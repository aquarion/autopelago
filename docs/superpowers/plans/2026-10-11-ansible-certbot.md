# Ansible-Managed Certbot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `bin/generate-*-certbot.sh` and `bin/update-all-certbots.sh` with an Ansible `certbot` role that issues certs from per-host data and renews each route53 profile with the right `AWS_PROFILE`.

**Architecture:** A new `certbot` role (tag `certbot`) loops over `certbot_certs` (host_vars data) running `certbot certonly`, installs one deploy hook in `/etc/letsencrypt/renewal-hooks/deploy/`, and generates one systemd renewal service + timer per renewal group (one per AWS profile, plus one for cloudflare/nginx certs), replacing the packaged `certbot.timer`. `aws_profiles` moves to the "all external hosts" play so root's `~/.aws` is Ansible-managed everywhere. A final task generates the nginx SSL snippets from the same data (Task 12).

**Tech Stack:** Ansible (ansible-lint + pre-commit enforced), certbot (apt) with the route53, cloudflare and nginx plugins, systemd units, Jinja2 templates.

**Spec:** `docs/superpowers/specs/2026-10-11-ansible-certbot-design.md`

**Conventions used throughout**
- Commit messages are prefixed with an emoji (🎇 new feature, ❌ removal, 📖 docs, 🔄️ change) and end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Never commit to `main`. Check with `git branch --show-current` before every commit.
- Pre-commit runs ansible-lint, check-yaml, trailing-whitespace and end-of-file fixers on commit. If a hook modifies files, re-run `git add` and commit again.
- Role task style follows `roles/otel_hostmetrics/tasks/main.yml` (FQCN modules, `tags`, `become`) and `roles/firth_sftp_docker/tasks/main.yml` (systemd units: template then `notify: Reload systemd`).
- `host_vars/` and `group_vars/` are excluded from ansible-lint (see `.ansible-lint`).

---

## File Structure

| File | Responsibility |
|---|---|
| `roles/certbot/defaults/main.yml` | Role variable defaults and the per-challenge certbot plugin arguments |
| `roles/certbot/tasks/main.yml` | Imports the other task files in order |
| `roles/certbot/tasks/validate.yml` | Asserts `certbot_certs` is well-formed and each needed AWS profile exists in root's credentials |
| `roles/certbot/tasks/hooks.yml` | Installs the deploy hook script; strips the per-cert `renew_hook` lines the old scripts saved |
| `roles/certbot/tasks/issue.yml` | Loops over `certbot_certs`, deletes `certbot_certs_absent`, fixes `/etc/letsencrypt` permissions |
| `roles/certbot/tasks/issue_cert.yml` | Issues one cert and reports `changed` only if its `fullchain.pem` checksum changed |
| `roles/certbot/tasks/renewal.yml` | Disables `certbot.timer`; generates, enables and prunes per-group renewal units |
| `roles/certbot/templates/reload-services.j2.sh` | The deploy hook (named `.j2.sh` so shfmt skips it, per `.pre-commit-config.yaml`) |
| `roles/certbot/templates/certbot-renew.service.j2` | One renewal service per group |
| `roles/certbot/templates/certbot-renew.timer.j2` | One renewal timer per group |
| `roles/certbot/templates/nginx-ssl-snippet.conf.j2` | The 4-line nginx SSL snippet (Task 12) |
| `roles/certbot/tasks/nginx_snippets.yml` | Generates `/etc/nginx/snippets/ssl/<stem>_ssl.conf` from `certbot_certs` (Task 12) |
| `roles/certbot/handlers/main.yml` | Validates nginx config, then reloads it, after snippet changes (Task 12) |
| `roles/certbot/tests/render.yml` | Renders the templates with sample data and asserts on the output |
| `roles/certbot/files/certbot-renew-group.sh` | Helper installed as `/usr/local/sbin/certbot-renew-group`: runs `certbot renew` once per cert (`--cert-name` takes one value), continues after failures, exits non-zero if any failed |
| `roles/certbot/tests/renew-group.sh` | Tests the helper against a fake `certbot` (all certs attempted in order; exit status reflects failures) |
| `host_vars/firth.water.gkhs.net/certbot.yml` | Firth's certs, as data |
| `host_vars/atoll.water.gkhs.net/certbot.yml` | Atoll's certs, as data (including the archive cert) |
| `playbook.yml` | Move `aws_profiles`; add the certbot play |
| `roles/aws_profiles/tasks/main.yml` | Remove the legacy `istic-r53` profile (last task, after verification) |
| `docs/adding-sftp-hosted-site.md` | Point at `certbot.yml` instead of the scripts and the snippet loop |
| `roles/firth_nginx/tasks/main.yml`, `roles/atoll_nginx/tasks/main.yml` | Drop the snippet-generating tasks (Task 12); firth keeps the static `letsencrypt_ssl.conf` task |
| `roles/firth_nginx/templates/ssl*`, `roles/atoll_nginx/templates/ssl/` | Static snippets and `ssl.nginx.conf.j2` deleted (Task 12); `letsencrypt_ssl.conf` stays |
| `bin/generate-firth-certbot.sh`, `bin/generate-atoll-certbot.sh`, `bin/update-all-certbots.sh` | Deleted |

---

### Task 0: Preconditions

**Files:** none

- [ ] **Step 1: Confirm PR #341 is merged**

Run: `gh pr view 341 --json state,mergedAt --jq '.state + " " + (.mergedAt // "")'`
Expected: `MERGED <timestamp>`. If it prints `OPEN` or `DRAFT`, stop and get #341 merged first. The cert data in Task 7 is taken from the scripts as merged.

- [ ] **Step 2: Rebase the work branch onto main**

