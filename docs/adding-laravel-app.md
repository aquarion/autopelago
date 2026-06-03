# Adding a new Laravel app to firth

Laravel apps run as Docker containers managed by the `firth_laravel_app` Ansible role. Each app gets a system user, MySQL database, optional Redis user, an nginx vhost, and a GitHub Actions deploy key automatically provisioned.

Docket is the most complete reference implementation for this pattern.

---

## 1. Prerequisites

- The app's Docker image must be published to GHCR (`ghcr.io/<org>/<name>`)
- A GitHub token with `repo` and `secrets:write` scope for the repository (to upload the deploy key)
- A GitHub token with `read:packages` scope for GHCR (shared `ghcr_token` in vault usually suffices)
- An nginx SSL snippet in `roles/firth_nginx/templates/snippets/` matching the domain's certificate

---

## 2. Generate secrets

Generate secrets for the new app and add them to a vault file at `host_vars/firth.water.gkhs.net/laravel/<appname>.vault.yml`:

```yaml
vault_<appname>_app_key: "base64:..."   # php artisan key:generate --show
vault_<appname>_db_password: "..."
vault_<appname>_redis_password: "..."   # if using Redis
```

For staging add corresponding `vault_<appname>_staging_*` variants.

To generate a Laravel app key without a running container:
```bash
docker run --rm php:8.3-cli php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"
```

Encrypt the vault file before committing:
```bash
ansible-vault encrypt host_vars/firth.water.gkhs.net/laravel/<appname>.vault.yml
```

---

## 3. Add the app to laravel_apps.yml

In `host_vars/firth.water.gkhs.net/laravel_apps.yml`, add an entry to `firth_laravel_app_apps`:

```yaml
- name: myapp                              # unique; becomes system user, container name, working dir
  image: ghcr.io/myorg/myapp
  image_tag: latest
  backend: fpm                             # fpm (PHP-FPM on port 9000) or octane (HTTP on port 8000)
  port: 9005                               # host-side port; must be unique across all apps
  server_name: myapp.example.com
  app_url: https://myapp.example.com
  app_key: "{{ vault_myapp_app_key }}"
  app_name: My App
  ssl_snippet: example                     # matches roles/firth_nginx/templates/snippets/<name>
  github_repo: myorg/myapp
  github_deploy_token: "{{ laravel_apps_deploy_token_myorg }}"
  ghcr_username: "{{ ghcr_username }}"
  ghcr_token: "{{ ghcr_token }}"
  mysql:
    db_name: myapp
    db_user: myapp
    db_password: "{{ vault_myapp_db_password }}"
  redis:                                   # optional
    username: myapp
    password: "{{ vault_myapp_redis_password }}"
  mail:                                    # optional; uses shared SMTP credentials
    host: "{{ laravel_apps_mail_host }}"
    port: "{{ laravel_apps_mail_port }}"
    username: "{{ laravel_apps_mail_username }}"
    password: "{{ laravel_apps_mail_password }}"
    from_address: "{{ laravel_apps_mail_from_address }}"
    from_name: "My App Support"
  additional_env:                          # optional; arbitrary env vars passed to the container
    MY_API_KEY: "{{ vault_myapp_api_key }}"
  additional_files:                        # optional; files copied into container at storage/app/<dest>
    - src: files/laravel/myapp/secret.vault.json
      dest: secret.json
```

### Choosing a port

Ports currently in use:

| App         | Port (prod) | Port (staging) |
|-------------|-------------|----------------|
| alchemistic | 9000        | —              |
| novelathon  | 9001        | 9002           |
| sprouter    | 8000        | 8001           |
| docket      | 9003        | 9004           |
| wereabouts  | 9005        | 9006           |

Pick the next available port. FPM apps use 9xxx; octane apps use 8xxx by convention.

### Optional: staging environment

Add a `staging:` block to the app entry to get a second deployment at a separate domain:

```yaml
  staging:
    image_tag: staging
    port: 9006                             # must also be unique
    server_name: myapp.istic.dev
    app_url: https://myapp.istic.dev
    app_key: "{{ vault_myapp_staging_app_key }}"
    ssl_snippet: istic_dev
    mysql:
      db_name: myapp_staging
      db_user: myapp_staging
      db_password: "{{ vault_myapp_staging_db_password }}"
    redis:                                 # if prod has redis, staging needs it too
      username: myapp_staging
      password: "{{ vault_myapp_staging_redis_password }}"
    additional_env:                        # replaces prod additional_env entirely — repeat any keys you need
      MY_API_KEY: "{{ vault_myapp_staging_api_key }}"
```

Staging inherits `mail`, `worker`, `workdir`, `ssl_snippet`, `www_redirect`, `additional_files`, and `additional_env` from the prod entry unless overridden. Note that `additional_env` is replaced entirely if provided — it is not merged with the prod value.

### Optional: additional files

For files that need to be present inside the container (e.g. service account credentials):

1. Place the file under `files/laravel/<appname>/` in the repo
2. If it contains secrets, encrypt it: `ansible-vault encrypt files/laravel/<appname>/secret.vault.json`
3. Add it to `.pre-commit-config.yaml` exclusions (see docket as an example for `.vault.json`)
4. Reference it in `additional_files:` — it will be copied to `<docker_root>/<appname>/secrets/<dest>` and bind-mounted into the container at `<workdir>/storage/app/<dest>` (read-only)

---

## 4. Bootstrap the infrastructure

The first deploy of a new app is a two-step process because the image may not exist yet when Ansible first runs.

### Step 1: provision without deploying the container

```bash
ansible-playbook playbook.yml -l firth --tags firth_laravel_app --skip-tags laravel_apps_deploy
```

This creates:
- System user `myapp` in the `docker` group
- SSH deploy keypair, uploaded as `FIRTH_SSH_KEY` to the GitHub repo's Actions secrets
- MySQL database and user
- Redis ACL user (if configured)
- nginx vhost at `/etc/nginx/sites-enabled/myapp.example.com.conf`
- Working directory at `{{ docker_root }}/myapp/`

### Step 2: build and push the initial image

Trigger your CI pipeline, or build and push manually:

```bash
docker build -t ghcr.io/myorg/myapp:latest .
docker push ghcr.io/myorg/myapp:latest
```

For staging, push a `staging` tag too if you have a staging block.

### Step 3: deploy the container

```bash
ansible-playbook playbook.yml -l firth --tags firth_laravel_app
```

This pulls the image, starts the container, waits for it to be running, copies Vite build assets from the container, then runs database migrations.

---

## 5. Subsequent deploys

After the initial bootstrap, deployments happen automatically via GitHub Actions using the `FIRTH_SSH_KEY` secret that was uploaded in step 1. The deploy workflow SSHes into firth as the app's system user and runs `docker compose pull && docker compose up -d`.

Running the playbook again is idempotent — it will only restart the container if the compose file changed.

---

## 6. Verify

```bash
# Check the container is running
ssh firth.water.gkhs.net 'docker ps | grep myapp'

# Check the nginx vhost is active
ssh firth.water.gkhs.net 'nginx -T 2>/dev/null | grep myapp.example.com'

# Hit the app through nginx
curl -sk https://myapp.example.com -o /dev/null -w '%{http_code}'
```
