#!/usr/bin/env python3
"""
Compare Route53 records against Ansible zone files to find unmanaged records.

Run from the repo root:
    python3 bin/r53_drift_check.py

Discovers task files by loading playbook.yml via Ansible's DataLoader,
extracting the roles list from each play, then recursively following
import_tasks/include_tasks directives from each role's tasks/main.yml.
This means any role added to the playbook is automatically included.

Uses Ansible's DataLoader (with vault decryption via the configured
vault_password_file) to load all group_vars, then Jinja2 to resolve
templates. This handles {{ loadbalancer_ip }}, loop item expansion,
and _zone-style block vars correctly.

Handles two Ansible task formats:
  1. Individual amazon.aws.route53 tasks (explicit zone/record/type/loop fields)
  2. _records list pattern (aquarionics/novelathon style) with a zone var and loop
"""

import glob
import os
import re
import sys

import boto3
from ansible import constants as C  # type: ignore[import]
from ansible.parsing.dataloader import DataLoader  # type: ignore[import]
from ansible.parsing.vault import get_file_vault_secret  # type: ignore[import]
from jinja2 import Environment, Undefined

PLAYBOOK = "playbook.yml"
ROLES_DIR = "roles"
GROUP_VARS_DIR = "group_vars/all"

SKIP_TYPES = {"NS", "SOA"}
AWS_PROFILES = ["aqcom", "istic"]


# ---------------------------------------------------------------------------
# Variable loading + Jinja2 rendering
# ---------------------------------------------------------------------------

def load_vars() -> tuple[DataLoader, dict]:
    """Load all group_vars (including vault) via Ansible's DataLoader."""
    loader = DataLoader()
    if C.DEFAULT_VAULT_PASSWORD_FILE:
        secret = get_file_vault_secret(C.DEFAULT_VAULT_PASSWORD_FILE, loader=loader)
        secret.load()
        loader.set_vault_secrets([("default", secret)])

    variables: dict = {}
    for path in sorted(glob.glob(os.path.join(GROUP_VARS_DIR, "*.yml"))):
        data = loader.load_from_file(path)
        if isinstance(data, dict):
            variables.update(data)
    return loader, variables


def make_renderer(base_vars: dict):
    """Return a render(template_str, extra_vars) function backed by Jinja2."""
    env = Environment(undefined=Undefined)

    def render(template_str: str, extra: dict | None = None) -> str:
        ctx = {**base_vars, **(extra or {})}
        try:
            return env.from_string(str(template_str)).render(**ctx)
        except Exception:  # pylint: disable=broad-exception-caught
            return str(template_str)

    return render


# ---------------------------------------------------------------------------
# Playbook-driven task file discovery
# ---------------------------------------------------------------------------

def _role_name(entry) -> str:
    """Extract role name from a play's roles list entry (string or dict)."""
    if isinstance(entry, str):
        return entry
    return entry.get("role", entry.get("name", ""))


class _TaskCollector:
    """Walks the task include graph, collecting file paths without duplicates."""

    _INCLUDE_KEYS = frozenset({
        "import_tasks", "include_tasks",
        "ansible.builtin.import_tasks", "ansible.builtin.include_tasks",
    })

    def __init__(self, loader: DataLoader, render):
        self.loader = loader
        self.render = render
        self.seen: set = set()
        self.files: list[str] = []

    def collect(self, filepath: str):
        """Load filepath and recursively follow all include directives."""
        if filepath in self.seen or not os.path.exists(filepath):
            return
        self.seen.add(filepath)
        self.files.append(filepath)

        try:
            tasks = self.loader.load_from_file(filepath)
        except Exception:  # pylint: disable=broad-exception-caught
            return

        if tasks and isinstance(tasks, list):
            self.follow(tasks, os.path.dirname(filepath))

    def follow(self, tasks: list, basedir: str):
        """Follow include directives in a task list, collecting referenced files."""
        for task in tasks:
            if not isinstance(task, dict):
                continue
            for key in self._INCLUDE_KEYS:
                if key in task and isinstance(task[key], str):
                    path = os.path.normpath(os.path.join(basedir, self.render(task[key])))
                    self.collect(path)
            for block_key in ("block", "rescue", "always"):
                if block_key in task and isinstance(task[block_key], list):
                    self.follow(task[block_key], basedir)


