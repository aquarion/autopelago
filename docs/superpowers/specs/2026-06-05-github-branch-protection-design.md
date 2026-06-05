# GitHub Branch Protection — Design Spec

**Date:** 2026-06-05

## Overview

An Ansible role and playbook to enforce consistent branch protection rules across a defined set of repos spanning two GitHub accounts (`aquarion` personal and `istic` org). Runs from localhost using the GitHub REST API (Rulesets API) via `ansible.builtin.uri` with a vault-stored PAT.

## Structure

New role:
```
roles/github_branch_protection/
  tasks/main.yml         # loop over repos, apply ruleset via GitHub API
  defaults/main.yml      # default rule config and empty override dict
```

New playbook at repo root:
```
github.yml               # targets localhost, connection: local
```

Updated files:
```
group_vars/all.yml       # add github_protected_repos and github_status_check_overrides
host_vars/localhost/vault.yml  # new vault file — GitHub PAT
```

## Repo List

`github_protected_repos` in `group_vars/all.yml` — a list of `{ owner, repo }` dicts:

```yaml
github_protected_repos:
  - { owner: aquarion, repo: autopelago }
  - { owner: istic, repo: some-repo }
```

## Ruleset Design

A single named ruleset (`ansible-managed`) is applied to the default branch (var: `github_default_branch`, default: `main`) of each repo. Rules are enforced for everyone — no bypass actors are configured.

### Rules

| Rule | Ruleset type | Parameters |
|------|-------------|------------|
| Block force pushes | `non_fast_forward` | none |
| Require PR before merge | `pull_request` | `required_approving_review_count: 1`, `dismiss_stale_reviews_on_push: false` |
| Require status checks | `required_status_checks` | `required_status_checks: [...]`, `strict_required_status_checks_policy: false` |

### Status Check Contexts

Default (`defaults/main.yml`): `github_status_check_overrides: {}`

Override in `group_vars/all.yml` for repos with specific named checks:

```yaml
github_status_check_overrides:
  autopelago: [run-tests]
```

Repos not in the override dict get an empty `required_status_checks` list — meaning the rule is present but any passing check satisfies it. Each named check is passed as `{ context: "name" }` per the Rulesets API format.

### Enforcement

`enforcement: active` — rules are enforced immediately. No bypass actors means admins are subject to the same rules.

## Idempotency

The Rulesets API has no single idempotent PUT. The task sequence per repo is:

1. `GET /repos/{owner}/{repo}/rulesets` — find existing ruleset named `ansible-managed`
2. If found: `PUT /repos/{owner}/{repo}/rulesets/{id}` — update in place
3. If not found: `POST /repos/{owner}/{repo}/rulesets` — create

This makes re-runs safe with no duplicate rulesets created.

## Authentication

Single GitHub PAT with `repo` scope, stored in `host_vars/localhost/vault.yml` as `vault_github_pat`. Covers both `aquarion` and `istic` accounts. Passed as a Bearer token header on all API calls.

Run with:
```
ansible-playbook github.yml --ask-vault-pass
```

## Error Handling

`ansible.builtin.uri` will fail the task on non-2xx responses, surfacing the GitHub API error message. No special retry logic needed — re-runs are safe due to the GET-then-POST-or-PUT pattern.

## Out of Scope

- Dynamic repo discovery (repos are explicitly listed)
- Classic branch protection API (deprecated by GitHub)
- Branch protection for non-default branches
- Org-level rulesets (repo-level rulesets are sufficient)
