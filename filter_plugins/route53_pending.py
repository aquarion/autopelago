"""Ansible filter plugin to skip Route53 records that already match.

amazon.aws.route53 lists every hosted zone and then every record set in the
zone on each call, so looping it over N records costs 2N paginated API calls
even when nothing has changed. This filter compares the desired records with a
single amazon.aws.route53_info record_sets listing and returns only the
records the module would change, normalised into the module's argument shapes.

The comparison follows amazon.aws.route53's own (amazon.aws 11.x main()):
match on lower-cased name and type, then compare the whole record set. The one
deliberate difference is that hostnames in values (CNAME/NS/PTR targets, the
MX/SRV target field, alias targets) are compared case-insensitively and with
or without a trailing dot. DNS treats those as the same name, but the module
compares strings, so it reports such records as changed on every run.
Anything else that differs is returned and written exactly as given.

Desired records are dicts with:
  name   - relative to the zone, "@" for the apex; or
  record - a fully-qualified name; a missing trailing dot is added, as the
           module does
  type, value (string, comma-separated string or list)
  state  - present (default) or absent
  ttl    - default 300
  alias, alias_hosted_zone_id, alias_evaluate_target_health - optional
Other keys (e.g. Cloudflare-only flags) are ignored.
"""

from operator import itemgetter

from ansible.errors import AnsibleFilterError
from ansible.module_utils.common.dict_transformations import camel_dict_to_snake_dict
from ansible.module_utils.common.validation import check_type_list
from ansible.plugins.filter.core import FilterModule as FilterModuleBase

_DEFAULT_TTL = 300
# Types whose value ends in a hostname: the whole value, or its last field.
_HOSTNAME_TYPES = {"CNAME", "NS", "PTR", "MX", "SRV"}


def _canonical_host(value):
    """Lower-case the trailing hostname field of a value and make it absolute."""
    head, _, host = value.rpartition(" ")
    host = host.lower().rstrip(".") + "."
    return f"{head} {host}" if head else host


def _fqdn(item, zone):
    if "record" in item:
        fqdn = str(item["record"])
    elif str(item["name"]) == "@":
        fqdn = zone
    else:
        fqdn = f"{item['name']}.{zone}"
    # The module appends the trailing dot if it is missing.
    return fqdn.lower().rstrip(".") + "."


def _normalise(item, zone):
    try:
        state = {"present": "present", "create": "present", "absent": "absent", "delete": "absent"}[
            item.get("state", "present")
        ]
    except KeyError as e:
        raise AnsibleFilterError(f"route53_pending: unsupported state {e} for {item}") from e
    alias = bool(item.get("alias", False))
    return {
        "record": _fqdn(item, zone),
        "type": item["type"],
        "state": state,
        "ttl": int(item.get("ttl", _DEFAULT_TTL)),
        # The module declares value as list/elements=str, so a string is split
        # on commas; do the same so the comparison sees what the module sees.
        "value": [str(v) for v in check_type_list(item.get("value") or [])],
        "alias": alias,
        "alias_hosted_zone_id": item.get("alias_hosted_zone_id"),
        "alias_evaluate_target_health": bool(item.get("alias_evaluate_target_health", False)),
    }


def _wanted_record_set(rec):
    record_set = {"Name": rec["record"], "Type": rec["type"]}
    if rec["alias"]:
        record_set["AliasTarget"] = {
            "HostedZoneId": rec["alias_hosted_zone_id"],
            "DNSName": rec["value"][0],
            "EvaluateTargetHealth": rec["alias_evaluate_target_health"],
        }
    else:
        record_set["TTL"] = rec["ttl"]
        record_set["ResourceRecords"] = [{"Value": v} for v in rec["value"]]
    return camel_dict_to_snake_dict(record_set)


def _matches(rec, existing):
    if rec["alias"] and len(rec["value"]) != 1:
        return False  # let the module report the error
    wanted = _wanted_record_set(rec)
    have = dict(existing)
    if "alias_target" in wanted and "alias_target" in have:
        for side in (wanted, have):
            target = side["alias_target"]
            dns_name = _canonical_host(str(target.get("dns_name", "")))
            side["alias_target"] = dict(target, dns_name=dns_name)
    if rec["type"] in _HOSTNAME_TYPES:
        for side in (wanted, have):
            if "resource_records" in side:
                values = [_canonical_host(str(r["value"])) for r in side["resource_records"]]
                side["resource_records"] = [{"value": v} for v in values]
    if rec["type"] == "CAA":
        wanted["resource_records"] = sorted(wanted["resource_records"], key=itemgetter("value"))
        have["resource_records"] = sorted(have.get("resource_records", []), key=itemgetter("value"))
    return wanted == have


class FilterModule(FilterModuleBase):
    """Ansible filter plugin to find Route53 records that need changing."""

    def filters(self):
        """Return the filter functions provided by this plugin."""
        return {"route53_pending": self.route53_pending}

    def route53_pending(self, records, existing, zone):
        """Return the records in ``records`` that differ from ``existing``.

        ``existing`` is route53_info's ``resource_record_sets`` for ``zone``.
        """
        zone = str(zone).lower().rstrip(".")
        current = {}
        for record_set in existing:
            record_set = dict(record_set)
            # Route53 escapes "*" and other characters as \ooo octal. Names are
            # case-insensitive; the wanted side is lower-cased too.
            record_set["name"] = record_set["name"].encode().decode("unicode_escape").lower()
            current.setdefault((record_set["name"], record_set["type"]), record_set)

        pending = []
        for item in records:
            rec = _normalise(item, zone)
            found = current.get((rec["record"], rec["type"]))
            if rec["state"] == "absent":
                if found is not None:
                    pending.append(rec)
            elif found is None or not _matches(rec, found):
                pending.append(rec)
        return pending