def discover_task_files(loader: DataLoader, render) -> list[str]:
    """
    Walk playbook.yml → roles → tasks/main.yml, following all
    import_tasks/include_tasks recursively. Returns all discovered task file paths.
    """
    playbook_data = loader.load_from_file(PLAYBOOK)
    if not playbook_data or not isinstance(playbook_data, list):
        return []

    collector = _TaskCollector(loader, render)
    for play in playbook_data:
        if not isinstance(play, dict):
            continue
        for role_entry in play.get("roles", []):
            role_name = _role_name(role_entry)
            if not role_name:
                continue
            main_path = os.path.join(ROLES_DIR, role_name, "tasks", "main.yml")
            collector.collect(main_path)

    return collector.files


# ---------------------------------------------------------------------------
# Route53 querying
# ---------------------------------------------------------------------------

_R53_WILDCARD = re.compile(r"\\052")


def normalize_r53_name(name: str) -> str:
    """Strip trailing dot and convert Route53 octal wildcard \\052 to *."""
    return _R53_WILDCARD.sub("*", name.rstrip("."))


def get_r53_records(profile: str) -> dict[str, set[tuple[str, str]]]:
    """Returns {zone: {(name, type)}} for all records in all hosted zones."""
    session = boto3.Session(profile_name=profile)
    client = session.client("route53")
    result: dict[str, set[tuple[str, str]]] = {}

    paginator = client.get_paginator("list_hosted_zones")
    for page in paginator.paginate():
        for zone in page["HostedZones"]:
            zone_name = zone["Name"].rstrip(".")
            zone_id = zone["Id"].split("/")[-1]
            records: set[tuple[str, str]] = set()

            rr_paginator = client.get_paginator("list_resource_record_sets")
            for rr_page in rr_paginator.paginate(HostedZoneId=zone_id):
                for rr in rr_page["ResourceRecordSets"]:
                    if rr["Type"] not in SKIP_TYPES:
                        records.add((normalize_r53_name(rr["Name"]), rr["Type"]))

            result[zone_name] = records
            print(f"  [{profile}] {zone_name}: {len(records)} records", file=sys.stderr)

    return result


# ---------------------------------------------------------------------------
# Ansible task file parsing
# ---------------------------------------------------------------------------

def normalize_record_name(name: str, zone: str) -> str:
    """Convert @ or relative name to absolute (without trailing dot)."""
    name = name.rstrip(".")
    if name == "@":
        return zone
    if not name.endswith("." + zone):
        return f"{name}.{zone}"
    return name


def parse_managed_records(
    task_files: list[str],
    loader: DataLoader,
    render,
) -> dict[str, set[tuple[str, str]]]:
    """Parse task files, returning {zone: {(name, type)}} for all route53 tasks."""
    managed: dict[str, set[tuple[str, str]]] = {}

    for filepath in task_files:
        try:
            tasks = loader.load_from_file(filepath)
        except Exception:  # pylint: disable=broad-exception-caught
            continue
        if not tasks or not isinstance(tasks, list):
            continue
        _extract_from_tasks(tasks, managed, render)

    return managed


def _add_records_list(records_list: list, zone: str, managed: dict, render, extra: dict):
    """Extract records from a _records list, skipping cf_only entries."""
    managed.setdefault(zone, set())
    for rec in records_list:
        if not isinstance(rec, dict) or "name" not in rec or "type" not in rec:
            continue
        if rec.get("cf_only"):
            continue
        raw_name = render(str(rec["name"]), extra)
        name = normalize_record_name(raw_name, zone)
        managed[zone].add((name, rec["type"]))


def _resolve_zone_from_vars(task_vars: dict, render, extra: dict) -> str | None:
    """Find and render the zone name from a task's vars block."""
    zone_raw = next(
        (v for k, v in task_vars.items() if k.endswith("zone") or k == "_zone"),
        None,
    )
    if zone_raw is None:
        for v in task_vars.values():
            if isinstance(v, str) and "." in v and " " not in v:
                zone_raw = v
                break
    return render(zone_raw, extra).rstrip(".") if zone_raw else None


