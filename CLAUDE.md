# autopelago

## Ansible

- Never run `ansible-playbook` piped through `tail`, `head`, or anything else that truncates output. Redirect full output to a file (e.g. `poetry run ansible-playbook ... 2>&1 | tee /tmp/run.log`) so the complete task list, including every `changed:` line, is preserved for review. Playbook runs are not always safely repeatable to recover lost output — once a task changes state, rerunning shows `ok`, not `changed`.
- Ansible here is declarative but not garbage-collecting. Removing or renaming a task just stops future runs from re-asserting that state — it does not undo what was already created on the target system. Any change that removes, renames, or replaces a task that created something on a remote system (Route53/Cloudflare records, apt source files, keyrings, systemd units, templated config files, etc.) needs an explicit cleanup task (`state: absent` / `command: delete`), not just a config change.
- Before implementing a new URI/API task or "solved" infra pattern (secret uploads, variable management, idempotency checks), check `roles/stream_delta/` first — it often already has the established pattern (e.g. the idempotent GitHub secret-upload pattern using `changed_when: status == 201`).

## Laravel apps on firth (`firth_laravel_app` role)

- All Laravel apps on `firth.water.gkhs.net` (alchemistic, novelathon, bloom, docket, wereabouts, thalium) are managed by one parametric `firth_laravel_app` role, not per-app roles.
- **Config location:** app list in `host_vars/firth.water.gkhs.net/laravel_apps.yml`; per-app secrets in `host_vars/firth.water.gkhs.net/laravel/` (one vault file per app).
- **System user:** each app gets a system user with shell `/bin/bash` — must not be `nologin`, since SSH deploys need a real shell. User is in the `docker` group.
- **GitHub tokens:** `laravel_apps_deploy_token_istic` for istic org repos, `laravel_apps_deploy_token_aquarion` for aquarion org repos. The generic `github_deploy_token` is scoped to personal repos only and 404s on org repos.
- **Bootstrapping a new app:** it has no image yet on first deploy. Run with `--skip-tags=laravel_apps_deploy` first to provision DB/Redis/nginx/system user without starting the container, then deploy normally once the image exists.
- **Elasticsearch CA cert path is intentional:** `firth_laravel_app_elasticsearch_ca_cert` defaults to the raw Docker volume host path (`/var/lib/docker/volumes/elasticsearch_certs/_data/ca/ca.crt`) rather than a cleaner path like `/etc/ssl/certs/`. This was arrived at after extensive permissions debugging — don't refactor it without expecting to re-solve those permission issues.
