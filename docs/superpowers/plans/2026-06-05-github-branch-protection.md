# GitHub Branch Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply a consistent GitHub Ruleset enforcing PR reviews, status checks, and no force-pushes to a defined list of repos spanning two GitHub accounts.

**Architecture:** A new `github_branch_protection` role loops over `github_protected_repos`, calling the GitHub Rulesets API via `ansible.builtin.uri`. Each repo gets a GET → POST-or-PUT sequence to create or update an `ansible-managed` ruleset idempotently. Non-secret vars live in `host_vars/localhost/main.yml`; the PAT lives in `host_vars/localhost/github.vault.yml`.

**Tech Stack:** Ansible `ansible.builtin.uri`, `community.general.dict_kv` filter, ansible-vault

---

## Files

| Action | Path | Purpose |
|--------|------|---------|
| Create | `roles/github_branch_protection/defaults/main.yml` | Default vars: ruleset name, default branch, empty overrides dict |
| Create | `roles/github_branch_protection/tasks/main.yml` | Loop over repos, include apply_ruleset.yml per repo |
| Create | `roles/github_branch_protection/tasks/apply_ruleset.yml` | GET + set_fact + conditional POST or PUT for a single repo |
| Create | `host_vars/localhost/main.yml` | Repo list and per-repo status check overrides |
| Create | `host_vars/localhost/github.vault.yml` | Vault-encrypted GitHub PAT |
| Create | `github.yml` | Playbook targeting localhost |

---

### Task 1: Role defaults

**Files:**
- Create: `roles/github_branch_protection/defaults/main.yml`

- [ ] **Step 1: Create the defaults file**

```yaml
# roles/github_branch_protection/defaults/main.yml
---
github_ruleset_name: ansible-managed
github_default_branch: main
github_status_check_overrides: {}
```

- [ ] **Step 2: Lint**

```bash
ansible-lint roles/github_branch_protection/defaults/main.yml
```

Expected: no warnings or errors.

- [ ] **Step 3: Commit**

```bash
git add roles/github_branch_protection/defaults/main.yml
git commit -m "🎇 Add github_branch_protection role defaults"
```

---

### Task 2: Host vars for localhost

**Files:**
- Create: `host_vars/localhost/main.yml`

`localhost` is already in inventory (`etc/inventory.ini`), so `host_vars/localhost/` is picked up automatically.

- [ ] **Step 1: Create the host vars file**

Replace the example repos with the actual list before committing.

```yaml
# host_vars/localhost/main.yml
---
github_protected_repos:
  - { owner: aquarion, repo: autopelago }
  - { owner: istic, repo: example-repo }

github_status_check_overrides:
  autopelago: [ansible-lint]
```

- [ ] **Step 2: Commit**

```bash
git add host_vars/localhost/main.yml
git commit -m "🎇 Add localhost host_vars for GitHub branch protection"
```

---

### Task 3: Vault file for GitHub PAT

**Files:**
- Create: `host_vars/localhost/github.vault.yml`

The pre-commit hook (`check-vault-files`) requires files matching `*.vault.*` to be ansible-vault encrypted. `vault_password_file` is already set in `ansible.cfg` to `~/.vault_pass.txt`.

- [ ] **Step 1: Create and encrypt the vault file**

```bash
ansible-vault create host_vars/localhost/github.vault.yml
```

This opens your editor. Enter the following content (replace the token value with your actual PAT — needs `repo` scope):

```yaml
vault_github_pat: ghp_your_token_here
```

Save and close. The file will be encrypted on disk.

- [ ] **Step 2: Verify it is encrypted**

```bash
head -1 host_vars/localhost/github.vault.yml
```

Expected output:
```
$ANSIBLE_VAULT;1.1;AES256
```

- [ ] **Step 3: Commit**

```bash
git add host_vars/localhost/github.vault.yml
git commit -m "🎇 Add vault-encrypted GitHub PAT for branch protection"
```

---

### Task 4: apply_ruleset.yml subtask

**Files:**
- Create: `roles/github_branch_protection/tasks/apply_ruleset.yml`

This file handles one repo (passed as `github_repo_item` loop variable from `main.yml`). It builds the status check list, fetches existing rulesets, then creates or updates the `ansible-managed` ruleset.

- [ ] **Step 1: Create the file**