def _handle_vars_block(task: dict, managed: dict, render, extra: dict):
    """Handle a block-with-vars task (_records list pattern)."""
    task_vars = task.get("vars", {})
    zone = _resolve_zone_from_vars(task_vars, render, extra)
    child_extra = {**extra, **({"_zone": zone} if zone else {})}
    for k, v in task_vars.items():
        if isinstance(v, str):
            child_extra[k] = render(v, extra)

    records_list = task_vars.get("_records", [])
    if zone and records_list:
        _add_records_list(records_list, zone, managed, render, child_extra)

    _extract_from_tasks(task.get("block", []), managed, render, child_extra)


def _handle_route53_task(task: dict, managed: dict, render, extra: dict):
    """Handle an individual amazon.aws.route53 task."""
    params = task["amazon.aws.route53"]
    zone = render(str(params.get("zone", "")), extra).rstrip(".")
    rtype = params.get("type")

    if not zone or not rtype or rtype in SKIP_TYPES:
        return

    managed.setdefault(zone, set())
    record_raw = str(params.get("record", ""))
    loop_items = task.get("loop") or task.get("with_items")

    if loop_items and "item" in record_raw:
        for item in loop_items:
            if isinstance(item, str):
                resolved = render(record_raw, {**extra, "item": item})
                managed[zone].add((resolved.rstrip("."), rtype))
    elif record_raw:
        managed[zone].add((render(record_raw, extra).rstrip("."), rtype))


def _extract_from_tasks(
    tasks: list,
    managed: dict,
    render,
    extra: dict | None = None,
):
    """Recursively extract route53 records from a task list."""
    extra = extra or {}

    for task in tasks:
        if not isinstance(task, dict):
            continue
        if "vars" in task and "block" in task:
            _handle_vars_block(task, managed, render, extra)
        elif "amazon.aws.route53" in task:
            _handle_route53_task(task, managed, render, extra)
        else:
            for key in ("block", "rescue", "always"):
                if key in task and isinstance(task[key], list):
                    _extract_from_tasks(task[key], managed, render, extra)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _print_report(
    all_r53: dict[str, tuple[str, set[tuple[str, str]]]],
    managed: dict[str, set[tuple[str, str]]],
):
    """Print drift and unmanaged-zone sections."""
    print("=" * 60)
    print("DRIFT REPORT: Records in Route53 NOT covered by Ansible")
    print("=" * 60)

    any_drift = False
    for zone in sorted(all_r53.keys()):
        profile, r53_records = all_r53[zone]
        unmanaged = r53_records - managed.get(zone, set())
        if not unmanaged:
            continue
        any_drift = True
        print(f"\n[{profile}] {zone}:")
        for name, rtype in sorted(unmanaged):
            print(f"  {name:<50} {rtype}")

    if not any_drift:
        print("\nNo drift found! All Route53 records are covered by Ansible.")

    print("\n" + "=" * 60)
    print("Zones in Route53 but NOT in Ansible:")
    print("=" * 60)
    for zone in sorted(all_r53.keys()):
        if zone not in managed:
            profile, _ = all_r53[zone]
            print(f"  [{profile}] {zone}")


def main():
    """Entry point: parse Ansible zones, query Route53, print drift report."""
    if not os.path.exists(PLAYBOOK):
        print(f"ERROR: {PLAYBOOK} not found. Run from the repo root.", file=sys.stderr)
        sys.exit(1)

    print("=== Loading Ansible variables ===", file=sys.stderr)
    loader, base_vars = load_vars()
    render = make_renderer(base_vars)
    print(f"  Loaded {len(base_vars)} variables from group_vars\n", file=sys.stderr)

    print("=== Discovering task files from playbook ===", file=sys.stderr)
    task_files = discover_task_files(loader, render)
    print(f"  Found {len(task_files)} task files\n", file=sys.stderr)

    print("=== Parsing Ansible task files ===", file=sys.stderr)
    managed = parse_managed_records(task_files, loader, render)
    print(f"  Found {len(managed)} zones in Ansible\n", file=sys.stderr)

    print("=== Querying Route53 ===", file=sys.stderr)
    all_r53: dict[str, tuple[str, set[tuple[str, str]]]] = {}
    for profile in AWS_PROFILES:
        try:
            for zone, records in get_r53_records(profile).items():
                all_r53[zone] = (profile, records)
        except Exception as e:  # pylint: disable=broad-exception-caught
            print(f"  ERROR with profile {profile}: {e}", file=sys.stderr)

    print(f"\nFound {len(all_r53)} zones in Route53\n", file=sys.stderr)
    _print_report(all_r53, managed)


if __name__ == "__main__":
    main()
