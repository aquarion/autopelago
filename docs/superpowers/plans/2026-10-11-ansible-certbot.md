# Ansible-Managed Certbot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `bin/generate-*-certbot.sh` and `bin/update-all-certbots.sh` with an Ansible `certbot` role that issues certs from per-host data and renews each route53 profile with the right `AWS_PROFILE`.

**Architecture:** A new `certbot` role (tag `certbot`) loops over `certbot_certs` (host_vars data) running `certbot certonly`, installs one deploy hook in `/etc/letsencrypt/renewal-hooks/deploy/`, and generates one systemd renewal service + timer per renewal group (one per AWS profile, plus one for cloudflare/nginx certs), replacing the packaged `certbot.timer`. `aws_profiles` moves to the "all external hosts" play so root's `~/.aws` is Ansible-managed everywhere.

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
| `roles/certbot/tests/render.yml` | Renders the templates with sample data and asserts on the output |
| `host_vars/firth.water.gkhs.net/certbot.yml` | Firth's certs, as data |
| `host_vars/atoll.water.gkhs.net/certbot.yml` | Atoll's certs, as data (including the archive cert) |
| `playbook.yml` | Move `aws_profiles`; add the certbot play |
| `roles/aws_profiles/tasks/main.yml` | Remove the legacy `istic-r53` profile (last task, after verification) |
| `docs/adding-sftp-hosted-site.md` | Point at `certbot.yml` instead of the scripts |
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
          - "'service nginx reload\n' in (certbot_rendered.results[0].content | b64decode)"
          - "'service dovecot restart\n' in (certbot_rendered.results[0].content | b64decode)"
          - "'Environment=AWS_PROFILE=istic\n' in (certbot_rendered.results[1].content | b64decode)"
          - "'--cert-name istic.net --cert-name nanocountdown.com\n' in (certbot_rendered.results[1].content | b64decode)"
          - "'AWS_PROFILE' not in (certbot_rendered.results[2].content | b64decode)"
          - "'--cert-name socksandpuppets.com\n' in (certbot_rendered.results[2].content | b64decode)"
          - "'OnCalendar=' in (certbot_rendered.results[3].content | b64decode)"
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
# Run by certbot after any certificate is issued or renewed.
set -e
{% for cmd in certbot_deploy_commands %}
{{ cmd }}
{% endfor %}
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
ExecStart=/usr/bin/certbot renew --quiet --no-self-upgrade{% for cert in certbot_group_certs %} --cert-name {{ cert }}{% endfor %}

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

