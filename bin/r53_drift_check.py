#!/usr/bin/env python3
"""
Compare Route53 records against Ansible zone files to find unmanaged records.

Run from the repo root:
    python3 bin/r53_drift_check.py

Handles two Ansible task formats:
  1. Individual amazon.aws.route53 tasks with explicit zone/record/type fields
  2. _records list pattern (aquarionics/novelathon style) with _zone var and loop
"""

import glob
import os
import sys

import boto3
import yaml

ZONES_DIR = "roles/firth_dns/tasks/zones"

# Skip these record types - Route53 auto-manages them
SKIP_TYPES = {"NS", "SOA"}

# AWS profiles to check
AWS_PROFILES = ["aqcom", "istic"]


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
                    rtype = rr["Type"]
                    if rtype in SKIP_TYPES:
                        continue
                    name = rr["Name"].rstrip(".")
                    records.add((name, rtype))

            result[zone_name] = records
            print(f"  [{profile}] {zone_name}: {len(records)} records", file=sys.stderr)

    return result


def normalize_record_name(name: str, zone: str) -> str:
    """Convert @ or relative name to absolute (without trailing dot)."""
    if name == "@":
        return zone
    if not name.endswith("." + zone) and not name.endswith("."):
        return f"{name}.{zone}"
    return name.rstrip(".")


def parse_ansible_zones(zones_dir: str) -> dict[str, set[tuple[str, str]]]:
    """
    Parse all zone YAML files, returning {zone: {(name, type)}}.
    Covers both individual task format and _records list format.
    """
    managed: dict[str, set[tuple[str, str]]] = {}

    for filepath in sorted(glob.glob(os.path.join(zones_dir, "*.yml"))):
        filename = os.path.basename(filepath)
        with open(filepath, encoding="utf-8") as f:
            try:
                tasks = yaml.safe_load(f)
            except yaml.YAMLError as e:
                print(f"  WARN: could not parse {filename}: {e}", file=sys.stderr)
                continue

        if not tasks or not isinstance(tasks, list):
            continue

        _extract_from_tasks(tasks, managed, filename)

    return managed


def _add_records_list(records_list: list, zone: str, managed: dict):
    """Extract records from a _records list into managed, skipping cf_only entries."""
    managed.setdefault(zone, set())
    for rec in records_list:
        if isinstance(rec, dict) and "name" in rec and "type" in rec and not rec.get("cf_only"):
            name = normalize_record_name(str(rec["name"]), zone)
            managed[zone].add((name, rec["type"]))


def _extract_from_tasks(
    tasks: list,
    managed: dict,
    filename: str,
    inherited_zone: str | None = None,
):
    """Recursively extract route53 records from a task list."""
    for task in tasks:
        if not isinstance(task, dict):
            continue

        # _records list pattern (aquarionics/novelathon style)
        if "vars" in task and "block" in task:
            zone = task.get("vars", {}).get("_zone", inherited_zone)
            records_list = task.get("vars", {}).get("_records", [])
            if zone and records_list:
                _add_records_list(records_list, zone, managed)
            _extract_from_tasks(
                task.get("block", []), managed, filename, zone or inherited_zone
            )
            continue

        # Individual amazon.aws.route53 task
        if "amazon.aws.route53" in task:
            params = task["amazon.aws.route53"]
            zone = params.get("zone", "").rstrip(".")
            record = params.get("record", "").rstrip(".")
            rtype = params.get("type")
            if zone and record and rtype and rtype not in SKIP_TYPES:
                managed.setdefault(zone, set())
                managed[zone].add((record, rtype))
            continue

        # Recurse into block/rescue/always
        for key in ("block", "rescue", "always"):
            if key in task and isinstance(task[key], list):
                _extract_from_tasks(task[key], managed, filename, inherited_zone)


def main():
    """Entry point: parse Ansible zones, query Route53, print drift report."""
    if not os.path.isdir(ZONES_DIR):
        print(f"ERROR: {ZONES_DIR} not found. Run from the repo root.", file=sys.stderr)
        sys.exit(1)

    print("=== Parsing Ansible zone files ===", file=sys.stderr)
    managed = parse_ansible_zones(ZONES_DIR)
    print(f"Found {len(managed)} zones in Ansible\n", file=sys.stderr)

    print("=== Querying Route53 ===", file=sys.stderr)
    all_r53: dict[str, tuple[str, set[tuple[str, str]]]] = {}
    for profile in AWS_PROFILES:
        try:
            for zone, records in get_r53_records(profile).items():
                all_r53[zone] = (profile, records)
        except Exception as e:  # pylint: disable=broad-exception-caught
            print(f"  ERROR with profile {profile}: {e}", file=sys.stderr)

    print(f"\nFound {len(all_r53)} zones in Route53\n", file=sys.stderr)

    print("=" * 60)
    print("DRIFT REPORT: Records in Route53 NOT covered by Ansible")
    print("=" * 60)

    any_drift = False
    for zone in sorted(all_r53.keys()):
        profile, r53_records = all_r53[zone]
        ansible_records = managed.get(zone, set())

        unmanaged = r53_records - ansible_records
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


if __name__ == "__main__":
    main()
