# Move certbot management into Ansible

Date: 2026-10-11

## Problem

Certificates on firth and atoll are issued by `bin/generate-firth-certbot.sh` and `bin/generate-atoll-certbot.sh`, pushed over ssh by `bin/update-all-certbots.sh`. Three things are wrong with that:

1. **Route53 auto-renewals fail.** The packaged `certbot.timer` runs `certbot renew` as root with no `AWS_PROFILE`. Certbot does not store the profile in a cert's renewal config, and the certs need different profiles (`aqcom`, `istic-r53`), so boto3 falls back to credentials for the wrong account. Observed: `Unable to find a Route53 hosted zone for _acme-challenge.nanocountdown.com`. Cloudflare certs renew fine because their credentials are a fixed file, `/root/.secrets/cloudflare.ini`.
   - Confirmed on firth: root's `~/.aws/credentials` has `default`, `aqcom` and `istic-r53` profiles, and `default` uses the same key as `aqcom`. A renewal with no `AWS_PROFILE` therefore uses the aqcom account. aqcom certs renew by accident, and `istic-r53` certs (such as `nanocountdown.com`) fail.
   - `istic-r53` and `default` are not created by the `aws_profiles` role, which defines only `aqcom` and `istic`. They were added by hand.
2. **The scripts can't see Ansible state.** They run on the remote host via `ssh bash -s`, so anything needing inventory variables (the atoll archive domain) has to be resolved elsewhere and passed in.
3. **The cert list lives outside Ansible.** nginx and dovecot templates already take a `cert_id` and point at `/etc/letsencrypt/live/<cert_id>/`, but which certs exist and which domains they cover is only in shell scripts. Adding a site needs two unrelated edits that people forget to do in order.

## Decisions

| Question | Decision |
|---|---|
| What issues and renews certs? | Keep certbot, driven by Ansible. Existing certs, renewal configs and `/etc/letsencrypt/live` paths stay as they are. |
| When does issuance run? | In the main playbook, tag `certbot`, before the nginx roles, so a new vhost's cert exists before `nginx -t` checks it. |
| Draft PR #341 (script rewrite) | Merge it first as the interim fix. This work is a new PR and uses #341's cert lists as its source data. |

Rejected: replacing certbot with `community.crypto` ACME modules. It would mean re-issuing every cert, owning storage paths and permissions, and writing our own renewal scheduling. Too much risk for what it buys.

## Design

### 1. Certs as data

Per host, in `host_vars/<host>/certbot.yml`:

```yaml
certbot_certs:
  - name: istic.net
    challenge: route53          # route53 | cloudflare | nginx
    aws_profile: istic-r53      # required for route53
    domains: [istic.net, "*.istic.net", istic.network, "*.istic.network"]
  - name: hubris.house
    challenge: route53
    aws_profile: aqcom
    domains: [hubris.house, "*.hubris.house"]
  - name: firth.water.gkhs.net
    challenge: nginx
    domains: [firth.water.gkhs.net, factionfiction.net]
certbot_certs_absent: []        # cert names to remove with `certbot delete`
```

- Domains are listed in full. There are no implicit wildcard defaults, so the data states exactly what is requested.
- `nginx` certs must not contain wildcards (http-01 cannot validate them). The role asserts this.
- The atoll archive cert is an entry whose domain is `{{ stream_delta_archive_public_domain }}`, guarded by `when:` that it is defined. This replaces the ssh env-var workaround.

### 2. `certbot` role

Runs before the nginx roles on firth and atoll (tag `certbot`). It depends on `water_gkhs_common`, which keeps installing the certbot packages and `/root/.secrets/cloudflare.ini`.

- For each entry in `certbot_certs`, runs `certbot certonly --non-interactive --expand --cert-name <name> <plugin args> -d <domain>...`.
  - Route53 entries run with `environment: AWS_PROFILE: <aws_profile>`.
  - Reports `changed` only when certbot output says a certificate was issued. An unchanged run is quick and reports `ok`.
- For each name in `certbot_certs_absent`, runs `certbot delete --cert-name <name>` if it exists. Removing an entry from `certbot_certs` alone does not delete anything from the host, so removals must be listed here.
- Reapplies the `root:certbot_access` ownership and group-read permissions on `/etc/letsencrypt`.

### 3. Service reloads: renewal-hooks directory

The role templates one script into `/etc/letsencrypt/renewal-hooks/deploy/`. Certbot runs it after any successful issuance of any cert. Per-host content comes from a variable (for example `certbot_deploy_commands`: firth reloads nginx and restarts dovecot, atoll reloads nginx).

This replaces the per-cert `--deploy-hook` from #341. Hooks given on the command line are saved in each cert's renewal config and only land when that cert is next issued. The directory hook applies to every cert immediately.

Cleanup: #341's `--deploy-hook` leaves a `renew_hook` line in the renewal config of every cert it issues. The role removes those lines (matching the exact #341 command) so services don't reload twice.

### 4. Renewal

- The role disables the packaged `certbot.timer`.
- It generates one oneshot service and one timer per renewal group:
  - one group per distinct `aws_profile` among the route53 certs,
  - one group for all cloudflare and nginx certs.
- Each service runs `certbot renew --cert-name <a> --cert-name <b> ...` for only its group's certs, with `AWS_PROFILE` set in the unit for route53 groups. This includes the `aqcom` group, so nothing depends on root's `default` profile any more. Timer cadence matches the stock timer (twice daily with a randomised delay).
- Each group succeeds or fails independently under systemd, so one broken profile cannot hide another.

### 5. Cleanup

- Delete `bin/generate-firth-certbot.sh`, `bin/generate-atoll-certbot.sh` and `bin/update-all-certbots.sh`.
- Update `docs/adding-sftp-hosted-site.md` and any other doc referencing the scripts: adding a cert means adding an entry to the host's `certbot.yml`.

## Migration

The riskiest step is the first run, because `certbot certonly --expand --cert-name X` with a different domain set reissues the cert with exactly the requested set. A mistake in the data could drop domains from a live cert.

1. Generate the initial `certbot_certs` data from the merged #341 scripts.
2. On each host, compare the data against `certbot certificates` and confirm every cert's domain set is identical.
3. Only then run `--tags certbot`.
4. Run `certbot renew --dry-run --cert-name ...` for each renewal group, with `AWS_PROFILE` set the way the unit sets it, to confirm renewal works under the new timers.

## Testing

- `ansible-lint` and `ansible-playbook --syntax-check` (both already enforced by pre-commit).
- Role assertions: nginx certs have no wildcards, every route53 cert has an `aws_profile`, cert names are unique, and each needed `aws_profile` has a section in `/root/.aws/credentials` (checked by section name only, so no secret is read into output).
- Manual verification on firth and atoll as in the Migration section. The role cannot meaningfully run under `--check`, since `command` tasks are skipped.

## Out of scope

- Replacing certbot with ACME modules.
- Changing how AWS profiles reach each host. The `aws_profiles` role is in the atoll play but not the firth play. The failing host was confirmed to have the profiles in root's `~/.aws`, and this design assumes they stay there. The role asserts that each `aws_profile` it needs exists in `/root/.aws/credentials` (section names only, never values).
- Alerting on renewal failure beyond what systemd and certbot already email.