```yaml
# roles/github_branch_protection/tasks/apply_ruleset.yml
---
- name: Build_status_check_contexts
  ansible.builtin.set_fact:
    github_repo_check_contexts: >-
      {{ (github_status_check_overrides[github_repo_item.repo] | default([]))
         | map('community.general.dict_kv', 'context') | list }}

- name: Get_existing_rulesets
  ansible.builtin.uri:
    url: "https://api.github.com/repos/{{ github_repo_item.owner }}/{{ github_repo_item.repo }}/rulesets"
    method: GET
    headers:
      Authorization: "Bearer {{ vault_github_pat }}"
      Accept: "application/vnd.github+json"
      X-GitHub-Api-Version: "2022-11-28"
    status_code: 200
  register: github_rulesets_result

- name: Set_existing_ruleset_fact
  ansible.builtin.set_fact:
    github_existing_ruleset: >-
      {{ github_rulesets_result.json
         | selectattr('name', '==', github_ruleset_name)
         | list | first | default({}) }}

- name: Create_ruleset
  ansible.builtin.uri:
    url: "https://api.github.com/repos/{{ github_repo_item.owner }}/{{ github_repo_item.repo }}/rulesets"
    method: POST
    headers:
      Authorization: "Bearer {{ vault_github_pat }}"
      Accept: "application/vnd.github+json"
      X-GitHub-Api-Version: "2022-11-28"
    body_format: json
    body:
      name: "{{ github_ruleset_name }}"
      target: branch
      enforcement: active
      conditions:
        ref_name:
          include:
            - "refs/heads/{{ github_default_branch }}"
          exclude: []
      bypass_actors: []
      rules:
        - type: non_fast_forward
        - type: pull_request
          parameters:
            required_approving_review_count: 1
            dismiss_stale_reviews_on_push: false
            require_code_owner_review: false
            require_last_push_approval: false
        - type: required_status_checks
          parameters:
            required_status_checks: "{{ github_repo_check_contexts }}"
            strict_required_status_checks_policy: false
    status_code: 201
  when: not github_existing_ruleset

- name: Update_ruleset
  ansible.builtin.uri:
    url: "https://api.github.com/repos/{{ github_repo_item.owner }}/{{ github_repo_item.repo }}/rulesets/{{ github_existing_ruleset.id }}"
    method: PUT
    headers:
      Authorization: "Bearer {{ vault_github_pat }}"
      Accept: "application/vnd.github+json"
      X-GitHub-Api-Version: "2022-11-28"
    body_format: json
    body:
      name: "{{ github_ruleset_name }}"
      target: branch
      enforcement: active
      conditions:
        ref_name:
          include:
            - "refs/heads/{{ github_default_branch }}"
          exclude: []
      bypass_actors: []
      rules:
        - type: non_fast_forward
        - type: pull_request
          parameters:
            required_approving_review_count: 1
            dismiss_stale_reviews_on_push: false
            require_code_owner_review: false
            require_last_push_approval: false
        - type: required_status_checks
          parameters:
            required_status_checks: "{{ github_repo_check_contexts }}"
            strict_required_status_checks_policy: false
    status_code: 200
  when: github_existing_ruleset
```

- [ ] **Step 2: Lint**

```bash
ansible-lint roles/github_branch_protection/tasks/apply_ruleset.yml
```

Expected: no warnings or errors.

- [ ] **Step 3: Commit**

```bash
git add roles/github_branch_protection/tasks/apply_ruleset.yml
git commit -m "🎇 Add apply_ruleset subtask for GitHub Rulesets API"
```

---

### Task 5: tasks/main.yml

**Files:**
- Create: `roles/github_branch_protection/tasks/main.yml`

- [ ] **Step 1: Create the file**

```yaml
# roles/github_branch_protection/tasks/main.yml
---
- name: Apply_branch_protection_ruleset
  ansible.builtin.include_tasks: apply_ruleset.yml
  loop: "{{ github_protected_repos }}"
  loop_control:
    loop_var: github_repo_item
    label: "{{ github_repo_item.owner }}/{{ github_repo_item.repo }}"
```

- [ ] **Step 2: Lint**

```bash
ansible-lint roles/github_branch_protection/tasks/main.yml
```

Expected: no warnings or errors.

- [ ] **Step 3: Commit**

```bash
git add roles/github_branch_protection/tasks/main.yml
git commit -m "🎇 Add github_branch_protection role main tasks"
```

---

### Task 6: Playbook

**Files:**
- Create: `github.yml`

`localhost` is in inventory with `ansible_connection=local`. No `become` needed — this is pure API calls.

- [ ] **Step 1: Create the playbook**

```yaml
# github.yml
---
- name: GitHub repository management
  hosts: localhost
  gather_facts: false
  roles:
    - github_branch_protection
```

- [ ] **Step 2: Lint the full playbook**

```bash
ansible-lint github.yml
```

Expected: no warnings or errors.

- [ ] **Step 3: Commit**

```bash
git add github.yml
git commit -m "🎇 Add github.yml playbook for repository management"
```

---

### Task 7: Run

- [ ] **Step 1: Run the playbook**

```bash
ansible-playbook github.yml
```

Expected: tasks complete with `ok` or `changed` for each repo; no failures.

- [ ] **Step 2: Verify in GitHub UI**

For each repo in `github_protected_repos`, check Settings → Rules → Rulesets. You should see an `ansible-managed` ruleset with:
- Enforcement: Active
- Target: Default branch
- Rules: Restrict force pushes, Require pull request, Require status checks

- [ ] **Step 3: Re-run to verify idempotency**

```bash
ansible-playbook github.yml
```

Expected: playbook completes without errors. `Update_ruleset` tasks will still report `changed` (Ansible's `uri` module always reports changed for PUT/POST regardless of content). Confirm no duplicate `ansible-managed` rulesets appear in the GitHub UI — only one per repo.
