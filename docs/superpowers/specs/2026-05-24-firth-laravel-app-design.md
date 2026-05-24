# firth_laravel_app Role Design

**Date:** 2026-05-24
**Status:** Approved

## Summary

Replace `firth_novelathon` and `firth_alchemistic` with a single parametric role `firth_laravel_app` that handles all Dockerised Laravel apps on firth. Also deploys Sprouter (`social.istic.net`) as a new app using the same role.

DNS registration is out of scope — handled separately per-app as zones and providers vary.

---

## Variable Structure

Apps are defined as a list in `host_vars/firth.water.gkhs.net/laravel_apps.yml`:

```yaml
firth_laravel_apps:
  - name: novelathon
    image: ghcr.io/istic/novelathon
    image_tag: latest
    backend: fpm               # fpm | octane
    port: 9001                 # fastcgi port (fpm) or Octane HTTP port
    server_name: novelathon.com
    app_url: https://novelathon.com
    app_key: "{{ vault_novelathon_app_key }}"
    github_repo: istic/novelathon
    github_deploy_token: "{{ vault_novelathon_github_deploy_token }}"
    ghcr_username: "{{ ghcr_username }}"
    ghcr_token: "{{ ghcr_token }}"
    worker: true
    mysql:
      db_name: novelathon
      db_user: novelathon
      db_password: "{{ vault_novelathon_db_password }}"
    redis:
      username: novelathon
      password: "{{ vault_novelathon_redis_password }}"
    mail:
      host: "{{ mail_host }}"
      port: 587
      username: "{{ mail_username }}"
      password: "{{ vault_mail_password }}"
      from_address: noreply@novelathon.com
      from_name: Novelathon
    staging:
      image_tag: staging
      port: 9002
      server_name: novelathon.istic.dev
      app_url: https://novelathon.istic.dev
      app_key: "{{ vault_novelathon_staging_app_key }}"
      mysql:
        db_name: novelathon_staging
        db_user: novelathon_stg
        db_password: "{{ vault_novelathon_staging_db_password }}"
      redis:
        username: novelathon_stg
        password: "{{ vault_novelathon_staging_redis_password }}"

  - name: sprouter
    image: ghcr.io/aquarion/sprouter
    image_tag: latest
    backend: octane
    port: 8000
    server_name: social.istic.net
    app_url: https://social.istic.net
    app_key: "{{ vault_sprouter_app_key }}"
    github_repo: aquarion/sprouter
    github_deploy_token: "{{ vault_sprouter_github_deploy_token }}"
    ghcr_username: "{{ ghcr_username }}"
    ghcr_token: "{{ ghcr_token }}"
    mysql:
      db_name: sprouter
      db_user: sprouter
      db_password: "{{ vault_sprouter_db_password }}"
    redis:
      username: sprouter
      password: "{{ vault_sprouter_redis_password }}"
    mail:
      host: "{{ mail_host }}"
      port: 587
      username: "{{ mail_username }}"
      password: "{{ vault_mail_password }}"
      from_address: noreply@social.istic.net
      from_name: Sprouter
```

Alchemistic follows the same structure as novelathon (`backend: fpm`, `port: 9000`, no `staging`, no `worker`). Its entry is omitted from the example above for brevity.

**Conventions:**
- `mysql` absent → no database provisioned; `redis` absent → no Redis ACL entry
- `staging` absent → no staging environment
- `worker: true` → queue worker service added to docker-compose
- Elasticsearch deferred until an app needs it; the dict structure accommodates an `elasticsearch:` key without other changes

---

## Role Structure

```
roles/firth_laravel_app/
  defaults/main.yml
  handlers/main.yml
  tasks/
    main.yml          ← loops over firth_laravel_apps; sets fla fact; calls app.yml
    app.yml           ← orchestrates sub-tasks for one app
    system_user.yml   ← system user (docker group), SSH keypair, GitHub secret upload
    mysql.yml         ← database + user (skipped if mysql key absent)
    redis.yml         ← ACL entry in /etc/redis/users.acl (skipped if redis key absent)
    ghcr.yml          ← docker login as system user (skipped if image is not ghcr.io/*)
    deploy.yml        ← docker_compose_v2, Vite asset copy, migrations
    nginx.yml         ← vhost template + sites-enabled symlink
    staging.yml       ← repeats deploy.yml + nginx.yml with staging overrides
  templates/
    docker-compose.yml.j2
    vhosts/app.conf.j2
```

### Loop variable pattern

`main.yml` loops with `loop_var: firth_laravel_app_item` to satisfy ansible-lint's `loop-var-prefix` rule. At the top of `app.yml`, a `fla` fact is set from `firth_laravel_app_item` so sub-task files remain readable.

---

## Templates

### `docker-compose.yml.j2`

Single template covering all apps. Key conditionals:

- Port mapping: inner port is `9000` (fpm) or `8000` (octane) based on `fla.backend`
- `DB_*` environment block included only when `fla.mysql` is defined
- `REDIS_*` environment block included only when `fla.redis` is defined
- `worker` service added (using YAML anchor from `app`) when `fla.worker` is true
- All services use `journald` logging with `tag: "$${.Name}/$${.ID}"`
- `extra_hosts: host.docker.internal:host-gateway` always present

### `vhosts/app.conf.j2`

Single vhost template. Key conditionals:

- FPM backend: `fastcgi_pass 127.0.0.1:{{ fla.port }}` with `fastcgi_params`
- Octane backend: `proxy_pass http://127.0.0.1:{{ fla.port }}` with forwarded headers
- `/build/` location always served directly from `{{ docker_root }}/{{ fla.name }}/public/build/`
- SSL snippet included as `ssl/{{ fla.server_name }}_ssl.conf` (managed by `firth_nginx`)

Staging uses the same two templates, rendered into `{{ docker_root }}/{{ fla.name }}-staging/`.

---

## Paths Convention

| Resource | Path |
|---|---|
| System user home | `/var/lib/{{ fla.name }}` |
| SSH deploy key | `/var/lib/{{ fla.name }}/.ssh/id_ed25519` |
| Production compose dir | `{{ docker_root }}/{{ fla.name }}/` |
| Staging compose dir | `{{ docker_root }}/{{ fla.name }}-staging/` |
| Vite assets | `{{ docker_root }}/{{ fla.name }}/public/build/` |
| nginx vhost | `/etc/nginx/sites-available/{{ fla.server_name }}.conf` |

---

## Migration Plan

### Phase 1 — build `firth_laravel_app`

1. Create the role with all task files and templates
2. Add `firth_laravel_app` to playbook.yml alongside the existing roles
3. Create `host_vars/firth.water.gkhs.net/laravel_apps.yml` with novelathon, alchemistic, and sprouter entries, porting existing vault vars across
4. Test with `--check` against firth

### Phase 2 — migrate existing apps

1. Remove `firth_novelathon` and `firth_alchemistic` from playbook.yml
2. Delete both roles
3. Run the playbook live — `firth_laravel_app` takes over

### Phase 3 — Sprouter

1. Generate `APP_KEY` for sprouter, populate vault vars
2. First live deploy via the playbook
3. Verify `social.istic.net` is reachable