# Commands the deploy hook runs after any cert is issued or renewed (set per host).
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
      - certbot_certs | map(attribute='challenge') | difference(['route53', 'cloudflare', 'nginx']) | length == 0
      - (certbot_certs | map(attribute='name') | list | length) == (certbot_certs | map(attribute='name') | unique | list | length)
      - certbot_certs | selectattr('challenge', 'equalto', 'route53') | rejectattr('aws_profile', 'defined') | list | length == 0
      - certbot_certs | selectattr('challenge', 'equalto', 'nginx') | map(attribute='domains') | flatten | select('match', '^\*\.') | list | length == 0
    fail_msg: >-
      certbot_certs is malformed. Every entry needs name, challenge (route53|cloudflare|nginx) and domains;
      names must be unique; route53 entries need aws_profile; nginx entries cannot contain wildcards
      (http-01 cannot validate them).
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
      Run the aws_profiles role first (--tags aws).
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
      (certbot_renewal_confs.files | map(attribute='path') | map('basename') | map('regex_replace', '.conf$', '')
       | difference(certbot_certs | map(attribute='name') | list) | difference(certbot_certs_absent)) | length == 0
    fail_msg: >-
      These certs exist on the host but are not in certbot_certs or certbot_certs_absent, so nothing would renew them:
      {{ certbot_renewal_confs.files | map(attribute='path') | map('basename') | map('regex_replace', '.conf$', '')
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

- name: Install the deploy hook that reloads services after issuance/renewal
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
- name: Remove per-cert deploy hooks saved by the old scripts
  ansible.builtin.lineinfile:
    path: "{{ item.path }}"
    regexp: "^renew_hook = ({{ certbot_legacy_deploy_hooks | map('regex_escape') | join('|') }})$"
    state: absent
  loop: "{{ certbot_renewal_confs.files }}"
  loop_control:
    label: "{{ item.path | basename }}"
  when: certbot_legacy_deploy_hooks | length > 0
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
- Create: `roles/certbot/tasks/renewal.yml`

- [ ] **Step 1: Write the tasks**

Create `roles/certbot/tasks/renewal.yml`:

```yaml
---
# One renewal group per AWS profile among the route53 certs, plus one "default" group for
# cloudflare and nginx certs. Each group is its own systemd service+timer so a broken profile
# fails (and alerts) on its own, and AWS_PROFILE can be set per group.
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

- name: Disable the packaged certbot timer (it renews with no AWS_PROFILE)
  ansible.builtin.systemd:
    name: certbot.timer
    enabled: false
    state: stopped
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

- [ ] **Step 2: Lint**

Run: `ansible-lint roles/certbot`
Expected: no violations.

- [ ] **Step 3: Check the group/unit-name expressions with sample data**

```bash
ansible localhost -c local -m ansible.builtin.debug -a "msg={{ ['aqcom','istic'] | map('regex_replace','^','certbot-renew-aws-') | map('regex_replace','\$','.timer') | list }}"
```
Expected: `["certbot-renew-aws-aqcom.timer", "certbot-renew-aws-istic.timer"]`.

The expressions avoid regex backreferences and backslashes on purpose: `'^'` adds a prefix and `'$'` adds a suffix, and `select('search', 'timer$')` picks the timer units out of a list of unit names.

- [ ] **Step 4: Commit**

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
# Order matters: validate first; install the deploy hook BEFORE issuing so a first issuance
# reloads services; issue; then set up renewal.
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
certbot_deploy_commands:
  - service nginx reload
  - service dovecot restart

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
    challenge: nginx
    domains: [forums.profounddecisions.co.uk]
  - name: michael.conterio.co.uk
    challenge: nginx
    domains: [michael.conterio.co.uk, www.michael.conterio.co.uk, conterio.co.uk, www.conterio.co.uk]

  # --- cloudflare ---
  - { name: socksandpuppets.com, challenge: cloudflare, domains: [socksandpuppets.com, "*.socksandpuppets.com"] }
  - { name: aquarionics.com, challenge: cloudflare, domains: [aquarionics.com, "*.aquarionics.com"] }
  - { name: novelathon.com, challenge: cloudflare, domains: [novelathon.com, "*.novelathon.com"] }
  - { name: istic.dev, challenge: cloudflare, domains: [istic.dev, "*.istic.dev"] }

  # --- route53, istic account ---
  - name: istic.net
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
  - { name: svc.istic.systems, challenge: route53, aws_profile: istic, domains: [svc.istic.systems, "*.svc.istic.systems"] }
  - { name: carcosadreams.com, challenge: route53, aws_profile: istic, domains: [carcosadreams.com, "*.carcosadreams.com", "*.carcosadreams.co.uk"] }
  - { name: ludoistic.com, challenge: route53, aws_profile: istic, domains: [ludoistic.com, "*.ludoistic.com"] }
  - { name: nanocountdown.com, challenge: route53, aws_profile: istic, domains: [nanocountdown.com, "*.nanocountdown.com"] }
  - { name: bloomfeed.app, challenge: route53, aws_profile: istic, domains: [bloomfeed.app, "*.bloomfeed.app"] }

  # --- route53, aqcom account ---
  - name: nicholasavenell.com
    challenge: route53
    aws_profile: aqcom
    domains: [nicholasavenell.com, "*.nicholasavenell.com", "*.nicholasavenell.net", nicholasavenell.net]
  - { name: bromioscreations.com, challenge: route53, aws_profile: aqcom, domains: [bromioscreations.com, "*.bromioscreations.com"] }
  - { name: larp.me, challenge: route53, aws_profile: aqcom, domains: [larp.me, "*.larp.me", larp.me.uk, "*.larp.me.uk"] }
  - { name: camlarp.co.uk, challenge: route53, aws_profile: aqcom, domains: [camlarp.co.uk, "*.camlarp.co.uk"] }
  # DNS-01 on purpose (not nginx): the live cert includes *.hubris.house
  - { name: hubris.house, challenge: route53, aws_profile: aqcom, domains: [hubris.house, "*.hubris.house"] }
  - { name: kastark.co.uk, challenge: route53, aws_profile: aqcom, domains: [kastark.co.uk, www.kastark.co.uk, dhmstark.co.uk, www.dhmstark.co.uk] }
```

- [ ] **Step 2: Write atoll's data**

Create `host_vars/atoll.water.gkhs.net/certbot.yml`:

```yaml
---
# Certificates on atoll. See docs/superpowers/specs/2026-10-11-ansible-certbot-design.md.
certbot_deploy_commands:
  - service nginx reload

# The archive site's public domain is an Ansible variable; the cert is only requested if it is set.
certbot_certs_archive: >-
  {{ [{'name': stream_delta_archive_public_domain, 'challenge': 'nginx', 'domains': [stream_delta_archive_public_domain]}]
     if (stream_delta_archive_public_domain | default('')) | length > 0 else [] }}

certbot_certs_static:
  - { name: voyeur.istic.net, challenge: route53, aws_profile: istic, domains: [voyeur.istic.net, "*.voyeur.istic.net", "*.ws.voyeur.istic.net"] }
  - { name: voyeur.istic.dev, challenge: cloudflare, domains: [voyeur.istic.dev, "*.voyeur.istic.dev", "*.ws.voyeur.istic.dev"] }

certbot_certs: "{{ certbot_certs_static + certbot_certs_archive }}"
```

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

- [ ] **Step 1: Apply the AWS profiles (root's `~/.aws`)**

```bash
ansible-playbook playbook.yml --tags aws --limit firth.water.gkhs.net 2>&1 | tee /tmp/aws-firth.log
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

A cert that appears only in `/tmp/actual.txt` is on the host but not in the data. The role's validation guard will refuse to run until each such cert is either added to `certbot_certs` (if it is still used, for example `atoll.water.gkhs.net`, which `atoll_ssl.conf` points at) or listed in `certbot_certs_absent` (if it should be deleted). Decide each one deliberately: with the packaged timer disabled, a cert in neither list would stop renewing. Repeat with `HOST=atoll.water.gkhs.net` before touching atoll.

- [ ] **Step 4: Confirm how the old hooks were saved**

On the host: `sudo grep -rn 'hook' /etc/letsencrypt/renewal/ | head`
Expected: lines like `renew_hook = service nginx reload; service dovecot restart` in some `.conf` files. If the key is not `renew_hook` (for example `deploy_hook`), change the `regexp` in `roles/certbot/tasks/hooks.yml` to match before the next step.

- [ ] **Step 5: Run the certbot role**

```bash
ansible-playbook playbook.yml --tags certbot --limit firth.water.gkhs.net 2>&1 | tee /tmp/certbot-firth.log
```
Expected: validation passes; the issuance loop reports `ok` for every cert (no `changed`, since nothing is due); the unit-file tasks report `changed` on the first run; no failures. Then read `/tmp/certbot-firth.log` in full and confirm no cert shows `changed`.

- [ ] **Step 6: Verify the timers and a real renewal path per group**

On firth:
```bash
systemctl list-timers 'certbot*' --all
sudo systemctl start certbot-renew-aws-istic.service && journalctl -u certbot-renew-aws-istic.service -n 20 --no-pager
sudo systemctl start certbot-renew-aws-aqcom.service && journalctl -u certbot-renew-aws-aqcom.service -n 20 --no-pager
sudo systemctl start certbot-renew-default.service && journalctl -u certbot-renew-default.service -n 20 --no-pager
```
Expected: `certbot.timer` is no longer listed; the three `certbot-renew-*` timers are; each service run ends with `Deactivated successfully` and no `Unable to find a Route53 hosted zone` error. (`certbot renew` skips certs that are not due, so a clean no-op is a pass.)

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
ansible-playbook playbook.yml --tags aws --limit 'firth.water.gkhs.net,atoll.water.gkhs.net' 2>&1 | tee /tmp/aws-cleanup.log
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

### Task 12: Open the PR

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
- Service reloads move to a single deploy hook in `/etc/letsencrypt/renewal-hooks/deploy/`; the per-cert hooks the old scripts saved are stripped.
- `aws_profiles` now runs on all external hosts; certs use the profile names `aqcom` / `istic` (the hand-added `istic-r53` is removed).
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

- **Spec coverage:** §1 data → Task 7; §1b profiles on all external hosts + `istic-r53` cleanup + profile assertion → Tasks 2, 8, 11; §2 role (issue, absent, permissions) → Task 4; §3 deploy-hook directory + legacy `renew_hook` cleanup → Tasks 1, 3; §4 per-group renewal and stock-timer disable → Tasks 1, 5; §5 script/doc removal → Task 10; Migration steps 0–4 → Task 9; Testing (lint, syntax-check, assertions, manual) → Tasks 1, 2, 8, 9.
- **Names used consistently:** `certbot_certs`, `certbot_certs_absent`, `certbot_deploy_commands`, `certbot_legacy_deploy_hooks`, `certbot_plugin_args`, `certbot_group_name` / `certbot_group_profile` / `certbot_group_certs` (templates), `certbot_renew_profiles`, `certbot_default_certs`, `certbot_wanted_units`.
- **Unit names:** `certbot-renew-aws-<profile>.service|timer` and `certbot-renew-default.service|timer`.
- **Change detection:** `changed` is reported by comparing each cert's `fullchain.pem` checksum before and after `certbot certonly` (Task 4), not by parsing certbot's output, so it does not depend on certbot's wording. A failed `certbot` run fails the play at the command task before the comparison.
