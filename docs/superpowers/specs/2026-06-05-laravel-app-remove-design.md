# firth_laravel_app_remove — Design Spec

**Date:** 2026-06-05
**Goal:** A new Ansible role that safely deprovisions a Laravel app from firth, archiving the database and last docker-compose file before any destructive steps.

---

## Overview

`firth_laravel_app_remove` is a standalone role that mirrors the structure of `firth_laravel_app` but tears things down instead of provisioning them. Each removal step is opt-in via a `remove:` flags dict. Archive always runs first, unconditionally. Staging is handled alongside production with the same flags unless overridden.

---

## Variable structure

Defined in `host_vars/firth.water.gkhs.net/laravel_apps_remove.yml`:

```yaml
firth_laravel_app_remove_apps:
  - name: sprouter
    mysql:
      db_name: sprouter
      db_user: sprouter
    redis:
      username: sprouter
    server_name: social.istic.net
    remove:
      containers: false
      mysql: false
      redis: false
      nginx: false
      workdir: false
      system_user: false
    staging:
      mysql:
        db_name: sprouter_staging
        db_user: sprouter_staging
      redis:
        username: sprouter_staging
      server_name: social.istic.dev
      remove: {}  # inherits parent remove flags
```

All `remove:` flags default to `false` — every destructive step must be explicitly opted in. Staging inherits the parent `remove:` block unless it provides its own. If the app has no `mysql:` block, the dump step is skipped and the tarball contains only the docker-compose file.

---

## Role file structure

```
roles/firth_laravel_app_remove/
  defaults/main.yml
  tasks/
    main.yml         — loop over firth_laravel_app_remove_apps
    app.yml          — orchestrate per-app: archive → removals → staging
    archive.yml      — mysqldump + copy docker-compose.yml + create tarball
    containers.yml   — docker compose down
    mysql.yml        — drop database and user
    redis.yml        — remove ACL entry from /etc/redis/users.acl
    nginx.yml        — remove vhost from sites-available + sites-enabled, reload nginx
    workdir.yml      — rm -rf {{ docker_root }}/{{ name }}
    system_user.yml  — userdel + remove /var/lib/{{ name }}
    staging.yml      — run archive + removals for staging environment
```

---

## Task ordering within app.yml

1. Archive (always, unconditional — runs before any removal)
2. Containers (`docker compose down`)
3. Nginx (vhost removal + reload)
4. MySQL (drop DB + user)
5. Redis (remove ACL line)
6. Workdir (`rm -rf {{ docker_root }}/{{ name }}`)
7. System user (`userdel`, remove `/var/lib/{{ name }}`)
8. Staging (same sequence, scoped to `{{ name }}-staging`)

---

## Archive step

For production and staging independently:

1. Check whether `{{ docker_root }}/{{ name }}-archive-{{ date }}.tar.gz` already exists — **fail if it does**, requiring the operator to remove it manually before re-running.
2. Capture today's date via `ansible_date_time.date`.
3. Run `mysqldump -h 127.0.0.1 -u root -p{{ mysql_root_password }} {{ db_name }}` to `/tmp/{{ name }}-{{ date }}.sql`. Skip if no `mysql:` block.
4. Copy `{{ docker_root }}/{{ name }}/docker-compose.yml` to `/tmp/{{ name }}-docker-compose-{{ date }}.yml`.
5. Create `{{ docker_root }}/{{ name }}-archive-{{ date }}.tar.gz` from the temp files (root-owned, mode `0640`).
6. Remove temp files.

---

## Removal steps detail

**containers.yml** — `docker compose down --volumes` in `{{ docker_root }}/{{ name }}`, become `{{ name }}` user. The `--volumes` flag removes the named `{{ name }}_storage` volume (and any anonymous volumes) alongside the containers. No-op if the directory doesn't exist.

**nginx.yml** — Remove `/etc/nginx/sites-enabled/{{ server_name }}.conf` (symlink) and `/etc/nginx/sites-available/{{ server_name }}.conf`, then notify Reload Nginx handler.

**mysql.yml** — Drop database `{{ mysql.db_name }}` and user `{{ mysql.db_user }}` via `community.mysql.mysql_db` / `community.mysql.mysql_user` with `state: absent`, using root credentials.

**redis.yml** — Remove the matching ACL line from `/etc/redis/users.acl` via `lineinfile` with `state: absent`, notify Reload Redis ACL handler.

**workdir.yml** — `file: path={{ docker_root }}/{{ name }} state=absent` for production; `file: path={{ docker_root }}/{{ name }}-staging state=absent` when called from the staging pass.

**system_user.yml** — `user: name={{ name }} state=absent remove=yes force=yes`. Removes home at `/var/lib/{{ name }}` including the production/staging symlinks.

---

## Defaults

```yaml
# roles/firth_laravel_app_remove/defaults/main.yml
firth_laravel_app_remove_apps: []
firth_laravel_app_remove_mysql_login_host: 127.0.0.1
firth_laravel_app_remove_mysql_login_user: root
```

---

## What this role does NOT do

- Remove GitHub Actions secrets or the deploy keypair from GitHub
- Remove GHCR images
- Modify `laravel_apps.yml` — the operator removes the entry manually after running this role