```bash
git fetch origin
git checkout feature/ansible-certbot
git branch --show-current   # expect: feature/ansible-certbot
git rebase origin/main
```
Expected: rebase finishes without conflicts. (The branch holds only spec commits, so it should replay cleanly. If `git rebase` reports that commits were already applied, that's fine.)

- [ ] **Step 3: Confirm the toolchain**

Run: `ansible --version | head -1 && ansible-lint --version | head -1`
Expected: both print a version. Run `direnv allow` in the repo root if `ansible` is not found.

---

### Task 1: Templates and their render test (test first)

**Files:**
- Create: `roles/certbot/tests/render.yml`
- Create: `roles/certbot/templates/reload-services.j2.sh`
- Create: `roles/certbot/templates/certbot-renew.service.j2`
- Create: `roles/certbot/templates/certbot-renew.timer.j2`

- [ ] **Step 1: Write the failing render test**

Create `roles/certbot/tests/render.yml`:

```yaml
---
# Renders the certbot role templates with sample data and checks the output.
# Run: CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml
- name: Render certbot role templates
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    certbot_test_dir: "{{ lookup('ansible.builtin.env', 'CERTBOT_TEST_DIR') }}"
    certbot_templates: "{{ playbook_dir }}/../templates"
    certbot_deploy_commands:
      - service nginx reload
      - service dovecot restart
  tasks:
    - name: Require a scratch directory
      ansible.builtin.assert:
        that: certbot_test_dir | length > 0
        fail_msg: Set CERTBOT_TEST_DIR to an empty scratch directory.

    - name: Render the deploy hook
      ansible.builtin.template:
        src: "{{ certbot_templates }}/reload-services.j2.sh"
        dest: "{{ certbot_test_dir }}/reload-services.sh"
        mode: "0755"

    - name: Render a route53 group service
      ansible.builtin.template:
        src: "{{ certbot_templates }}/certbot-renew.service.j2"
        dest: "{{ certbot_test_dir }}/aws-istic.service"
        mode: "0644"
      vars:
        certbot_group_name: aws-istic
        certbot_group_profile: istic
        certbot_group_certs: [istic.net, nanocountdown.com]

    - name: Render the default group service
      ansible.builtin.template:
        src: "{{ certbot_templates }}/certbot-renew.service.j2"
        dest: "{{ certbot_test_dir }}/default.service"
        mode: "0644"
      vars:
        certbot_group_name: default
        certbot_group_profile: ""
        certbot_group_certs: [socksandpuppets.com]

    - name: Render a group timer
      ansible.builtin.template:
        src: "{{ certbot_templates }}/certbot-renew.timer.j2"
        dest: "{{ certbot_test_dir }}/aws-istic.timer"
        mode: "0644"
      vars:
        certbot_group_name: aws-istic

    - name: Read the rendered files
      ansible.builtin.slurp:
        src: "{{ certbot_test_dir }}/{{ item }}"
      register: certbot_rendered
      loop: [reload-services.sh, aws-istic.service, default.service, aws-istic.timer]

    - name: Check the rendered output
      ansible.builtin.assert:
        that:
          - "'service nginx reload || rc=$?\n' in (certbot_rendered.results[0].content | b64decode)"
          - "'service dovecot restart || rc=$?\n' in (certbot_rendered.results[0].content | b64decode)"
          - "'rc=0\n' in (certbot_rendered.results[0].content | b64decode)"
          - "'exit $rc\n' in (certbot_rendered.results[0].content | b64decode)"
          - "'Environment=AWS_PROFILE=istic\n' in (certbot_rendered.results[1].content | b64decode)"
          - "'Type=oneshot' in (certbot_rendered.results[1].content | b64decode)"
          - "'Environment=' not in (certbot_rendered.results[2].content | b64decode)"
          - "'ExecStart=/usr/local/sbin/certbot-renew-group istic.net nanocountdown.com\n' in (certbot_rendered.results[1].content | b64decode)"
          - "'AWS_PROFILE' not in (certbot_rendered.results[2].content | b64decode)"
          - "'ExecStart=/usr/local/sbin/certbot-renew-group socksandpuppets.com\n' in (certbot_rendered.results[2].content | b64decode)"
          - "'OnCalendar=' in (certbot_rendered.results[3].content | b64decode)"
          - "'Persistent=true' in (certbot_rendered.results[3].content | b64decode)"
          - "'(aws-istic)' in (certbot_rendered.results[3].content | b64decode)"
        fail_msg: Rendered certbot templates do not match expectations.
```

- [ ] **Step 2: Run it to verify it fails**

Run: `CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml 2>&1 | tail -15`
Expected: FAIL on "Render the deploy hook" with a "Could not find or access ... reload-services.j2.sh" error (the templates don't exist yet).

- [ ] **Step 3: Write the deploy hook template**

Create `roles/certbot/templates/reload-services.j2.sh`:

```sh
#!/bin/sh
# {{ ansible_managed }}
# Run by certbot after a renewal of an existing certificate.
# Every command runs even if an earlier one fails; the exit status reports any failure.
rc=0
{% for cmd in certbot_deploy_commands %}
{{ cmd }} || rc=$?
{% endfor %}
exit $rc
```

- [ ] **Step 4: Write the renewal service template**

Create `roles/certbot/templates/certbot-renew.service.j2`:

```ini
# {{ ansible_managed }}
[Unit]
Description=Renew Let's Encrypt certificates ({{ certbot_group_name }})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
{% if certbot_group_profile | length > 0 %}
Environment=AWS_PROFILE={{ certbot_group_profile }}
{% endif %}
ExecStart=/usr/local/sbin/certbot-renew-group{% for cert in certbot_group_certs %} {{ cert }}{% endfor %}

```

- [ ] **Step 5: Write the renewal timer template**

Create `roles/certbot/templates/certbot-renew.timer.j2`:

```ini
# {{ ansible_managed }}
[Unit]
Description=Twice-daily renewal of Let's Encrypt certificates ({{ certbot_group_name }})

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=43200
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml 2>&1 | tail -8`
Expected: `localhost : ok=7 changed=4 ... failed=0` (changed count may vary) and no failed assertion.

If the `ExecStart=` assertion fails, check that the rendered line ends with a newline immediately after the last cert name (the blank line at the end of the service template is what guarantees this).

- [ ] **Step 7: Lint and commit**

```bash
ansible-lint roles/certbot/tests/render.yml
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot
git commit -m "🎇 Add certbot role templates with a render test

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
Expected: ansible-lint prints no violations; the commit succeeds (re-run `git add` and commit if a hook reformatted files).

---

### Task 2: Role defaults and validation

**Files:**
- Create: `roles/certbot/defaults/main.yml`
- Create: `roles/certbot/tasks/validate.yml`

- [ ] **Step 1: Write the defaults**

Create `roles/certbot/defaults/main.yml`:

```yaml
---
# Certificates to issue on this host. See docs/superpowers/specs/2026-10-11-ansible-certbot-design.md.
# Each entry: name, challenge (route53 | cloudflare | nginx), domains, and aws_profile (route53 only).
certbot_certs: []

# Cert names to remove with `certbot delete`. Removing an entry from certbot_certs does NOT
# delete the cert from the host, so list removals here.
certbot_certs_absent: []

# nginx SSL snippet stems (file /etc/nginx/snippets/ssl/<stem>_ssl.conf) to delete from the host.
certbot_ssl_snippets_absent: []

# Commands the deploy hook runs after a renewal of an existing cert (set per host).
certbot_deploy_commands: []

# Per-cert `renew_hook` values saved by the old bin/generate-*-certbot.sh scripts (--deploy-hook).
# The role strips these from renewal configs so services are not reloaded twice.
certbot_legacy_deploy_hooks:
  - service nginx reload; service dovecot restart
  - service nginx reload

certbot_plugin_args:
  route53:
    - --dns-route53
    - --preferred-challenges
    - dns-01
  cloudflare:
    - --dns-cloudflare
    - --dns-cloudflare-credentials
    - /root/.secrets/cloudflare.ini
    - --preferred-challenges
    - dns-01
  nginx:
    - --nginx
    - --preferred-challenges
    - http-01

certbot_aws_credentials_file: /root/.aws/credentials
```

- [ ] **Step 2: Write the validation tasks**

Create `roles/certbot/tasks/validate.yml`:

```yaml
---
- name: Validate certbot_certs entries
  ansible.builtin.assert:
    that:
      - certbot_certs | selectattr('name', 'undefined') | list | length == 0
      - certbot_certs | selectattr('challenge', 'undefined') | list | length == 0
      - certbot_certs | selectattr('domains', 'undefined') | list | length == 0
      - certbot_certs | map(attribute='name') | list | intersect(certbot_certs_absent) | length == 0
      - certbot_certs | selectattr('domains', 'defined') | map(attribute='domains') | map('length') | select('equalto', 0) | list | length == 0
      - certbot_certs | map(attribute='challenge') | difference(['route53', 'cloudflare', 'nginx']) | length == 0
      - (certbot_certs | map(attribute='name') | list | length) == (certbot_certs | map(attribute='name') | unique | list | length)
      - certbot_certs | selectattr('challenge', 'equalto', 'route53') | rejectattr('aws_profile', 'defined') | list | length == 0
      - certbot_certs | selectattr('challenge', 'equalto', 'nginx') | map(attribute='domains') | flatten | select('match', '^\*\.') | list | length == 0
      - (certbot_certs | selectattr('ssl_snippet', 'defined') | map(attribute='ssl_snippet') | list | length) == (certbot_certs | selectattr('ssl_snippet',
        'defined') | map(attribute='ssl_snippet') | unique | list | length)
    fail_msg: >-
      certbot_certs is malformed. Every entry needs name, challenge (route53|cloudflare|nginx) and domains;
      names must be unique and must not also be in certbot_certs_absent; domains must be a non-empty list; route53 entries need aws_profile; nginx entries cannot
      contain wildcards
      (http-01 cannot validate them); ssl_snippet values must be unique.
  tags: certbot

- name: Check required AWS profiles exist in root's credentials (section names only)
  ansible.builtin.command:
    argv: [grep, -q, -x, -F, "[{{ item }}]", "{{ certbot_aws_credentials_file }}"]
  loop: "{{ certbot_certs | selectattr('challenge', 'equalto', 'route53') | map(attribute='aws_profile') | unique | list }}"
  register: certbot_profile_check
  changed_when: false
  failed_when: false
  check_mode: false
  tags: certbot

- name: Fail if an AWS profile is missing
  ansible.builtin.assert:
    that: certbot_profile_check.results | map(attribute='rc') | select('ne', 0) | list | length == 0
    fail_msg: >-
      AWS profile(s) missing from {{ certbot_aws_credentials_file }}:
      {{ certbot_profile_check.results | rejectattr('rc', 'equalto', 0) | map(attribute='item') | list }}.
      Run the aws_profiles role first (--tags aws_profiles).
  tags: certbot

# The role replaces the packaged certbot.timer, which renewed EVERY cert on the host. A cert that
# exists on the host but is not in certbot_certs would silently stop renewing, so fail instead.
- name: Find the certs certbot already has on this host
  ansible.builtin.find:
    paths: /etc/letsencrypt/renewal
    patterns: "*.conf"
  register: certbot_renewal_confs
  tags: certbot

- name: Fail if the host has certs this role does not manage (they would stop renewing)
  ansible.builtin.assert:
    that: >-
      (certbot_renewal_confs.files | map(attribute='path') | map('basename') | map('regex_replace', '\\.conf$', '')
       | difference(certbot_certs | map(attribute='name') | list) | difference(certbot_certs_absent)) | length == 0
    fail_msg: >-
      These certs exist on the host but are not in certbot_certs or certbot_certs_absent, so nothing would renew them:
      {{ certbot_renewal_confs.files | map(attribute='path') | map('basename') | map('regex_replace', '\\.conf$', '')
         | difference(certbot_certs | map(attribute='name') | list) | difference(certbot_certs_absent) | list }}.
      Add each to certbot_certs, or to certbot_certs_absent if it should be deleted.
  tags: certbot
```

- [ ] **Step 3: Lint**

Run: `ansible-lint roles/certbot`
Expected: no violations. (The role has no `tasks/main.yml` yet; lint only checks the files that exist. If it complains about a missing `main.yml`, continue to Task 6 and re-lint there.)

- [ ] **Step 4: Check the assertions against bad data**

Create a throwaway playbook outside the repo's role dir and run it. Use the scratchpad directory, not the repo:

```bash
SCRATCH=$(mktemp -d)
cat > "$SCRATCH/validate_test.yml" <<'EOF'
---
- name: Validation rejects bad data
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files: []
  tasks:
    - name: Duplicate names and a wildcard on nginx must fail validation
      block:
        - name: Run the role's validation
          ansible.builtin.include_role:
            name: certbot
            tasks_from: validate.yml
          vars:
            certbot_certs:
              - { name: a.example, challenge: nginx, domains: ["*.a.example"] }
              - { name: a.example, challenge: route53, domains: [a.example] }
        - name: Validation should not have passed
          ansible.builtin.fail:
            msg: Validation accepted bad data.
      rescue:
        - name: Confirm the failure came from validation
          ansible.builtin.assert:
            that: "'certbot_certs is malformed' in ansible_failed_result.msg"
EOF
ANSIBLE_ROLES_PATH="$PWD/roles" ansible-playbook "$SCRATCH/validate_test.yml" 2>&1 | tail -12
```
Expected: the validate task prints a failure containing `certbot_certs is malformed`, which the `rescue` block catches, and the playbook ends `failed=0`, `rescued=1`. If it ends with `Validation accepted bad data`, the assertions in `validate.yml` are too weak.

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot
git commit -m "🎇 Add certbot role defaults and input validation

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Deploy hook installation and legacy hook cleanup

**Files:**
- Create: `roles/certbot/tasks/hooks.yml`

- [ ] **Step 1: Write the tasks**

Create `roles/certbot/tasks/hooks.yml`:

```yaml
---
- name: Ensure the certbot deploy hook directory exists
  ansible.builtin.file:
    path: /etc/letsencrypt/renewal-hooks/deploy
    state: directory
    owner: root
    group: root
    mode: "0755"
  tags: certbot

- name: Install the deploy hook that reloads services after a renewal
  ansible.builtin.template:
    src: reload-services.j2.sh
    dest: /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
    owner: root
    group: root
    mode: "0755"
  tags: certbot

# certbot_renewal_confs is registered in validate.yml (which always runs first).
# The old scripts passed --deploy-hook, which certbot saves into each cert's renewal config.
# Left in place, services would reload twice (once from the config, once from the hook directory).
# Only strip the old per-cert hooks once the replacement hook actually has commands.
- name: Remove per-cert deploy hooks saved by the old scripts
  ansible.builtin.lineinfile:
    path: "{{ item.path }}"
    regexp: "^renew_hook = ({{ certbot_legacy_deploy_hooks | map('regex_escape') | join('|') }})$"
    state: absent
  loop: "{{ certbot_renewal_confs.files }}"
  loop_control:
    label: "{{ item.path | basename }}"
  when: certbot_legacy_deploy_hooks | length > 0 and certbot_deploy_commands | length > 0
  tags: certbot
```

- [ ] **Step 2: Lint**

Run: `ansible-lint roles/certbot`
Expected: no violations.

- [ ] **Step 3: Commit**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot
git commit -m "🎇 Install certbot deploy hook and strip legacy per-cert hooks

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Issuance, removal and permissions

**Files:**
- Create: `roles/certbot/tasks/issue_cert.yml`
- Create: `roles/certbot/tasks/issue.yml`

Change detection watches the cert file rather than parsing certbot's output: a cert counts as changed exactly when its `fullchain.pem` checksum differs before and after the `certbot` run. That is true whatever certbot prints, and it also covers a cert being created for the first time.

- [ ] **Step 1: Write the per-cert task file**

Create `roles/certbot/tasks/issue_cert.yml`:

```yaml
---
# Included once per entry in certbot_certs (loop variable: certbot_cert).
#
# `certbot certonly --expand` keeps a cert that is not due and already has exactly these names.
# If the requested names differ from the existing cert, certbot reissues it with exactly the
# requested set (non-interactive), so certbot_certs must list every name the cert needs.
- name: Note the certificate before issuing ({{ certbot_cert.name }})
  ansible.builtin.stat:
    path: "/etc/letsencrypt/live/{{ certbot_cert.name }}/fullchain.pem"
    follow: true
    get_checksum: true
    checksum_algorithm: sha256
  register: certbot_before
  tags: certbot

# A failing certbot run deliberately aborts the play for this host (fail fast): certs already
# issued keep certbot's default permissions until the next successful run re-applies group access.
- name: Issue or expand the certificate ({{ certbot_cert.name }})
  ansible.builtin.command:
    argv: >-
      {{ ['certbot', 'certonly', '--non-interactive', '--expand', '--cert-name', certbot_cert.name]
         + certbot_plugin_args[certbot_cert.challenge]
         + (certbot_cert.domains | map('regex_replace', '^', '--domain=') | list) }}
  environment: "{{ {'AWS_PROFILE': certbot_cert.aws_profile} if certbot_cert.challenge == 'route53' else {} }}"
  changed_when: false # change is reported by the checksum comparison below
  tags: certbot

- name: Report changed only if the certificate file changed ({{ certbot_cert.name }})
  ansible.builtin.stat:
    path: "/etc/letsencrypt/live/{{ certbot_cert.name }}/fullchain.pem"
    follow: true
    get_checksum: true
    checksum_algorithm: sha256
  register: certbot_after
  changed_when: (certbot_before.stat.checksum | default('')) != (certbot_after.stat.checksum | default(''))
  tags: certbot
```

- [ ] **Step 2: Write the issuance tasks**

Create `roles/certbot/tasks/issue.yml`:

```yaml
---
- name: Issue or expand certificates
  ansible.builtin.include_tasks: issue_cert.yml
  loop: "{{ certbot_certs }}"
  loop_control:
    loop_var: certbot_cert
    label: "{{ certbot_cert.name }}"
  tags: certbot

- name: Remove certificates that are no longer wanted
  ansible.builtin.command:
    argv: [certbot, delete, --non-interactive, --cert-name, "{{ item }}"]
    removes: "/etc/letsencrypt/renewal/{{ item }}.conf"
  loop: "{{ certbot_certs_absent }}"
  tags: certbot

- name: Let the certbot_access group read Let's Encrypt files (nginx, dovecot, exim)
  ansible.builtin.file:
    path: /etc/letsencrypt
    state: directory
    owner: root
    group: certbot_access
    mode: g+rX
    recurse: true
  tags: certbot
```

- [ ] **Step 3: Lint**

Run: `ansible-lint roles/certbot`
Expected: no violations. (If ansible-lint flags `risky-file-permissions` on the final task, the explicit `mode` already satisfies it; if it flags `no-changed-when` on a command task, the `changed_when`/`removes` keys above are what satisfy it, so recheck indentation.)

- [ ] **Step 4: Check the argv expression with sample data**

```bash
ansible localhost -c local -m ansible.builtin.debug -a "msg={{ ['certbot','certonly','--non-interactive','--expand','--cert-name','istic.net'] + ['--dns-route53'] + (['istic.net','*.istic.net'] | map('regex_replace','^','--domain=') | list) }}"
```
Expected output includes: `"--cert-name", "istic.net", "--dns-route53", "--domain=istic.net", "--domain=*.istic.net"`.

- [ ] **Step 5: Check the change detection with a scratch cert**

Outside the repo, simulate a cert file that is left alone, rewritten, and created, to confirm only the last two report `changed`:

```bash
SCRATCH=$(mktemp -d); mkdir -p "$SCRATCH/live/x" "$SCRATCH/arch"
echo one > "$SCRATCH/arch/f1" && ln -sf ../../arch/f1 "$SCRATCH/live/x/fullchain.pem"
cat > "$SCRATCH/t.yml" <<EOF
---
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Stat before
      ansible.builtin.stat: { path: "$SCRATCH/live/x/fullchain.pem", follow: true, get_checksum: true, checksum_algorithm: sha256 }
      register: certbot_before
    - name: Rewrite the cert file
      ansible.builtin.copy: { content: "two\n", dest: "$SCRATCH/arch/f1", mode: "0644" }
    - name: Stat after
      ansible.builtin.stat: { path: "$SCRATCH/live/x/fullchain.pem", follow: true, get_checksum: true, checksum_algorithm: sha256 }
      register: certbot_after
      changed_when: (certbot_before.stat.checksum | default('')) != (certbot_after.stat.checksum | default(''))
EOF
ansible-playbook "$SCRATCH/t.yml" 2>/dev/null | grep -E "^changed|^ok|PLAY RECAP|localhost "
```
Expected: `changed: [localhost]` for the rewrite and for "Stat after" (so `changed=2` in the recap).

- [ ] **Step 6: Commit**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot
git commit -m "🎇 Issue certbot certs from data, delete removed ones, fix permissions

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Per-group renewal units

**Files:**
- Create: `roles/certbot/tests/renew-group.sh`
- Create: `roles/certbot/files/certbot-renew-group.sh`
- Create: `roles/certbot/tasks/renewal.yml`

`certbot renew` accepts only ONE `--cert-name` (verified on certbot 4.0.0: with several, only the last is renewed), so each service runs a helper that calls certbot once per cert.

- [ ] **Step 1: Write the failing helper test**

Create `roles/certbot/tests/renew-group.sh` and make it executable (`chmod +x`):

```bash
#!/bin/bash
# Tests certbot-renew-group.sh with a fake certbot.
# Run from the repo root: roles/certbot/tests/renew-group.sh [path/to/certbot-renew-group.sh]
helper=${1:-roles/certbot/files/certbot-renew-group.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/certbot" <<'EOF'
#!/bin/sh
echo "$*" >>"$FAKE_CERTBOT_LOG"
while [ $# -gt 0 ]; do
	if [ "$1" = "--cert-name" ] && [ "$2" = "fail.example" ]; then
		exit 1
	fi
	shift
done
exit 0
EOF
chmod +x "$tmp/certbot"

failures=0

# run_case NAME EXPECTED_RC CERT...
run_case() {
	local name=$1 want_rc=$2 rc rc_class want_class cert expected=""
	shift 2
	: >"$tmp/log"
	CERTBOT="$tmp/certbot" FAKE_CERTBOT_LOG="$tmp/log" "$helper" "$@"
	rc=$?
	for cert in "$@"; do
		expected+="renew --quiet --no-random-sleep-on-renew --cert-name $cert"$'\n'
	done
	[ "$rc" -ne 0 ] && rc_class=nonzero || rc_class=0
	[ "$want_rc" -ne 0 ] && want_class=nonzero || want_class=0
	if [ "$(cat "$tmp/log")"$'\n' = "$expected" ] && [ "$rc_class" = "$want_class" ]; then
		echo "PASS: $name"
	else
		echo "FAIL: $name (rc=$rc, want rc $want_rc)"
		echo "expected invocations:"
		printf '%s' "$expected"
		echo "actual invocations:"
		cat "$tmp/log"
		failures=1
	fi
}

run_case "continues after a failure and exits non-zero" 1 a.example fail.example c.example
run_case "all succeed and exit zero" 0 a.example b.example

exit "$failures"
```

Run: `roles/certbot/tests/renew-group.sh`
Expected: both cases `FAIL` (the helper does not exist yet) and a non-zero exit.

- [ ] **Step 2: Write the helper**

Create `roles/certbot/files/certbot-renew-group.sh` and make it executable (`chmod +x`); the role installs it as `/usr/local/sbin/certbot-renew-group`:

```sh
#!/bin/sh
# Renew the given certificates, one `certbot renew` per cert: --cert-name only accepts a
# single value, so a multi-name command would renew just the last one.
# Keeps going after a failure so one broken cert can't stop the rest, and exits non-zero
# if any of them failed so systemd marks the unit as failed.
# Usage: certbot-renew-group CERT_NAME...
rc=0
for cert in "$@"; do
	"${CERTBOT:-/usr/bin/certbot}" renew --quiet --no-random-sleep-on-renew --cert-name "$cert" || rc=1
done
exit "$rc"
```

`--no-random-sleep-on-renew` is there because the timer already has `RandomizedDelaySec`, and a per-cert random sleep would multiply. `--no-self-upgrade` is deprecated in certbot 4 and is dropped.

- [ ] **Step 3: Run the helper test and shell linters**

Run: `roles/certbot/tests/renew-group.sh && shellcheck roles/certbot/files/certbot-renew-group.sh roles/certbot/tests/renew-group.sh`
Expected: `PASS` for both cases, and shellcheck prints nothing.

- [ ] **Step 4: Write the tasks**

Create `roles/certbot/tasks/renewal.yml`:

```yaml
---
# One renewal group per AWS profile among the route53 certs, plus one "default" group for
# cloudflare and nginx certs. Each group is its own systemd service+timer so each group
# fails on its own, and AWS_PROFILE can be set per group.
- name: Work out renewal groups
  ansible.builtin.set_fact:
    certbot_renew_profiles: >-
      {{ certbot_certs | selectattr('challenge', 'equalto', 'route53') | map(attribute='aws_profile') | unique | list }}
    certbot_default_certs: >-
      {{ certbot_certs | rejectattr('challenge', 'equalto', 'route53') | map(attribute='name') | list }}
  tags: certbot

- name: Work out which renewal units should exist
  ansible.builtin.set_fact:
    certbot_wanted_units: >-
      {{ (['certbot-renew-default.service', 'certbot-renew-default.timer'] if certbot_default_certs | length > 0 else [])
         + (certbot_renew_profiles | map('regex_replace', '^', 'certbot-renew-aws-') | map('regex_replace', '$', '.service') | list)
         + (certbot_renew_profiles | map('regex_replace', '^', 'certbot-renew-aws-') | map('regex_replace', '$', '.timer') | list) }}
  tags: certbot

# If certbot.timer does not exist (certbot not installed from apt) there is nothing to disable.
- name: Disable the packaged certbot timer (it renews with no AWS_PROFILE)
  ansible.builtin.systemd:
    name: certbot.timer
    enabled: false
    state: stopped
  register: certbot_stock_timer
  failed_when: certbot_stock_timer is failed and 'Could not find' not in (certbot_stock_timer.msg | default(''))
  tags: certbot

- name: Install the per-cert renewal helper (certbot renew takes one --cert-name)
  ansible.builtin.copy:
    src: certbot-renew-group.sh
    dest: /usr/local/sbin/certbot-renew-group
    owner: root
    group: root
    mode: "0755"
  tags: certbot

- name: Deploy the route53 renewal services (one per AWS profile)
  ansible.builtin.template:
    src: certbot-renew.service.j2
    dest: "/etc/systemd/system/certbot-renew-aws-{{ item }}.service"
    owner: root
    group: root
    mode: "0644"
  vars:
    certbot_group_name: "aws-{{ item }}"
    certbot_group_profile: "{{ item }}"
    certbot_group_certs: >-
      {{ certbot_certs | selectattr('challenge', 'equalto', 'route53') | selectattr('aws_profile', 'equalto', item)
         | map(attribute='name') | list }}
  loop: "{{ certbot_renew_profiles }}"
  notify: Reload systemd
  tags: certbot

- name: Deploy the route53 renewal timers
  ansible.builtin.template:
    src: certbot-renew.timer.j2
    dest: "/etc/systemd/system/certbot-renew-aws-{{ item }}.timer"
    owner: root
    group: root
    mode: "0644"
  vars:
    certbot_group_name: "aws-{{ item }}"
  loop: "{{ certbot_renew_profiles }}"
  notify: Reload systemd
  tags: certbot

- name: Deploy the default renewal service (cloudflare and nginx certs)
  ansible.builtin.template:
    src: certbot-renew.service.j2
    dest: /etc/systemd/system/certbot-renew-default.service
    owner: root
    group: root
    mode: "0644"
  vars:
    certbot_group_name: default
    certbot_group_profile: ""
    certbot_group_certs: "{{ certbot_default_certs }}"
  when: certbot_default_certs | length > 0
  notify: Reload systemd
  tags: certbot

- name: Deploy the default renewal timer
  ansible.builtin.template:
    src: certbot-renew.timer.j2
    dest: /etc/systemd/system/certbot-renew-default.timer
    owner: root
    group: root
    mode: "0644"
  vars:
    certbot_group_name: default
  when: certbot_default_certs | length > 0
  notify: Reload systemd
  tags: certbot

- name: Pick up new unit files before enabling timers
  ansible.builtin.meta: flush_handlers
  tags: certbot

- name: Enable and start the renewal timers
  ansible.builtin.systemd:
    name: "{{ item }}"
    enabled: true
    state: started
  loop: "{{ certbot_wanted_units | select('search', 'timer$') | list }}"
  tags: certbot

# Removing a group (e.g. an AWS profile no longer used) must delete its units explicitly;
# dropping the entry from certbot_certs does not remove anything from the host.
- name: Find existing renewal units
  ansible.builtin.find:
    paths: /etc/systemd/system
    patterns:
      - certbot-renew-*.service
      - certbot-renew-*.timer
  register: certbot_existing_units
  tags: certbot

- name: Stop and disable stale renewal timers
  ansible.builtin.systemd:
    name: "{{ item }}"
    enabled: false
    state: stopped
  loop: >-
    {{ certbot_existing_units.files | map(attribute='path') | map('basename')
       | difference(certbot_wanted_units) | select('search', 'timer$') | list }}
  tags: certbot

- name: Remove stale renewal units
  ansible.builtin.file:
    path: "/etc/systemd/system/{{ item }}"
    state: absent
  loop: "{{ certbot_existing_units.files | map(attribute='path') | map('basename') | difference(certbot_wanted_units) | list }}"
  notify: Reload systemd
  tags: certbot
```

- [ ] **Step 5: Lint**

Run: `ansible-lint roles/certbot`
Expected: no violations.

- [ ] **Step 6: Check the group/unit-name expressions with sample data**

```bash
ansible localhost -c local -m ansible.builtin.debug -a "msg={{ ['aqcom','istic'] | map('regex_replace','^','certbot-renew-aws-') | map('regex_replace','\$','.timer') | list }}"
```
Expected: `["certbot-renew-aws-aqcom.timer", "certbot-renew-aws-istic.timer"]`.

The expressions avoid regex backreferences and backslashes on purpose: `'^'` adds a prefix and `'$'` adds a suffix, and `select('search', 'timer$')` picks the timer units out of a list of unit names.

- [ ] **Step 7: Commit**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot
git commit -m "🎇 Add per-AWS-profile certbot renewal units

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Wire the role together

**Files:**
- Create: `roles/certbot/tasks/main.yml`

- [ ] **Step 1: Write main.yml**

Create `roles/certbot/tasks/main.yml`:

```yaml
---
# Order matters: validate first; install the deploy hook BEFORE issuing so an issuance that
# renews or expands an existing cert reloads services (certbot does not run the hook for a
# first-time issuance); issue; then set up renewal.
- name: Validate certbot data
  ansible.builtin.import_tasks: validate.yml

- name: Install deploy hook
  ansible.builtin.import_tasks: hooks.yml

- name: Issue certificates
  ansible.builtin.import_tasks: issue.yml

- name: Configure renewal
  ansible.builtin.import_tasks: renewal.yml
```

- [ ] **Step 2: Lint the whole role and re-run the render test**

```bash
ansible-lint roles/certbot
CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml 2>&1 | tail -4
```
Expected: ansible-lint clean; the render test still ends `failed=0`.

- [ ] **Step 3: Commit**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot
git commit -m "🎇 Wire certbot role tasks together

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Per-host cert data

**Files:**
- Create: `host_vars/firth.water.gkhs.net/certbot.yml`
- Create: `host_vars/atoll.water.gkhs.net/certbot.yml`

The data below is the exact set of names the merged #341 scripts request. The only translation is `aws_profile: istic-r53` → `istic`. Do not "tidy" the domain lists: a different set makes certbot reissue the cert with that set.

- [ ] **Step 1: Write firth's data**

Create `host_vars/firth.water.gkhs.net/certbot.yml`:

```yaml
---
# Certificates on firth. See docs/superpowers/specs/2026-10-11-ansible-certbot-design.md.
# Domain lists must be complete: certbot reissues a cert with exactly the names listed here.
# ssl_snippet is the file stem of /etc/nginx/snippets/ssl/<stem>_ssl.conf that vhosts include.
# It keeps each snippet's existing filename; it is used from Task 12 onwards.
certbot_deploy_commands:
  - service nginx reload
  - service dovecot restart

# Dead certs found live on firth during Task 9 Step 3 (certbot certificates) that are not in
# certbot_certs below. certbot delete removes them instead of leaving them unmanaged.
certbot_certs_absent:
  - archipelago.water.gkhs.net # pre-firth legacy server, long out of service
  - foip.me # domain decommissioned (#246, #252); no DNS zone left

certbot_certs:
  # --- nginx (http-01; no wildcards) ---
  - name: firth.water.gkhs.net
    challenge: nginx
    domains:
      - firth.water.gkhs.net
      - istic.net
      - factionfiction.net
      - www.factionfiction.net
      - themonthlymoon.com
      - ludo.istic.co
      - imperial.istic.net
      - altru.istic.net
      - log.istic.net
      - hol.istic.net
      - live.art.istic.net
      - material.istic.net
      - istic.co
      - warehousebasement.com
      - www.warehousebasement.com
      - dagon.church
      - live.dagon.church
      - wiki.dagon.church
      - mechan.istic.net
      - optim.istic.net
      - www.larpfic.com
      - larpfic.com
      - www.lrpfic.com
      - lrpfic.com
      - www.deathuntodarkness.org
      - deadbadgerdesigns.co.uk
      - www.deadbadgerdesigns.co.uk
      - live.dailyphoto.aquarionics.com
  - name: forums.profounddecisions.co.uk
    ssl_snippet: pddiscourse
    challenge: nginx
    domains: [forums.profounddecisions.co.uk]
  - name: michael.conterio.co.uk
    ssl_snippet: conterio
    challenge: nginx
    domains: [michael.conterio.co.uk, www.michael.conterio.co.uk, conterio.co.uk, www.conterio.co.uk]

  # --- cloudflare ---
  - { name: socksandpuppets.com, ssl_snippet: socksandpuppets, challenge: cloudflare, domains: [socksandpuppets.com, "*.socksandpuppets.com"] }
  - { name: aquarionics.com, ssl_snippet: aquarionics, challenge: cloudflare, domains: [aquarionics.com, "*.aquarionics.com"] }
  - { name: novelathon.com, ssl_snippet: novelathon.com, challenge: cloudflare, domains: [novelathon.com, "*.novelathon.com"] }
  - { name: istic.dev, ssl_snippet: istic_dev, challenge: cloudflare, domains: [istic.dev, "*.istic.dev"] }

  # --- route53, istic account ---
  - name: istic.net
    ssl_snippet: istic
    challenge: route53
    aws_profile: istic
    domains:
      - istic.net
      - "*.istic.net"
      - istic.network
      - "*.istic.network"
      - "*.blogs.istic.network"
      - istic.systems
      - "*.istic.systems"
  - { name: svc.istic.systems, ssl_snippet: svc_istic_systems, challenge: route53, aws_profile: istic, domains: [svc.istic.systems, "*.svc.istic.systems"] }
  - { name: carcosadreams.com, ssl_snippet: carcosadreams, challenge: route53, aws_profile: istic, domains: [carcosadreams.com, "*.carcosadreams.com", "*.carcosadreams.co.uk"] }
  - { name: ludoistic.com, ssl_snippet: ludoistic, challenge: route53, aws_profile: istic, domains: [ludoistic.com, "*.ludoistic.com"] }
  - { name: nanocountdown.com, ssl_snippet: nanocountdown.com, challenge: route53, aws_profile: istic, domains: [nanocountdown.com, "*.nanocountdown.com"] }
  - { name: bloomfeed.app, ssl_snippet: bloomfeedapp, challenge: route53, aws_profile: istic, domains: [bloomfeed.app, "*.bloomfeed.app"] }

  # --- route53, aqcom account ---
  - name: nicholasavenell.com
    ssl_snippet: nicholasavenell
    challenge: route53
    aws_profile: aqcom
    domains: [nicholasavenell.com, "*.nicholasavenell.com", "*.nicholasavenell.net", nicholasavenell.net]
  - { name: bromioscreations.com, ssl_snippet: bromioscreations, challenge: route53, aws_profile: aqcom, domains: [bromioscreations.com, "*.bromioscreations.com"] }
  - { name: larp.me, ssl_snippet: larpme, challenge: route53, aws_profile: aqcom, domains: [larp.me, "*.larp.me", larp.me.uk, "*.larp.me.uk"] }
  - { name: camlarp.co.uk, ssl_snippet: camlarp, challenge: route53, aws_profile: aqcom, domains: [camlarp.co.uk, "*.camlarp.co.uk"] }
  # DNS-01 on purpose (not nginx): the live cert includes *.hubris.house
  - { name: hubris.house, ssl_snippet: hubris, challenge: route53, aws_profile: aqcom, domains: [hubris.house, "*.hubris.house"] }
  - { name: kastark.co.uk, ssl_snippet: kastark, challenge: route53, aws_profile: aqcom, domains: [kastark.co.uk, www.kastark.co.uk, dhmstark.co.uk, www.dhmstark.co.uk] }
```

- [ ] **Step 2: Write atoll's data**

Create `host_vars/atoll.water.gkhs.net/certbot.yml`:

```yaml
---
# Certificates on atoll. See docs/superpowers/specs/2026-10-11-ansible-certbot-design.md.
# ssl_snippet: see host_vars/firth.water.gkhs.net/certbot.yml.
certbot_deploy_commands:
  - service nginx reload
  - service dovecot restart

# The archive site's public domain is an Ansible variable; the cert is only requested if it is set.
certbot_certs_archive: >-
  {{ [{'name': stream_delta_archive_public_domain, 'challenge': 'nginx', 'domains': [stream_delta_archive_public_domain]}]
     if (stream_delta_archive_public_domain | default('')) | length > 0 else [] }}

certbot_certs_static:
  - { name: voyeur.istic.net, ssl_snippet: delta, challenge: route53, aws_profile: istic, domains: [voyeur.istic.net, "*.voyeur.istic.net", "*.ws.voyeur.istic.net"] }
  - { name: voyeur.istic.dev, ssl_snippet: delta_staging, challenge: cloudflare, domains: [voyeur.istic.dev, "*.voyeur.istic.dev", "*.ws.voyeur.istic.dev"] }
  # Legacy cert dovecot's ssl_cert points at directly (not via an nginx snippet). Its own name
  # doesn't match its SANs; it originally also covered the "voyuer" typo domain (dropped — not a
  # live service name). Keep issuing it so dovecot's mail TLS doesn't go stale.
  - { name: atoll.water.gkhs.net, challenge: route53, aws_profile: istic, domains: [atoll.istic.systems] }

certbot_certs: "{{ certbot_certs_static + certbot_certs_archive }}"
```

> **Found during Task 9 Step 3 on the real host, not during planning:** atoll's dovecot (`ssl_cert` in `doveconf -n`) points directly at `/etc/letsencrypt/live/atoll.water.gkhs.net/`, a cert whose live SANs (`atoll.istic.systems`, plus a typo'd `voyuer.istic.net`/`ws.voyuer.istic.net` that the owner confirmed is dead) don't match its own name. It is NOT the dead `atoll_ssl.conf` nginx snippet from Task 12 — those are unrelated; dovecot doesn't use nginx snippets at all. The cert above was added once this was confirmed live via `ssh atoll 'sudo certbot certificates'` and its renewal conf (`authenticator = dns-route53`, no persisted `aws_profile`, so `istic` per the zone owner). This also means the deploy commands needed `service dovecot restart`, so the "decision for the owner" bullet about atoll's nginx-only reload (further down this task, and in Task 13's PR body) is resolved, not deferred.

- [ ] **Step 3: Check both files parse and the data resolves**

```bash
for h in firth.water.gkhs.net atoll.water.gkhs.net; do
  ansible "$h" -c local -m ansible.builtin.debug -a 'msg={{ certbot_certs | map(attribute="name") | list }}' 2>&1 | head -30
done
```
Expected: firth lists 19 names (starting `firth.water.gkhs.net` and ending `kastark.co.uk`); atoll lists `voyeur.istic.net`, `voyeur.istic.dev`, and `stream.aquarionics.com`.

- [ ] **Step 4: Commit**

Run `git branch --show-current` (expect `feature/ansible-certbot`), then:

```bash
git add host_vars/firth.water.gkhs.net/certbot.yml host_vars/atoll.water.gkhs.net/certbot.yml
git commit -m "🎇 Add certbot cert data for firth and atoll

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Playbook wiring

**Files:**
- Modify: `playbook.yml` (the "Actions on all external hosts" play, the "Hello Atoll" play, and a new play after "Actions on all hosts running NGINX")

- [ ] **Step 1: Move `aws_profiles` into the all-external-hosts play**

In the "Actions on all external hosts" play, add `- aws_profiles` right after `- water_gkhs_users`:

```yaml
  roles:
    - water_gkhs_users
    - aws_profiles
    - water_gkhs_tailscale
```

- [ ] **Step 2: Remove it from the Atoll play**

In the "Hello Atoll" play, delete the `    - aws_profiles` line (between `water_gkhs_exim` and `geerlingguy.nodejs`), so it reads:

```yaml
    - water_gkhs_exim
    - geerlingguy.nodejs
```

- [ ] **Step 3: Add the certbot play**

Insert this play immediately after the "Actions on all hosts running NGINX" play and before "Hello Firth":

```yaml
- name: Certbot certificates on all external hosts
  hosts: external_hosts
  handlers:
    - name: Import global handlers
      ansible.builtin.import_tasks: roles/global_things/handlers/main.yml
  become: true
  roles:
    - { role: certbot, tags: certbot }
```

It runs after `water_gkhs_nginx` (nginx must be installed for the nginx plugin) and before `firth_nginx` / `atoll_nginx` (which reference the certs).

- [ ] **Step 4: Verify the play order**

Run: `grep -n "^- name:" playbook.yml`
Expected order: AWS Roles, Actions on all hosts, Actions on all external hosts, Actions on all non-local hosts, Actions on all hosts running NGINX, Certbot certificates on all external hosts, Hello Firth, Hello Atoll.

- [ ] **Step 5: Syntax-check and lint**

```bash
ansible-playbook playbook.yml --syntax-check
ansible-lint playbook.yml
```
Expected: `playbook: playbook.yml` for the syntax check, and no lint violations.

- [ ] **Step 6: Commit**

Run `git branch --show-current` (expect `feature/ansible-certbot`), then:

```bash
git add playbook.yml
git commit -m "🔄️ Run aws_profiles on all external hosts and add the certbot play

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Rollout and verification (manual, on the hosts)

**Files:** none. Do this on one host at a time, firth first. Nothing here should be skipped: the first run can reissue certs.

> **WARNING: always pass `--limit firth.water.gkhs.net` or `--limit atoll.water.gkhs.net` with `--tags certbot`.** Ten pre-existing tasks in `roles/water_gkhs_common` are also tagged `certbot`; without `--limit` they would run on the localhost/workstation too (apt-installing certbot and writing `/root/.secrets/cloudflare.ini` there).

- [ ] **Step 1: Apply the AWS profiles (root's `~/.aws`)**

> **WARNING:** the `aws_profiles` role will OVERWRITE root's hand-made `[aqcom]` keys on firth with the vault values (watch for `changed` on the `aqcom` tasks and make sure the vault values are the ones you want). Do NOT use `--diff` with `--tags aws_profiles`: those tasks have no `no_log` and would print key values. Also, `backup: true` leaves timestamped copies of root's credentials files in `/root/.aws`; delete them once you are satisfied.

Use `--tags aws_profiles` (not the broader `--tags aws`), which runs only this role's credential tasks. The `aws` tag also covers `firth_dns`'s live Route53/Cloudflare DNS sync, `water_gkhs_common`'s apt/python-library tasks, and `stream_delta` on atoll, which you don't want running as a side effect here.

```bash
ansible-playbook playbook.yml --tags aws_profiles --limit firth.water.gkhs.net 2>&1 | tee /tmp/aws-firth.log
```
Expected: the `AWS Creds`/`AWS Config` tasks run against firth (`changed` or `ok`), none fail. Per the project rules, redirect the full output to a file as above; do not pipe it through `tail`/`head`.

Then on firth confirm root has the profile (section names only, no keys):
```bash
sudo grep -c -x -F '[istic]' /root/.aws/credentials
```
Expected: `1`.

- [ ] **Step 2: Prove renewal works with the new profile name, before changing any cert data**

On firth:
```bash
sudo env AWS_PROFILE=istic certbot renew --dry-run --cert-name nanocountdown.com
```
Expected: `Congratulations, all simulated renewals succeeded`. If it fails, stop: the `istic` key lacks the Route53 permissions certbot needs, and the rest of this plan depends on it.

- [ ] **Step 3: Compare the Ansible data with what certbot has today (must be identical)**

```bash
HOST=firth.water.gkhs.net
ansible "$HOST" -c local -m ansible.builtin.debug -a 'msg={{ certbot_certs | to_json }}' \
  | sed '1s/^[^{]*=> //' | jq -r '.msg | fromjson | .[] | .name + ": " + (.domains | sort | join(" "))' | sort > /tmp/expected.txt
ssh "$HOST" 'sudo certbot certificates 2>/dev/null' \
  | python3 -c '
import re, sys
name = None
for line in sys.stdin:
    m = re.match(r"\s*Certificate Name: (\S+)", line)
    if m: name = m.group(1)
    m = re.match(r"\s*Domains: (.*)", line)
    if m and name: print(name + ": " + " ".join(sorted(m.group(1).split())))
' | sort > /tmp/actual.txt
diff /tmp/expected.txt /tmp/actual.txt && echo IDENTICAL
```
Expected: `IDENTICAL`. Any difference means a cert would be reissued with a different name set. Fix `certbot.yml` (not the host) until it matches.

Before deciding about any cert that appears only on the host, find out which cert dovecot and exim use. They use the cert named `{{ letsencrypt_dir }}`/`{{ cert_id }}`, which both default to `{{ ansible_fqdn }}` (`group_vars/all/00-core.yml:1`) — but that is a *fact gathered from the host*, not something you can get with `-c local` (that evaluates on the controller and gives the controller's own hostname, not the target's; it only works for host_vars like `certbot_certs` above, which is static data, not a live fact). On BOTH hosts run:
```bash
ssh "$HOST" 'hostname -f'
ssh "$HOST" 'sudo doveconf -n | grep ssl_cert'
ssh "$HOST" 'sudo grep -i tls_certkey /etc/exim4/conf.d/main/00_water_gkhs_custom'
```
and compare the fqdn and the cert names in the `ssl_cert`/`tls_certkey` paths with the names in the data. If the fqdn-named cert exists on a host but is not in `certbot_certs`, it is still in use by dovecot/exim: it must go into `certbot_certs`, NOT `certbot_certs_absent`.

A cert that appears only in `/tmp/actual.txt` is on the host but not in the data. The role's validation guard will refuse to run until each such cert is either added to `certbot_certs` (if it is still used) or listed in `certbot_certs_absent` (if it should be deleted). Decide each one deliberately: with the packaged timer disabled, a cert in neither list would stop renewing. (Do not add a cert just because a snippet file mentions it, and do not assume a cert is a dead name just because it looks odd. This is exactly how `atoll.water.gkhs.net` was found during rollout: dovecot's `ssl_cert` pointed straight at it, even though its own SANs didn't contain its name and it isn't the `atoll_nginx`/`atoll_ssl.conf` nginx snippet — those are unrelated, since dovecot doesn't use nginx snippets at all. It's now in `host_vars/atoll.water.gkhs.net/certbot.yml`.) Repeat with `HOST=atoll.water.gkhs.net` before touching atoll.

- [ ] **Step 4: Confirm how the old hooks were saved**

On the host: `sudo grep -rn 'hook' /etc/letsencrypt/renewal/ | head`
Expected: lines like `renew_hook = service nginx reload; service dovecot restart` in some `.conf` files. If the key is not `renew_hook` (for example `deploy_hook`), change the `regexp` in `roles/certbot/tasks/hooks.yml` to match before the next step.

- [ ] **Step 5: Run the certbot role**

```bash
ansible-playbook playbook.yml --tags certbot --limit firth.water.gkhs.net 2>&1 | tee /tmp/certbot-firth.log
```
Expected: validation passes; the issuance loop reports `ok` for every cert (no `changed`, since nothing is due); the helper-install task and the unit-file tasks report `changed` on the first run; no failures. Then read `/tmp/certbot-firth.log` in full and confirm no cert shows `changed`.

Resolved during Step 3 above (not a deferred decision): atoll's deploy commands now include `service dovecot restart`, because dovecot there turned out to depend directly on a renewed cert (`atoll.water.gkhs.net`).

- [ ] **Step 6: Verify the timers, that EVERY cert in each group is checked, and real renewal paths**

A unit that merely succeeds proves little: confirm each cert was actually considered. On firth, for each group (`aws-istic`, `aws-aqcom`, `default`; use the real group names from `systemctl list-timers`):
```bash
systemctl list-timers 'certbot*' --all
sudo systemctl start certbot-renew-<group>.service
systemctl is-failed certbot-renew-<group>.service   # expect: inactive (not "failed")
sudo grep -E 'not yet due for renewal|Certificate not yet due|Congratulations|Renewing an existing certificate|No renewals were attempted|renew' /var/log/letsencrypt/letsencrypt.log | tail -n 60
```
(`journalctl -u certbot-renew-<group>.service` shows little because the helper runs certbot with `--quiet`; use `/var/log/letsencrypt/letsencrypt.log`.) For EVERY cert name listed in `certbot_certs` for that group, confirm the log's latest run mentions the cert (its `/etc/letsencrypt/renewal/<name>.conf` line) as not due for renewal (skipped) or renewed. A group whose unit succeeded but where one cert never appears means that cert was not checked.

Expected: `certbot.timer` is no longer listed; the three `certbot-renew-*` timers are; each service run is not `failed`, every cert in the group appears in the log as skipped or renewed, and there is no `Unable to find a Route53 hosted zone` error.

Then prove the real ACME path (a staging challenge through the same credential path as the unit):
```bash
# at least one cert per route53 group, with the group's profile
sudo env AWS_PROFILE=istic certbot renew --dry-run --cert-name nanocountdown.com
sudo env AWS_PROFILE=aqcom certbot renew --dry-run --cert-name <one aqcom cert from certbot_certs>
# one nginx cert and one cloudflare cert on each host
sudo certbot renew --dry-run --cert-name <one nginx-challenge cert>
sudo certbot renew --dry-run --cert-name <one cloudflare-challenge cert>
```
Expected for each: `Congratulations, all simulated renewals succeeded` naming that cert, and no `No certificate found with name` error.

- [ ] **Step 7: Repeat Steps 1–6 for atoll**

Use `--limit atoll.water.gkhs.net` and `HOST=atoll.water.gkhs.net`. Expected: the archive cert (`stream.aquarionics.com`) appears in the comparison and in the default group.

---

### Task 10: Remove the scripts and update the docs

**Files:**
- Delete: `bin/generate-firth-certbot.sh`, `bin/generate-atoll-certbot.sh`, `bin/update-all-certbots.sh`
- Modify: `docs/adding-sftp-hosted-site.md`

Do this only after Task 9 has passed on both hosts.

- [ ] **Step 1: Delete the scripts**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git rm bin/generate-firth-certbot.sh bin/generate-atoll-certbot.sh bin/update-all-certbots.sh
```

- [ ] **Step 2: Update the cert instructions in the SFTP doc**

In `docs/adding-sftp-hosted-site.md`, replace the block that starts `Then add the cert to \`bin/generate-firth-certbot.sh\`.` (the paragraph, the Route53 bash example, the "For Cloudflare-managed domains:" paragraph and its bash example) with:

````markdown
Then add the cert to `certbot_certs` in `host_vars/firth.water.gkhs.net/certbot.yml`. For Route53-managed domains:

```yaml
- { name: example.com, challenge: route53, aws_profile: aqcom, domains: [example.com, "*.example.com"] }
```

For Cloudflare-managed domains:

```yaml
- { name: example.com, challenge: cloudflare, domains: [example.com, "*.example.com"] }
```

For a plain nginx-validated cert (no wildcards): `challenge: nginx`.

List every name the cert needs: if the list differs from the existing cert, certbot reissues it with exactly that set. `aws_profile` is `aqcom` or `istic`.
````

- [ ] **Step 3: Update the "Run the playbook" block**

In the same file, in section "5. Run the playbook", replace the lines
```bash
# Generate the certificate (run on firth)
./bin/generate-firth-certbot.sh
```
with
```bash
# Generate the certificate
ansible-playbook playbook.yml --tags certbot --limit firth.water.gkhs.net
```

- [ ] **Step 4: Confirm nothing else references the scripts**

Run: `grep -rn "generate-.*-certbot\|update-all-certbots" --include=*.md --include=*.yml --include=*.sh --include=*.j2 . | grep -v '^./.git/\|^./docs/superpowers\|galaxy-roles\|\.direnv'`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add docs/adding-sftp-hosted-site.md
git commit -m "❌ Remove certbot shell scripts; document certbot_certs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Remove the legacy `istic-r53` profile

**Files:**
- Modify: `roles/aws_profiles/tasks/main.yml` (append)

Do this only after the new renewal units have run successfully on both hosts (Task 9 Steps 6–7). Removing config from the role does not remove anything from the hosts, so these are explicit removal tasks. `default` is deliberately left alone.

- [ ] **Step 1: Append the removal tasks**

Add to the end of `roles/aws_profiles/tasks/main.yml`:

```yaml

- name: AWS Creds - remove legacy istic-r53 profile
  community.general.ini_file:
    path: ~/.aws/credentials
    section: istic-r53
    state: absent
    mode: "0600"
    backup: true
  tags:
    - aws

- name: AWS Config - remove legacy istic-r53 profile
  community.general.ini_file:
    path: ~/.aws/config
    section: profile istic-r53
    state: absent
    mode: "0600"
    backup: true
  tags:
    - aws
```

- [ ] **Step 2: Lint**

Run: `ansible-lint roles/aws_profiles`
Expected: no violations.

- [ ] **Step 3: Apply and verify**

```bash
ansible-playbook playbook.yml --tags aws_profiles --limit 'firth.water.gkhs.net,atoll.water.gkhs.net' 2>&1 | tee /tmp/aws-cleanup.log
```
Then on each host: `sudo grep -c -x -F '[istic-r53]' /root/.aws/credentials`
Expected: `0` (grep prints `0` and exits 1; that is the pass). Also run `sudo certbot renew --dry-run --cert-name nanocountdown.com` with `AWS_PROFILE=istic` once more to confirm renewals still work.

- [ ] **Step 4: Commit**

Run `git branch --show-current` (expect `feature/ansible-certbot`), then:

```bash
git add roles/aws_profiles/tasks/main.yml
git commit -m "🔄️ Remove the legacy istic-r53 AWS profile from managed hosts

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Generate the nginx SSL snippets from `certbot_certs`

> **WARNING:** as in Task 9, always pass `--limit firth.water.gkhs.net` or `--limit atoll.water.gkhs.net` with `--tags certbot`, because ten pre-existing `certbot`-tagged tasks in `roles/water_gkhs_common` would otherwise also run on the localhost/workstation.

**Files:**
- Create: `roles/certbot/templates/nginx-ssl-snippet.conf.j2`
- Create: `roles/certbot/handlers/main.yml`
- Create: `roles/certbot/tasks/nginx_snippets.yml`
- Modify: `roles/certbot/tasks/main.yml`, `roles/certbot/defaults/main.yml` (already has `certbot_ssl_snippets_absent`), `roles/certbot/tests/render.yml`
- Modify: `host_vars/atoll.water.gkhs.net/certbot.yml`
- Modify: `roles/firth_nginx/tasks/main.yml`, `roles/atoll_nginx/tasks/main.yml`
- Delete: 13 static snippets and `ssl.nginx.conf.j2` in `roles/firth_nginx/templates/`, and `roles/atoll_nginx/templates/ssl/`
- Modify: `docs/adding-sftp-hosted-site.md`

Do this only after Task 9 has passed on both hosts. Every `ssl_*` snippet in the repo (all 17, normalised for whitespace and cert name) is the same four directives, so the generated files are equivalent to what is deployed today. The existing file stems are kept (vhosts include them by name), via the `ssl_snippet` field added to the data in Task 7. `letsencrypt_ssl.conf` stays static: it points at `{{ letsencrypt_dir }}`, which exim and dovecot also use. `atoll_ssl.conf` is dead (no vhost includes it, and the host it names does not exist), so it is deleted from the host explicitly.

- [ ] **Step 1: Extend the render test (it will fail until the template exists)**

In `roles/certbot/tests/render.yml`, make three edits.

(a) After the `Render a group timer` task (the one ending with `certbot_group_name: aws-istic`), add:

```yaml
    - name: Render an nginx SSL snippet
      ansible.builtin.template:
        src: "{{ certbot_templates }}/nginx-ssl-snippet.conf.j2"
        dest: "{{ certbot_test_dir }}/nginx-snippet.conf"
        mode: "0644"
      vars:
        certbot_cert:
          name: istic.net
```

(b) Add the new file to the read loop. Change
```yaml
      loop: [reload-services.sh, aws-istic.service, default.service, aws-istic.timer]
```
to
```yaml
      loop: [reload-services.sh, aws-istic.service, default.service, aws-istic.timer, nginx-snippet.conf]
```

(c) Append these assertions to the `that:` list of `Check the rendered output`:

```yaml
          - "'ssl_certificate /etc/letsencrypt/live/istic.net/fullchain.pem;\n' in (certbot_rendered.results[4].content | b64decode)"
          - "'ssl_certificate_key /etc/letsencrypt/live/istic.net/privkey.pem;\n' in (certbot_rendered.results[4].content | b64decode)"
          - "'ssl_session_timeout 10m;\n' in (certbot_rendered.results[4].content | b64decode)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml 2>&1 | tail -8`
Expected: FAIL on "Render an nginx SSL snippet" (the template does not exist yet).

- [ ] **Step 3: Write the snippet template**

Create `roles/certbot/templates/nginx-ssl-snippet.conf.j2`:

```jinja
# {{ ansible_managed }}
ssl_certificate /etc/letsencrypt/live/{{ certbot_cert.name }}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/{{ certbot_cert.name }}/privkey.pem;
ssl_session_cache shared:SSL:1m;
ssl_session_timeout 10m;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml 2>&1 | tail -4`
Expected: `failed=0` (now `ok=8 changed=5`).

- [ ] **Step 5: Write the handler**

Create `roles/certbot/handlers/main.yml`. A handler can notify another handler, so the config is validated first and only then reloaded (the `Reload Nginx` handler comes from `roles/global_things/handlers/main.yml`, which the certbot play imports):

```yaml
---
- name: Validate nginx for certbot snippets
  ansible.builtin.command: nginx -t
  changed_when: false
  notify: Reload Nginx
```

- [ ] **Step 6: Write the snippet tasks**

Create `roles/certbot/tasks/nginx_snippets.yml`:

```yaml
---
- name: Ensure the nginx SSL snippet directory exists
  ansible.builtin.file:
    path: /etc/nginx/snippets/ssl
    state: directory
    owner: root
    group: root
    mode: "0755"
  tags: certbot

- name: Generate nginx SSL snippets from certbot_certs
  ansible.builtin.template:
    src: nginx-ssl-snippet.conf.j2
    dest: "/etc/nginx/snippets/ssl/{{ certbot_cert.ssl_snippet }}_ssl.conf"
    owner: root
    group: root
    mode: "0644"
  loop: "{{ certbot_certs | selectattr('ssl_snippet', 'defined') | list }}"
  loop_control:
    loop_var: certbot_cert
    label: "{{ certbot_cert.ssl_snippet }}_ssl.conf"
  notify: Validate nginx for certbot snippets
  tags: certbot

# Dropping an entry from certbot_certs does not delete its snippet from the host; list it here.
- name: Remove nginx SSL snippets that no longer exist
  ansible.builtin.file:
    path: "/etc/nginx/snippets/ssl/{{ item }}_ssl.conf"
    state: absent
  loop: "{{ certbot_ssl_snippets_absent }}"
  notify: Validate nginx for certbot snippets
  tags: certbot
```

- [ ] **Step 7: Wire it into the role**

Append to `roles/certbot/tasks/main.yml`:

```yaml

- name: Generate nginx SSL snippets
  ansible.builtin.import_tasks: nginx_snippets.yml
```

- [ ] **Step 8: Delete the dead atoll snippet**

Add to `host_vars/atoll.water.gkhs.net/certbot.yml`:

```yaml

# No vhost includes atoll_ssl.conf and the host it names does not exist.
certbot_ssl_snippets_absent:
  - atoll
```

- [ ] **Step 9: Lint**

Run: `ansible-lint roles/certbot && ansible-playbook playbook.yml --syntax-check`
Expected: no violations; the syntax check prints `playbook: playbook.yml`.

- [ ] **Step 10: Commit the new generation (the old definitions are still in place)**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add roles/certbot host_vars/atoll.water.gkhs.net/certbot.yml
git commit -m "🎇 Generate nginx SSL snippets from certbot_certs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 11: Snapshot the snippets on each host (manual, before)**

On each host, record each snippet's directives, normalised for whitespace:

```bash
sudo sh -c 'cd /etc/nginx/snippets/ssl && for f in *_ssl.conf; do echo "== $f"; grep -E "^[[:space:]]*ssl_" "$f" | sed -E "s/^[[:space:]]+//" | tr -s " " | sort; done' > /tmp/ssl-before.txt
wc -l /tmp/ssl-before.txt
```
Expected: a non-empty file with one `== <name>_ssl.conf` section per snippet.

- [ ] **Step 12: Run the role and diff (manual)**

```bash
ansible-playbook playbook.yml --tags certbot --limit firth.water.gkhs.net 2>&1 | tee /tmp/snippets-firth.log
```
Then on firth, repeat the Step 11 command writing to `/tmp/ssl-after.txt`, and `sudo nginx -t`, then:

```bash
diff /tmp/ssl-before.txt /tmp/ssl-after.txt && echo IDENTICAL
```
Expected: `nginx: configuration file ... test is successful` and `IDENTICAL` on firth. On atoll the only difference should be the whole `== atoll_ssl.conf` section removed. Anything else means a snippet changed value: stop and compare that cert's `ssl_snippet` against the vhosts that include it.

- [ ] **Step 13: Remove the old definitions**

In `roles/firth_nginx/tasks/main.yml`, delete this whole task (the five-entry loop that generated snippets):

```yaml
- name: Configure SSL Config
  ansible.builtin.template:
    src: ssl.nginx.conf.j2
    dest: /etc/nginx/snippets/ssl/{{ item.file_name }}_ssl.conf
    mode: "0644"
  vars:
    cert_name: "{{ item.cert_name }}"
  loop:
    - { cert_name: "camlarp.co.uk", file_name: "camlarp" }
    - { cert_name: "nanocountdown.com", file_name: "nanocountdown.com" }
    - { cert_name: "novelathon.com", file_name: "novelathon.com" }
    - { cert_name: "kastark.co.uk", file_name: "kastark" }
    - { cert_name: "svc.istic.systems", file_name: "svc_istic_systems" }
  notify:
    - Validate nginx configuration
    - Restart nginx
  tags:
    - nginx
    - nginx_ssl
```

In `roles/atoll_nginx/tasks/main.yml`, delete both snippet tasks (`Delete old ssl config snippits` and `Configure ssl config snippits`), since `templates/ssl/` will be empty.

Leave firth's `Delete old ssl config snippits` and `Configure ssl config snippits` tasks: they still deploy the static `letsencrypt_ssl.conf`.

Then delete the static files:

```bash
git branch --show-current   # expect: feature/ansible-certbot
git rm roles/firth_nginx/templates/ssl.nginx.conf.j2 \
  roles/firth_nginx/templates/ssl/{aquarionics,bloomfeedapp,bromioscreations,carcosadreams,conterio,hubris,istic_dev,istic,larpme,ludoistic,nicholasavenell,pddiscourse,socksandpuppets}_ssl.conf \
  roles/atoll_nginx/templates/ssl/{atoll,delta,delta_staging}_ssl.conf
ls roles/firth_nginx/templates/ssl
```
Expected `ls` output: only `letsencrypt_ssl.conf`.

- [ ] **Step 14: Run the nginx roles and confirm nothing changed (manual)**

```bash
ansible-playbook playbook.yml --tags nginx --limit 'firth.water.gkhs.net,atoll.water.gkhs.net' 2>&1 | tee /tmp/nginx-after.log
```
Then on each host rerun the Step 11 command into `/tmp/ssl-after2.txt` and `diff /tmp/ssl-after.txt /tmp/ssl-after2.txt && echo IDENTICAL`, and `sudo nginx -t`.
Expected: `IDENTICAL` and a successful `nginx -t`. (On atoll `ssl-after.txt` is the post-Step-12 snapshot.)

- [ ] **Step 15: Update the SFTP doc**

In `docs/adding-sftp-hosted-site.md`, replace everything from the line `Add an entry to the \`Configure SSL Config\` loop in \`roles/firth_nginx/tasks/main.yml\`:` down to (but not including) the `---` line before `## 4. Add the nginx vhost` with:

````markdown
Add the cert to `certbot_certs` in `host_vars/firth.water.gkhs.net/certbot.yml`. Giving it an `ssl_snippet` also generates `/etc/nginx/snippets/ssl/<ssl_snippet>_ssl.conf`, which the vhost includes and which points at the Let's Encrypt cert. For Route53-managed domains:

```yaml
- { name: example.com, ssl_snippet: example, challenge: route53, aws_profile: aqcom, domains: [example.com, "*.example.com"] }
```

For Cloudflare-managed domains:

```yaml
- { name: example.com, ssl_snippet: example, challenge: cloudflare, domains: [example.com, "*.example.com"] }
```

For a plain nginx-validated cert (no wildcards): `challenge: nginx`.

List every name the cert needs: if the list differs from the existing cert, certbot reissues it with exactly that set. `aws_profile` is `aqcom` or `istic`.
````

Then replace the "Generate the certificate" and "Deploy nginx config and SFTP containers" commands in section 5 with:

```bash
# Generate the certificate and its nginx SSL snippet, then deploy nginx config and SFTP containers
ansible-playbook playbook.yml --tags certbot,nginx,sftp --limit firth.water.gkhs.net
```

Confirm nothing still describes the old loop: `grep -rn "Configure SSL Config\|ssl.nginx.conf.j2" . | grep -v '^./.git/\|docs/superpowers\|galaxy-roles\|\.direnv'`
Expected: no output.

- [ ] **Step 16: Commit**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git add -A roles/firth_nginx roles/atoll_nginx docs/adding-sftp-hosted-site.md
git commit -m "❌ Remove static nginx SSL snippets now generated from certbot_certs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Open the PR

**Files:** none

- [ ] **Step 1: Run the full checks**

```bash
ansible-playbook playbook.yml --syntax-check
ansible-lint
CERTBOT_TEST_DIR=$(mktemp -d) ansible-playbook roles/certbot/tests/render.yml 2>&1 | tail -3
```
Expected: syntax check passes, lint clean, render test `failed=0`.

- [ ] **Step 2: Push and open a draft PR**

```bash
git branch --show-current   # expect: feature/ansible-certbot
git push -u origin feature/ansible-certbot
gh pr create --draft --base main --title "🎇 Manage certbot with Ansible (fix route53 auto-renewals)" --body "$(cat <<'EOF'
## Summary

- New `certbot` role: certs are data in `host_vars/<host>/certbot.yml`, issued with `certbot certonly --expand`.
- Renewal: one systemd service+timer per AWS profile (plus one for cloudflare/nginx certs), each with `AWS_PROFILE` set explicitly, replacing the packaged `certbot.timer`. Fixes route53 auto-renewals failing because the timer ran with no profile and fell back to root's `default` (the aqcom account).
- Each service runs a helper (`/usr/local/sbin/certbot-renew-group`) that calls `certbot renew` once per cert, because `--cert-name` takes only one value.
- Found on atoll during rollout: dovecot there points `ssl_cert` directly at a legacy cert (`atoll.water.gkhs.net`, SANs `atoll.istic.systems` plus a now-dropped typo'd domain) that wasn't in the original data. It's now a managed cert, and atoll's deploy commands gained `service dovecot restart` so it actually gets picked up on renewal.
- Service reloads move to a single deploy hook in `/etc/letsencrypt/renewal-hooks/deploy/`; the per-cert hooks the old scripts saved are stripped.
- `aws_profiles` now runs on all external hosts; certs use the profile names `aqcom` / `istic` (the hand-added `istic-r53` is removed).
- nginx SSL snippets (`/etc/nginx/snippets/ssl/<stem>_ssl.conf`) are generated from the same `certbot_certs` data via an `ssl_snippet` field that keeps each existing filename; the 17 static copies and the `firth_nginx` loop are removed, and the dead `atoll_ssl.conf` is deleted from atoll.
- Removes `bin/generate-*-certbot.sh` and `bin/update-all-certbots.sh`; docs point at `certbot.yml`.

Spec: `docs/superpowers/specs/2026-10-11-ansible-certbot-design.md`

## Verified on firth and atoll

- [x] Cert data matches `certbot certificates` exactly before the first run
- [x] `certbot renew --dry-run` with `AWS_PROFILE=istic` succeeds
- [x] `--tags certbot` reports no `changed` certs
- [x] Each renewal group runs cleanly via `systemctl start`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: the command prints the new PR URL. Only tick the "Verified" boxes in the body if Task 9 was actually run on both hosts.

---

## Self-Review Notes

- **Spec coverage:** §1 data → Task 7; §1b profiles on all external hosts + `istic-r53` cleanup + profile assertion → Tasks 2, 8, 11; §2 role (issue, absent, permissions) → Task 4; §3 deploy-hook directory + legacy `renew_hook` cleanup → Tasks 1, 3; §4 per-group renewal and stock-timer disable → Tasks 1, 5; §5 script/doc removal → Task 10; §6 nginx SSL snippets → Task 12; Migration steps 0–4 → Task 9; Testing (lint, syntax-check, assertions, manual) → Tasks 1, 2, 8, 9.
- **Names used consistently:** `certbot_certs`, `certbot_certs_absent`, `certbot_deploy_commands`, `certbot_legacy_deploy_hooks`, `certbot_plugin_args`, `certbot_group_name` / `certbot_group_profile` / `certbot_group_certs` (templates), `certbot_renew_profiles`, `certbot_default_certs`, `certbot_wanted_units`.
- **Unit names:** `certbot-renew-aws-<profile>.service|timer` and `certbot-renew-default.service|timer`.
- **Change detection:** `changed` is reported by comparing each cert's `fullchain.pem` checksum before and after `certbot certonly` (Task 4), not by parsing certbot's output, so it does not depend on certbot's wording. A failed `certbot` run fails the play at the command task before the comparison.
