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
    ssl_snippet: istic          # optional: also generates /etc/nginx/snippets/ssl/istic_ssl.conf
    challenge: route53          # route53 | cloudflare | nginx
    aws_profile: istic          # required for route53; must be a profile the aws_profiles role creates (aqcom | istic)
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

### 1b. AWS profiles are managed by Ansible on every host that issues route53 certs

Today `aws_profiles` runs on the workstation, on atoll (under `become`, so root's `~/.aws`), and in `deploy-stream-delta.yml`. It never runs on firth, so firth's root profiles (`default`, `aqcom`, `istic-r53`) are hand-maintained. The role also creates `istic`, not `istic-r53`, and `firth_dns` already uses `istic` throughout. The `istic-r53` key on firth was confirmed to be the same key as the vault's `istic_aws_key`.

- Move `aws_profiles` into the "Actions on all external hosts" play (which has `become: true`), before the `certbot` role, and remove the atoll-only entry from the Atoll play. Every external host (firth, atoll, and any added later) then gets root's `~/.aws` from the vault. The workstation keeps getting it from the existing local `AWS Roles` play. It is deliberately not added to the `hosts: all` play, since `become` there would write to root's `~/.aws` on the workstation.
- `certbot_certs` uses the role's names: `aqcom` and `istic`. Nothing uses `istic-r53` any more.
- Cleanup (explicit, since removing config doesn't delete anything from the host): remove the `istic-r53` section from root's `~/.aws/credentials` and `config` on firth and, if present, atoll. Leave `default` alone: other root processes may rely on it, and the renewal units no longer do.
- The `certbot` role asserts each `aws_profile` it needs exists in `/root/.aws/credentials` (section names only, no values), so a missing profile fails fast with a clear message instead of a Route53 "hosted zone not found" error at renewal time.

### 2. `certbot` role

Runs before the nginx roles on firth and atoll (tag `certbot`). It depends on `water_gkhs_common`, which keeps installing the certbot packages and `/root/.secrets/cloudflare.ini`.

- For each entry in `certbot_certs`, runs `certbot certonly --non-interactive --expand --cert-name <name> <plugin args> -d <domain>...`.
  - Route53 entries run with `environment: AWS_PROFILE: <aws_profile>`.
  - Reports `changed` only when the cert's `fullchain.pem` checksum differs before and after the run (a `stat` before and after, with `changed_when` on the second). It does not parse certbot's output, so it doesn't depend on certbot's wording, and it also catches a first-time issuance. An unchanged run is quick and reports `ok`.
- For each name in `certbot_certs_absent`, runs `certbot delete --cert-name <name>` if it exists. Removing an entry from `certbot_certs` alone does not delete anything from the host, so removals must be listed here.
- Reapplies the `root:certbot_access` ownership and group-read permissions on `/etc/letsencrypt`.

### 3. Service reloads: renewal-hooks directory

The role templates one script into `/etc/letsencrypt/renewal-hooks/deploy/`. Certbot runs it after any renewal of an existing cert, whether via `certbot renew` or `certbot certonly` on an existing cert name (for example when expanding its domains). It does not run when a cert is first created. That is fine: a new cert is referenced by nothing until its nginx SSL snippet is deployed, and that step validates and reloads nginx. Per-host content comes from a variable (for example `certbot_deploy_commands`: firth reloads nginx and restarts dovecot, atoll reloads nginx).

This replaces the per-cert `--deploy-hook` from #341. Hooks given on the command line are saved in each cert's renewal config and only land when that cert is next issued. The directory hook applies to every cert immediately.

Cleanup: #341's `--deploy-hook` leaves a `renew_hook` line in the renewal config of every cert it issues. The role removes those lines (matching the exact #341 command) so services don't reload twice.

### 4. Renewal

- The role disables the packaged `certbot.timer`.
- It generates one oneshot service and one timer per renewal group:
  - one group per distinct `aws_profile` among the route53 certs,
  - one group for all cloudflare and nginx certs.
- Each service runs `certbot renew --cert-name <a> --cert-name <b> ...` for only its group's certs, with `AWS_PROFILE` set in the unit for route53 groups. This includes the `aqcom` group, so nothing depends on root's `default` profile any more. Timer cadence matches the stock timer (twice daily with a randomised delay).
- Each group succeeds or fails independently under systemd, so one broken profile cannot hide another.

### 5. nginx SSL snippets

The 17 SSL snippets in `firth_nginx` and `atoll_nginx` are all the same four directives (certificate, key, session cache, session timeout) and differ only in the cert name. Five on firth are already generated from a loop that duplicates cert names kept in the certbot script, so adding a site means editing two unrelated places.

- A cert entry with an `ssl_snippet` field gets `/etc/nginx/snippets/ssl/<ssl_snippet>_ssl.conf`, generated by the `certbot` role from one template. `ssl_snippet` keeps each snippet's existing filename (for example `istic`, `larpme`, `pddiscourse`, `delta`), because vhosts include them by name. No vhost changes.
- A change validates the nginx config (`nginx -t`) and then reloads nginx. Firth's old tasks restarted it, but a changed cert path only needs a reload.
- `letsencrypt_ssl.conf` stays a static file in `firth_nginx`: it points at `{{ letsencrypt_dir }}`, which exim and dovecot also use.
- `atoll_ssl.conf` is dead (no vhost includes it, and the host it names does not exist). It is deleted from atoll with an explicit `certbot_ssl_snippets_absent` entry, since deleting the template does not remove the deployed file.
- The generated files are checked against the deployed ones before the old definitions are removed: normalised for whitespace, every snippet must be identical, except the removed `atoll_ssl.conf`.
- This runs as the last step, after the cert and renewal work has been proven on both hosts, so a snippet problem can't be confused with an issuance or renewal problem.

### 6. Cleanup

- Delete `bin/generate-firth-certbot.sh`, `bin/generate-atoll-certbot.sh` and `bin/update-all-certbots.sh`.
- Update `docs/adding-sftp-hosted-site.md` and any other doc referencing the scripts: adding a cert (and its nginx SSL snippet) means adding one entry to the host's `certbot.yml`.

## Migration

The riskiest step is the first run, because `certbot certonly --expand --cert-name X` with a different domain set reissues the cert with exactly the requested set. A mistake in the data could drop domains from a live cert.

0. Run `aws_profiles` on the external hosts (`--tags aws`) so root has the `aqcom` and `istic` profiles, then check `AWS_PROFILE=istic certbot renew --dry-run --cert-name nanocountdown.com` succeeds before changing any cert data. The `istic-r53` cleanup waits until after the new renewal units have run successfully.
1. Generate the initial `certbot_certs` data from the merged #341 scripts, translating `istic-r53` to `istic`.
2. On each host, compare the data against `certbot certificates` and confirm every cert's domain set is identical.
3. Only then run `--tags certbot`.
4. Run `certbot renew --dry-run --cert-name ...` for each renewal group, with `AWS_PROFILE` set the way the unit sets it, to confirm renewal works under the new timers.
5. Only then generate the nginx SSL snippets: snapshot each deployed snippet's directives, run `--tags certbot`, snapshot again and confirm they are identical (apart from the deleted `atoll_ssl.conf`) and `nginx -t` passes. Remove the old static snippets and loop afterwards, and rerun `--tags nginx` to confirm nothing changed.

## Testing

- `ansible-lint` and `ansible-playbook --syntax-check` (both already enforced by pre-commit).
- Role assertions: every cert on the host (`/etc/letsencrypt/renewal/*.conf`) is in `certbot_certs` or `certbot_certs_absent` (the role replaces the packaged timer that renewed everything, so an unlisted cert would silently stop renewing), nginx certs have no wildcards, every route53 cert has an `aws_profile`, cert names are unique, and each needed `aws_profile` has a section in `/root/.aws/credentials` (checked by section name only, so no secret is read into output).
- Manual verification on firth and atoll as in the Migration section. The role cannot meaningfully run under `--check`, since `command` tasks are skipped.

## Out of scope

- Replacing certbot with ACME modules.
- Rotating the AWS keys, or removing the hand-added `default` profile.
- Followup idea: once every external host has the profiles, the Route53 DNS tasks (`firth_dns`, `aws_pdforums`) could run on a host instead of the `localactions` workstation play, which would remove the need to run the AWS roles locally. boto3 is already installed on every host (`water_gkhs_common`, and certbot's route53 plugin needs it), so the remaining work is moving the plays and is a separate change.
- Alerting on renewal failure beyond what systemd and certbot already email.
