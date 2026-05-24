# firth_laravel_app Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `firth_novelathon` and `firth_alchemistic` with a single parametric `firth_laravel_app` role that deploys all Dockerised Laravel apps on firth from a list in host_vars, and add Sprouter (`social.istic.net`) as the first new app using that role.

**Architecture:** A `firth_laravel_apps` list in `host_vars/firth.water.gkhs.net/laravel_apps.yml` defines each app. `tasks/main.yml` loops over the list (loop_var `firth_laravel_app_item`). `tasks/app.yml` sets a `fla` fact (raw app dict) and a `fla_ctx` fact (normalised rendering context), then delegates to focused sub-task files. The same `deploy.yml` and `nginx.yml` task files serve both production and staging — staging.yml just rebuilds `fla_ctx` before calling them.

**Tech Stack:** Ansible, community.docker, community.crypto, ansible.posix, ansible.mysql, Jinja2 templates, GitHub API (deploy key upload), GHCR

---

## Context for implementers

- Working directory: `/home/aquarion/code/aquarion/autopelago`
- Branch: `feature/firth-laravel-app` (already created)
- Spec: `docs/superpowers/specs/2026-05-24-firth-laravel-app-design.md`
- Existing roles to study: `roles/firth_novelathon/`, `roles/firth_alchemistic/`
- Global handlers (`Reload Nginx`, `Reload Redis ACL`) are defined in `roles/global_things/handlers/main.yml` and imported by the firth play in `playbook.yml` — do **not** redefine them in this role
- `docker_root`, `firth_services_docker_network`, `mysql_root_password` are defined in encrypted host_vars/group_vars — the role consumes them but does not define them
- `encrypt_secret` is a custom filter plugin in `filter_plugins/filters.py` — used for GitHub secret upload
- SSL snippet `istic_ssl.conf` already exists at `roles/firth_nginx/templates/ssl/istic_ssl.conf` and covers `*.istic.net` — no changes to `firth_nginx` needed for `social.istic.net`
- Run `ansible-lint roles/firth_laravel_app/` after each task to catch issues early
- ansible-lint `loop-var-prefix` rule: loop variables must start with the role name; use `firth_laravel_app_item` as the loop_var name

---

## File map

**Create:**
```
roles/firth_laravel_app/
  meta/main.yml
  defaults/main.yml
  handlers/main.yml
  tasks/main.yml
  tasks/app.yml
  tasks/system_user.yml
  tasks/mysql.yml
  tasks/redis.yml
  tasks/ghcr.yml
  tasks/deploy.yml
  tasks/nginx.yml
  tasks/staging.yml
  templates/docker-compose.yml.j2
  templates/vhosts/app.conf.j2
host_vars/firth.water.gkhs.net/laravel_apps.yml
host_vars/firth.water.gkhs.net/laravel_apps.vault.yml   (vault-encrypted)
```

**Modify:**
```
playbook.yml   — add firth_laravel_app; later remove firth_novelathon + firth_alchemistic
```

**Delete (Phase 2):**
```
roles/firth_novelathon/
roles/firth_alchemistic/
host_vars/firth.water.gkhs.net/novelathon.yml
host_vars/firth.water.gkhs.net/alchemistic.yml
```

---

## Task 1: Role scaffold

**Files:**
- Create: `roles/firth_laravel_app/meta/main.yml`
- Create: `roles/firth_laravel_app/defaults/main.yml`
- Create: `roles/firth_laravel_app/handlers/main.yml`

- [ ] **Create the role directory structure**

```bash
mkdir -p roles/firth_laravel_app/{meta,defaults,handlers,tasks,templates/vhosts}
```

- [ ] **Write `roles/firth_laravel_app/meta/main.yml`**

```yaml
---
galaxy_info:
  author: Nicholas Avenell
  description: Parametric role to deploy Dockerised Laravel apps on firth.
  company: Istic Co. <https://istic.co>
  license: GPL-2.0-or-later
  min_ansible_version: "2.1"
  galaxy_tags:
    - docker
    - laravel

dependencies: []
```

- [ ] **Write `roles/firth_laravel_app/defaults/main.yml`**

```yaml
---
# List of apps to deploy — define in host_vars/firth.water.gkhs.net/laravel_apps.yml
firth_laravel_apps: []

# MySQL login credentials for provisioning databases (set in host vault)
firth_laravel_app_mysql_login_host: 127.0.0.1
firth_laravel_app_mysql_login_user: root
```

- [ ] **Write `roles/firth_laravel_app/handlers/main.yml`**

```yaml
---
# Global handlers (Reload Nginx, Reload Redis ACL) are defined in
# roles/global_things/handlers/main.yml and imported by the firth play.
```

- [ ] **Run ansible-lint to confirm the skeleton is valid**

```bash
ansible-lint roles/firth_laravel_app/
```

Expected: no errors (empty tasks dir will warn; create a stub `tasks/main.yml` with `---` if needed)

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/
git commit -m "⚙️ Add firth_laravel_app role scaffold"
```

---

## Task 2: docker-compose.yml.j2 template

**Files:**
- Create: `roles/firth_laravel_app/templates/docker-compose.yml.j2`

The template uses a `fla_ctx` dict (set in `tasks/app.yml` and `tasks/staging.yml`). Key fields: `name`, `image`, `image_tag`, `backend` (fpm|octane), `port`, `app_name`, `app_env`, `app_debug`, `app_key`, `app_url`, `mysql` (optional dict), `redis` (optional dict), `mail`, `worker` (bool).

Inner container port is `9000` for fpm, `8000` for octane. The `worker` service uses a YAML anchor (`&app-env`) on the environment block to avoid repetition. Staging sets `APP_ENV: staging` and `APP_DEBUG: "true"` via `fla_ctx.app_env` / `fla_ctx.app_debug`.

- [ ] **Write `roles/firth_laravel_app/templates/docker-compose.yml.j2`**

```jinja2
# {{ ansible_managed }}
name: {{ fla_ctx.name }}
services:
  app:
    image: "{{ fla_ctx.image }}:{{ fla_ctx.image_tag }}"
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{ fla_ctx.port }}:{% if fla_ctx.backend == 'fpm' %}9000{% else %}8000{% endif %}"
    environment: &app-env
      APP_NAME: "{{ fla_ctx.app_name }}"
      APP_ENV: "{{ fla_ctx.app_env }}"
      APP_KEY: "{{ fla_ctx.app_key }}"
      APP_DEBUG: "{{ fla_ctx.app_debug }}"
      APP_URL: "{{ fla_ctx.app_url }}"
      LOG_STACK: "stderr,single"
{% if fla_ctx.mysql %}
      DB_CONNECTION: mysql
      DB_HOST: "{{ fla_ctx.mysql.db_host | default('host.docker.internal') }}"
      DB_PORT: "{{ fla_ctx.mysql.db_port | default(3306) }}"
      DB_DATABASE: "{{ fla_ctx.mysql.db_name }}"
      DB_USERNAME: "{{ fla_ctx.mysql.db_user }}"
      DB_PASSWORD: "{{ fla_ctx.mysql.db_password }}"
{% endif %}
{% if fla_ctx.redis %}
      REDIS_HOST: "{{ fla_ctx.redis.host | default('host.docker.internal') }}"
      REDIS_PORT: "{{ fla_ctx.redis.port | default(6379) }}"
      REDIS_USERNAME: "{{ fla_ctx.redis.username }}"
      REDIS_PASSWORD: "{{ fla_ctx.redis.password }}"
{% endif %}
{% if fla_ctx.mail %}
      MAIL_MAILER: smtp
      MAIL_HOST: "{{ fla_ctx.mail.host }}"
      MAIL_PORT: "{{ fla_ctx.mail.port | default(587) }}"
      MAIL_USERNAME: "{{ fla_ctx.mail.username }}"
      MAIL_PASSWORD: "{{ fla_ctx.mail.password }}"
      MAIL_FROM_ADDRESS: "{{ fla_ctx.mail.from_address }}"
      MAIL_FROM_NAME: "{{ fla_ctx.mail.from_name }}"
{% endif %}
    volumes:
      - {{ fla_ctx.name }}_storage:/var/www/html/storage
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - firth_services
    logging:
      driver: journald
      options:
        tag: "$${.Name}/$${.ID}"

{% if fla_ctx.worker %}
  worker:
    image: "{{ fla_ctx.image }}:{{ fla_ctx.image_tag }}"
    restart: unless-stopped
    command: ["php", "artisan", "queue:work"]
    environment: *app-env
    volumes:
      - {{ fla_ctx.name }}_storage:/var/www/html/storage
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - firth_services
    logging:
      driver: journald
      options:
        tag: "$${.Name}/$${.ID}"

{% endif %}
volumes:
  {{ fla_ctx.name }}_storage:

networks:
  firth_services:
    external: true
    name: "{{ firth_services_docker_network }}"
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/templates/docker-compose.yml.j2
git commit -m "⚙️ Add firth_laravel_app docker-compose template"
```

---

## Task 3: vhosts/app.conf.j2 template

**Files:**
- Create: `roles/firth_laravel_app/templates/vhosts/app.conf.j2`

Template uses `fla_ctx` fields: `server_name`, `name` (for log files and asset paths), `backend`, `port`, `ssl_snippet`, `www_redirect`. The `ssl_snippet` value is the filename stem (e.g. `istic` → includes `ssl/istic_ssl.conf`).

- [ ] **Write `roles/firth_laravel_app/templates/vhosts/app.conf.j2`**

```jinja2
# {{ ansible_managed }}
server {
    listen 80;
    listen [::]:80;
    server_name {{ fla_ctx.server_name }}{% if fla_ctx.www_redirect %} www.{{ fla_ctx.server_name }}{% endif %};
    return 301 https://{{ fla_ctx.server_name }}$request_uri;
}

{% if fla_ctx.www_redirect %}
server {
    listen 443 ssl proxy_protocol;
    listen [::]:443 ssl proxy_protocol;
    server_name www.{{ fla_ctx.server_name }};

    include /etc/nginx/snippets/ssl/{{ fla_ctx.ssl_snippet }}_ssl.conf;

    return 301 https://{{ fla_ctx.server_name }}$request_uri;
}

{% endif %}
server {
    listen 443 ssl proxy_protocol;
    listen [::]:443 ssl proxy_protocol;
    server_name {{ fla_ctx.server_name }};

    include /etc/nginx/snippets/errors.conf;
    include /etc/nginx/snippets/ssl/{{ fla_ctx.ssl_snippet }}_ssl.conf;

    error_log  /var/log/nginx/{{ fla_ctx.name }}.error.log;
    access_log /var/log/nginx/{{ fla_ctx.name }}.access.log;

    add_header X-WhyAmI {{ fla_ctx.name }};

    location /build/ {
        alias {{ docker_root }}/{{ fla_ctx.name }}/public/build/;
        expires max;
        add_header Cache-Control "public, immutable";
    }

    location / {
{% if fla_ctx.backend == 'fpm' %}
        fastcgi_pass 127.0.0.1:{{ fla_ctx.port }};
        fastcgi_param SCRIPT_FILENAME /var/www/html/public/index.php;
        fastcgi_param QUERY_STRING $query_string;
        include fastcgi_params;
{% else %}
        proxy_pass http://127.0.0.1:{{ fla_ctx.port }};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
{% endif %}
    }
}
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/templates/vhosts/app.conf.j2
git commit -m "⚙️ Add firth_laravel_app nginx vhost template"
```

---

## Task 4: tasks/system_user.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/system_user.yml`

Uses `fla` (raw app dict). Creates the system user, SSH deploy keypair, authorises keys, uploads the private key as `FIRTH_SSH_KEY` to the GitHub repo's Actions secrets, and creates host working directories.

- [ ] **Write `roles/firth_laravel_app/tasks/system_user.yml`**

```yaml
---
- name: Create {{ fla.name }} system user
  tags: "{{ fla.name }}"
  block:
    - name: Ensure {{ fla.name }} system user exists
      ansible.builtin.user:
        name: "{{ fla.name }}"
        system: true
        home: "/var/lib/{{ fla.name }}"
        create_home: true
        shell: /bin/bash
        groups: docker
        append: true
        state: present

    - name: Ensure {{ fla.name }} .ssh directory exists
      ansible.builtin.file:
        path: "/var/lib/{{ fla.name }}/.ssh"
        state: directory
        owner: "{{ fla.name }}"
        group: "{{ fla.name }}"
        mode: "0700"

    - name: Generate SSH deploy keypair for {{ fla.name }}
      community.crypto.openssh_keypair:
        path: "/var/lib/{{ fla.name }}/.ssh/id_ed25519"
        type: ed25519
        comment: "{{ fla.name }}-deploy@firth"
        owner: "{{ fla.name }}"
        group: "{{ fla.name }}"
        mode: "0600"
        force: false
      register: firth_laravel_app_deploy_keypair

    - name: Authorise deploy key for {{ fla.name }}
      ansible.posix.authorized_key:
        user: "{{ fla.name }}"
        key: "{{ firth_laravel_app_deploy_keypair.public_key }}"
        state: present

    - name: Authorise aquarion SSH keys for {{ fla.name }}
      ansible.posix.authorized_key:
        user: "{{ fla.name }}"
        key: "{{ lookup('file', playbook_dir + '/files/aquarion.keys') }}"
        state: present

    - name: Slurp {{ fla.name }} deploy private key
      ansible.builtin.slurp:
        src: "/var/lib/{{ fla.name }}/.ssh/id_ed25519"
      register: firth_laravel_app_deploy_privkey
      no_log: true

    - name: Get GitHub public key for {{ fla.name }} repository
      ansible.builtin.uri:
        url: "https://api.github.com/repos/{{ fla.github_repo }}/actions/secrets/public-key"
        method: GET
        headers:
          Accept: "application/vnd.github.v3+json"
          Authorization: "Bearer {{ fla.github_deploy_token }}"
          X-GitHub-Api-Version: "2022-11-28"
        return_content: true
      register: firth_laravel_app_github_pubkey
      delegate_to: localhost
      become: false
      changed_when: false
      no_log: true

    - name: Upload {{ fla.name }} deploy key to GitHub Actions secrets
      ansible.builtin.uri:
        url: "https://api.github.com/repos/{{ fla.github_repo }}/actions/secrets/FIRTH_SSH_KEY"
        method: PUT
        headers:
          Authorization: "Bearer {{ fla.github_deploy_token }}"
          Accept: "application/vnd.github.v3+json"
          X-GitHub-Api-Version: "2022-11-28"
        body:
          encrypted_value: "{{ firth_laravel_app_deploy_privkey.content | b64decode | encrypt_secret(firth_laravel_app_github_pubkey.json.key) }}"
          key_id: "{{ firth_laravel_app_github_pubkey.json.key_id }}"
        body_format: json
        status_code: [200, 201, 204]
      register: firth_laravel_app_github_secret_response
      delegate_to: localhost
      become: false
      changed_when: firth_laravel_app_github_secret_response.status == 201
      no_log: true

    - name: Create {{ fla.name }} working directory
      ansible.builtin.file:
        path: "{{ docker_root }}/{{ fla.name }}"
        state: directory
        owner: root
        group: root
        mode: "0755"

    - name: Create {{ fla.name }} public asset directory
      ansible.builtin.file:
        path: "{{ docker_root }}/{{ fla.name }}/public"
        state: directory
        owner: "{{ fla.name }}"
        group: "{{ fla.name }}"
        mode: "0755"

  rescue:
    - name: Debug {{ fla.name }} system user failure
      ansible.builtin.debug:
        msg: "Failed to set up system user for {{ fla.name }}. Check docker group exists and GitHub token has secrets:write scope."

    - name: Abort after {{ fla.name }} system user failure
      ansible.builtin.fail:
        msg: "Cannot continue: system user setup for {{ fla.name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/system_user.yml
```

Expected: no errors

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/system_user.yml
git commit -m "⚙️ Add firth_laravel_app system_user tasks"
```

---

## Task 5: tasks/mysql.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/mysql.yml`

Uses `fla_ctx.mysql` (dict with `db_name`, `db_user`, `db_password`). Only called when `fla_ctx.mysql` is non-empty. Uses `firth_laravel_app_mysql_login_host`, `firth_laravel_app_mysql_login_user` (from defaults), and `mysql_root_password` (from host vault).

- [ ] **Write `roles/firth_laravel_app/tasks/mysql.yml`**

```yaml
---
- name: Provision {{ fla_ctx.name }} database
  tags: "{{ fla_ctx.name }}"
  block:
    - name: Ensure python3-mysqldb is installed
      ansible.builtin.apt:
        name: python3-mysqldb
        state: present

    - name: Create {{ fla_ctx.name }} database
      community.mysql.mysql_db:
        name: "{{ fla_ctx.mysql.db_name }}"
        state: present
        login_host: "{{ firth_laravel_app_mysql_login_host }}"
        login_user: "{{ firth_laravel_app_mysql_login_user }}"
        login_password: "{{ mysql_root_password }}"

    - name: Create {{ fla_ctx.name }} database user
      community.mysql.mysql_user:
        name: "{{ fla_ctx.mysql.db_user }}"
        password: "{{ fla_ctx.mysql.db_password }}"
        priv: "{{ fla_ctx.mysql.db_name }}.*:ALL"
        host: "%"
        state: present
        login_host: "{{ firth_laravel_app_mysql_login_host }}"
        login_user: "{{ firth_laravel_app_mysql_login_user }}"
        login_password: "{{ mysql_root_password }}"
        column_case_sensitive: true

  rescue:
    - name: Debug {{ fla_ctx.name }} database failure
      ansible.builtin.debug:
        msg: "Failed to provision database for {{ fla_ctx.name }}. Check mysql_root_password and MySQL connectivity."

    - name: Abort after {{ fla_ctx.name }} database failure
      ansible.builtin.fail:
        msg: "Cannot continue: database setup for {{ fla_ctx.name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/mysql.yml
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/mysql.yml
git commit -m "⚙️ Add firth_laravel_app mysql tasks"
```

---

## Task 6: tasks/redis.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/redis.yml`

Uses `fla_ctx.redis` (dict with `username`, `password`). Only called when `fla_ctx.redis` is non-empty. Notifies the global `Reload Redis ACL` handler (defined in `roles/global_things/handlers/main.yml`).

- [ ] **Write `roles/firth_laravel_app/tasks/redis.yml`**

```yaml
---
- name: Configure Redis ACL user for {{ fla_ctx.name }}
  ansible.builtin.lineinfile:
    path: /etc/redis/users.acl
    line: "user {{ fla_ctx.redis.username }} on +@all -DEBUG ~* >{{ fla_ctx.redis.password }}"
    regexp: "^user {{ fla_ctx.redis.username | regex_escape }} "
  notify: Reload Redis ACL
  tags: "{{ fla_ctx.name }}"
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/redis.yml
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/redis.yml
git commit -m "⚙️ Add firth_laravel_app redis tasks"
```

---

## Task 7: tasks/ghcr.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/ghcr.yml`

Uses `fla` (raw app dict). Resolves GHCR credentials, validates they exist, then logs in as the app's system user. Only called when `fla.image` starts with `ghcr.io/`.

- [ ] **Write `roles/firth_laravel_app/tasks/ghcr.yml`**

```yaml
---
- name: Authenticate to GHCR for {{ fla.name }}
  tags: "{{ fla.name }}"
  block:
    - name: Resolve GHCR credentials for {{ fla.name }}
      ansible.builtin.set_fact:
        firth_laravel_app_ghcr_username_resolved: "{{ fla.ghcr_username | default(ghcr_username | default(''), true) }}"
        firth_laravel_app_ghcr_token_resolved: "{{ fla.ghcr_token | default(ghcr_token | default(''), true) }}"
      changed_when: false
      no_log: true

    - name: Validate GHCR credentials for {{ fla.name }}
      ansible.builtin.assert:
        that:
          - firth_laravel_app_ghcr_username_resolved | length > 0
          - firth_laravel_app_ghcr_token_resolved | length > 0
        fail_msg: >-
          Missing GHCR credentials for {{ fla.name }} image {{ fla.image }}.
          Set fla.ghcr_username/fla.ghcr_token or legacy ghcr_username/ghcr_token.
      no_log: true

    - name: Authenticate to GHCR as {{ fla.name }}
      community.docker.docker_login:
        registry_url: ghcr.io
        username: "{{ firth_laravel_app_ghcr_username_resolved }}"
        password: "{{ firth_laravel_app_ghcr_token_resolved }}"
      become: true
      become_user: "{{ fla.name }}"
      no_log: true

  rescue:
    - name: Debug {{ fla.name }} GHCR auth failure
      ansible.builtin.debug:
        msg: "Failed to authenticate {{ fla.name }} to GHCR. Check ghcr_username/ghcr_token have read:packages scope."

    - name: Abort after {{ fla.name }} GHCR auth failure
      ansible.builtin.fail:
        msg: "Cannot continue: GHCR authentication for {{ fla.name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/ghcr.yml
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/ghcr.yml
git commit -m "⚙️ Add firth_laravel_app ghcr tasks"
```

---

## Task 8: tasks/deploy.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/deploy.yml`

Uses `fla_ctx`. Renders the docker-compose template, pulls the image, copies Vite assets (only if compose changed), and runs migrations (only if compose changed). `become_user` is `fla_ctx.system_user` (the app's system user).

- [ ] **Write `roles/firth_laravel_app/tasks/deploy.yml`**

```yaml
---
- name: Deploy {{ fla_ctx.name }}
  tags: "{{ fla_ctx.name }}"
  block:
    - name: Template docker-compose.yml for {{ fla_ctx.name }}
      ansible.builtin.template:
        src: docker-compose.yml.j2
        dest: "{{ docker_root }}/{{ fla_ctx.name }}/docker-compose.yml"
        owner: root
        group: docker
        mode: "0660"

    - name: Pull and start {{ fla_ctx.name }}
      community.docker.docker_compose_v2:
        project_src: "{{ docker_root }}/{{ fla_ctx.name }}"
        pull: always
        state: present
      become: true
      become_user: "{{ fla_ctx.system_user }}"
      register: firth_laravel_app_compose

    - name: Remove stale {{ fla_ctx.name }} build assets
      ansible.builtin.file:
        path: "{{ docker_root }}/{{ fla_ctx.name }}/public/build"
        state: absent
      become: true
      become_user: "{{ fla_ctx.system_user }}"
      when: firth_laravel_app_compose.changed

    - name: Copy Vite build assets from {{ fla_ctx.name }} container
      ansible.builtin.command: docker compose cp app:/var/www/html/public/build public/build
      args:
        chdir: "{{ docker_root }}/{{ fla_ctx.name }}"
      become: true
      become_user: "{{ fla_ctx.system_user }}"
      when: firth_laravel_app_compose.changed
      changed_when: firth_laravel_app_compose.changed

    - name: Run migrations for {{ fla_ctx.name }}
      ansible.builtin.command: docker compose exec -T app php artisan migrate --force
      args:
        chdir: "{{ docker_root }}/{{ fla_ctx.name }}"
      become: true
      become_user: "{{ fla_ctx.system_user }}"
      when: firth_laravel_app_compose.changed
      register: firth_laravel_app_migrate
      changed_when: "'migrated' in firth_laravel_app_migrate.stdout"

  rescue:
    - name: Debug {{ fla_ctx.name }} deploy failure
      ansible.builtin.debug:
        msg: "Failed to deploy {{ fla_ctx.name }}. Check docker-compose.yml and image availability."

    - name: Abort after {{ fla_ctx.name }} deploy failure
      ansible.builtin.fail:
        msg: "Cannot continue: deploy of {{ fla_ctx.name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/deploy.yml
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/deploy.yml
git commit -m "⚙️ Add firth_laravel_app deploy tasks"
```

---

## Task 9: tasks/nginx.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/nginx.yml`

Uses `fla_ctx`. Renders the vhost template and enables it. Notifies the global `Reload Nginx` handler.

- [ ] **Write `roles/firth_laravel_app/tasks/nginx.yml`**

```yaml
---
- name: Deploy nginx vhost for {{ fla_ctx.name }}
  tags: "{{ fla_ctx.name }}"
  block:
    - name: Template nginx vhost for {{ fla_ctx.server_name }}
      ansible.builtin.template:
        src: vhosts/app.conf.j2
        dest: "/etc/nginx/sites-available/{{ fla_ctx.server_name }}.conf"
        owner: root
        group: root
        mode: "0644"
      notify: Reload Nginx

    - name: Enable nginx vhost for {{ fla_ctx.server_name }}
      ansible.builtin.file:
        path: "/etc/nginx/sites-enabled/{{ fla_ctx.server_name }}.conf"
        src: "../sites-available/{{ fla_ctx.server_name }}.conf"
        state: link
      notify: Reload Nginx

  rescue:
    - name: Debug {{ fla_ctx.name }} nginx failure
      ansible.builtin.debug:
        msg: "Failed to deploy nginx vhost for {{ fla_ctx.server_name }}."

    - name: Abort after {{ fla_ctx.name }} nginx failure
      ansible.builtin.fail:
        msg: "Cannot continue: nginx vhost for {{ fla_ctx.server_name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/nginx.yml
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/nginx.yml
git commit -m "⚙️ Add firth_laravel_app nginx tasks"
```

---

## Task 10: tasks/staging.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/staging.yml`

Uses `fla` (for inherited values) and `fla.staging` (for overrides). Builds a `fla_ctx` for the staging environment, creates staging directories, calls `mysql.yml` and `redis.yml` with the staging context, then calls `deploy.yml` and `nginx.yml`. This is the last step in `app.yml` so overwriting `fla_ctx` is safe.

`staging.yml` being included last means `fla_ctx` correctly reflects staging values when the nested includes run.

- [ ] **Write `roles/firth_laravel_app/tasks/staging.yml`**

```yaml
---
- name: Create {{ fla.name }}-staging working directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop:
    - "{{ docker_root }}/{{ fla.name }}-staging"
    - "{{ docker_root }}/{{ fla.name }}-staging/public"
  tags: "{{ fla.name }}"

- name: Set {{ fla.name }} staging context
  ansible.builtin.set_fact:
    fla_ctx:
      name: "{{ fla.name }}-staging"
      image: "{{ fla.image }}"
      image_tag: "{{ fla.staging.image_tag | default('staging') }}"
      backend: "{{ fla.backend }}"
      port: "{{ fla.staging.port }}"
      app_name: "{{ fla.app_name | default(fla.name | capitalize) }} Staging"
      app_env: staging
      app_debug: "true"
      app_key: "{{ fla.staging.app_key }}"
      app_url: "{{ fla.staging.app_url }}"
      server_name: "{{ fla.staging.server_name }}"
      ssl_snippet: "{{ fla.staging.ssl_snippet | default(fla.ssl_snippet) }}"
      www_redirect: "{{ fla.staging.www_redirect | default(false) }}"
      worker: "{{ fla.staging.worker | default(fla.worker | default(false)) }}"
      mysql: "{{ fla.staging.mysql | default({}) }}"
      redis: "{{ fla.staging.redis | default({}) }}"
      mail: "{{ fla.mail | default({}) }}"
      system_user: "{{ fla.name }}"
  tags: "{{ fla.name }}"

- name: Provision {{ fla.name }} staging database
  ansible.builtin.include_tasks: mysql.yml
  when: fla_ctx.mysql | length > 0
  tags: "{{ fla.name }}"

- name: Configure {{ fla.name }} staging Redis user
  ansible.builtin.include_tasks: redis.yml
  when: fla_ctx.redis | length > 0
  tags: "{{ fla.name }}"

- name: Deploy {{ fla.name }} staging application
  ansible.builtin.include_tasks: deploy.yml
  tags: "{{ fla.name }}"

- name: Deploy {{ fla.name }} staging nginx vhost
  ansible.builtin.include_tasks: nginx.yml
  tags: "{{ fla.name }}"
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app/tasks/staging.yml
```

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/staging.yml
git commit -m "⚙️ Add firth_laravel_app staging tasks"
```

---

## Task 11: tasks/app.yml and tasks/main.yml

**Files:**
- Create: `roles/firth_laravel_app/tasks/app.yml`
- Create: `roles/firth_laravel_app/tasks/main.yml`

`app.yml` is the per-app orchestrator. It sets `fla` (raw dict) and `fla_ctx` (production rendering context), then calls sub-task files in order. `main.yml` loops over `firth_laravel_apps` and calls `app.yml` for each entry.

- [ ] **Write `roles/firth_laravel_app/tasks/app.yml`**

```yaml
---
- name: Set {{ firth_laravel_app_item.name }} context
  ansible.builtin.set_fact:
    fla: "{{ firth_laravel_app_item }}"
    fla_ctx:
      name: "{{ firth_laravel_app_item.name }}"
      image: "{{ firth_laravel_app_item.image }}"
      image_tag: "{{ firth_laravel_app_item.image_tag | default('latest') }}"
      backend: "{{ firth_laravel_app_item.backend }}"
      port: "{{ firth_laravel_app_item.port }}"
      app_name: "{{ firth_laravel_app_item.app_name | default(firth_laravel_app_item.name | capitalize) }}"
      app_env: production
      app_debug: "false"
      app_key: "{{ firth_laravel_app_item.app_key }}"
      app_url: "{{ firth_laravel_app_item.app_url }}"
      server_name: "{{ firth_laravel_app_item.server_name }}"
      ssl_snippet: "{{ firth_laravel_app_item.ssl_snippet }}"
      www_redirect: "{{ firth_laravel_app_item.www_redirect | default(false) }}"
      worker: "{{ firth_laravel_app_item.worker | default(false) }}"
      mysql: "{{ firth_laravel_app_item.mysql | default({}) }}"
      redis: "{{ firth_laravel_app_item.redis | default({}) }}"
      mail: "{{ firth_laravel_app_item.mail | default({}) }}"
      system_user: "{{ firth_laravel_app_item.name }}"
  tags: always

- name: Setup system user for {{ fla.name }}
  ansible.builtin.include_tasks: system_user.yml

- name: Provision {{ fla.name }} database
  ansible.builtin.include_tasks: mysql.yml
  when: fla_ctx.mysql | length > 0

- name: Configure {{ fla.name }} Redis user
  ansible.builtin.include_tasks: redis.yml
  when: fla_ctx.redis | length > 0

- name: Authenticate to GHCR for {{ fla.name }}
  ansible.builtin.include_tasks: ghcr.yml
  when: fla.image is match('^ghcr\\.io/.+')

- name: Ensure shared Docker network exists
  community.docker.docker_network:
    name: "{{ firth_services_docker_network }}"
    state: present

- name: Deploy {{ fla.name }}
  ansible.builtin.include_tasks: deploy.yml

- name: Deploy {{ fla.name }} nginx vhost
  ansible.builtin.include_tasks: nginx.yml

- name: Deploy {{ fla.name }} staging
  ansible.builtin.include_tasks: staging.yml
  when: fla.staging is defined
```

- [ ] **Write `roles/firth_laravel_app/tasks/main.yml`**

```yaml
---
- name: Configure Laravel applications
  ansible.builtin.include_tasks: app.yml
  loop: "{{ firth_laravel_apps }}"
  loop_control:
    loop_var: firth_laravel_app_item
    label: "{{ firth_laravel_app_item.name }}"
```

- [ ] **Run ansible-lint on the full role**

```bash
ansible-lint roles/firth_laravel_app/
```

Expected: no errors

- [ ] **Commit**

```bash
git add roles/firth_laravel_app/tasks/app.yml roles/firth_laravel_app/tasks/main.yml
git commit -m "⚙️ Add firth_laravel_app orchestrator tasks"
```

---

## Task 12: host_vars — laravel_apps.yml

**Files:**
- Create: `host_vars/firth.water.gkhs.net/laravel_apps.yml`

This file is **not vault-encrypted** — it contains only variable references to vault vars. Actual secret values live in the vault files created in Task 13. References to existing novelathon/alchemistic vault vars use the names already defined in `novelathon.yml` and `alchemistic.yml` (those files are kept until Phase 2).

The `ssl_snippet` values:
- `novelathon.com` → `novelathon.com` (cert managed by firth_nginx SSL Config loop)
- `novelathon.istic.dev` staging → `istic_dev`
- `manage.istic.systems` (alchemistic) → `istic`
- `social.istic.net` (sprouter) → `istic`

Alchemistic's current FPM port is 9000 — keep it. Novelathon production is 9001, staging 9002. Sprouter is 8000 (Octane). Pick a free port for future apps starting from 9003.

- [ ] **Write `host_vars/firth.water.gkhs.net/laravel_apps.yml`**

```yaml
---
firth_laravel_apps:
  - name: alchemistic
    image: ghcr.io/istic/alchemistic
    image_tag: latest
    backend: fpm
    port: 9000
    server_name: manage.istic.systems
    app_url: https://manage.istic.systems
    app_key: "{{ firth_alchemistic_app_key }}"
    app_name: Alchemistic
    ssl_snippet: istic
    github_repo: istic/alchemistic
    github_deploy_token: "{{ firth_alchemistic_github_deploy_token }}"
    ghcr_username: "{{ ghcr_username }}"
    ghcr_token: "{{ ghcr_token }}"
    mysql:
      db_name: "{{ firth_alchemistic_db_name }}"
      db_user: "{{ firth_alchemistic_db_user }}"
      db_password: "{{ firth_alchemistic_db_password }}"
    mail:
      host: "{{ firth_alchemistic_mail_host }}"
      port: "{{ firth_alchemistic_mail_port }}"
      username: "{{ firth_alchemistic_mail_username }}"
      password: "{{ firth_alchemistic_mail_password }}"
      from_address: "{{ firth_alchemistic_mail_from_address }}"
      from_name: "{{ firth_alchemistic_mail_from_name }}"

  - name: novelathon
    image: ghcr.io/istic/novelathon
    image_tag: latest
    backend: fpm
    port: 9001
    server_name: novelathon.com
    app_url: https://novelathon.com
    app_key: "{{ firth_novelathon_app_key }}"
    app_name: Novelathon
    ssl_snippet: novelathon.com
    www_redirect: true
    github_repo: istic/novelathon
    github_deploy_token: "{{ firth_novelathon_github_deploy_token }}"
    ghcr_username: "{{ ghcr_username }}"
    ghcr_token: "{{ ghcr_token }}"
    worker: true
    mysql:
      db_name: "{{ firth_novelathon_db_name }}"
      db_user: "{{ firth_novelathon_db_user }}"
      db_password: "{{ firth_novelathon_db_password }}"
    redis:
      username: "{{ firth_novelathon_redis_username }}"
      password: "{{ firth_novelathon_redis_password }}"
    mail:
      host: "{{ firth_novelathon_mail_host }}"
      port: "{{ firth_novelathon_mail_port }}"
      username: "{{ firth_novelathon_mail_username }}"
      password: "{{ firth_novelathon_mail_password }}"
      from_address: "{{ firth_novelathon_mail_from_address }}"
      from_name: "{{ firth_novelathon_mail_from_name }}"
    staging:
      image_tag: staging
      port: 9002
      server_name: novelathon.istic.dev
      app_url: https://novelathon.istic.dev
      app_key: "{{ firth_novelathon_staging_app_key }}"
      ssl_snippet: istic_dev
      mysql:
        db_name: "{{ firth_novelathon_staging_db_name }}"
        db_user: "{{ firth_novelathon_staging_db_user }}"
        db_password: "{{ firth_novelathon_staging_db_password }}"
      redis:
        username: "{{ firth_novelathon_staging_redis_username }}"
        password: "{{ firth_novelathon_staging_redis_password }}"

  - name: sprouter
    image: ghcr.io/aquarion/sprouter
    image_tag: latest
    backend: octane
    port: 8000
    server_name: social.istic.net
    app_url: https://social.istic.net
    app_key: "{{ vault_sprouter_app_key }}"
    app_name: Sprouter
    ssl_snippet: istic
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

**Important:** The existing `novelathon.yml` and `alchemistic.yml` vault files define the `firth_novelathon_*` and `firth_alchemistic_*` vars referenced above. Do not touch those files until Phase 2. Also verify the exact variable names by running:

```bash
ansible-vault view host_vars/firth.water.gkhs.net/novelathon.yml | grep "^firth_novelathon_app_key\|github_deploy_token\|db_name\|db_user\|redis_username\|mail_"
ansible-vault view host_vars/firth.water.gkhs.net/alchemistic.yml | grep "^firth_alchemistic_app_key\|db_name\|db_user\|mail_\|github_deploy_token"
```

Update the variable references in `laravel_apps.yml` if the actual names differ.

- [ ] **Run ansible-lint**

```bash
ansible-lint host_vars/firth.water.gkhs.net/laravel_apps.yml
```

- [ ] **Commit**

```bash
git add host_vars/firth.water.gkhs.net/laravel_apps.yml
git commit -m "⚙️ Add laravel_apps host_vars for firth"
```

---

## Task 13: Vault vars for Sprouter

**Files:**
- Create: `host_vars/firth.water.gkhs.net/laravel_apps.vault.yml` (vault-encrypted)

This file holds the sprouter-specific secrets referenced in `laravel_apps.yml`. The pre-commit hook (`Check host_vars are vault-encrypted`) requires `*.vault.yml` files to be encrypted.

- [ ] **Generate a Sprouter APP_KEY** (run this in the sprouter repo, not autopelago)

```bash
cd /home/aquarion/code/aquarion/sprouter
php artisan key:generate --show
```

Copy the output — it looks like `base64:...=`

- [ ] **Create and encrypt the vault file**

```bash
cd /home/aquarion/code/aquarion/autopelago
ansible-vault create host_vars/firth.water.gkhs.net/laravel_apps.vault.yml
```

In the editor, enter:

```yaml
---
vault_sprouter_app_key: "base64:PASTE_GENERATED_KEY_HERE"
vault_sprouter_github_deploy_token: "PASTE_GITHUB_PAT_HERE"
vault_sprouter_db_password: "GENERATE_RANDOM_PASSWORD_HERE"
vault_sprouter_redis_password: "GENERATE_RANDOM_PASSWORD_HERE"
```

Use `openssl rand -base64 32` to generate random passwords for `db_password` and `redis_password`. The GitHub PAT (`vault_sprouter_github_deploy_token`) needs `secrets:write` scope on the `aquarion/sprouter` repo.

- [ ] **Verify the vault file is encrypted**

```bash
head -1 host_vars/firth.water.gkhs.net/laravel_apps.vault.yml
```

Expected: `$ANSIBLE_VAULT;1.1;AES256`

- [ ] **Commit**

```bash
git add host_vars/firth.water.gkhs.net/laravel_apps.vault.yml
git commit -m "⚙️ Add Sprouter vault vars"
```

---

## Task 14: Wire up playbook.yml (Phase 1)

**Files:**
- Modify: `playbook.yml`

Add `firth_laravel_app` to the firth play's roles list, **after** `firth_novelathon` and `firth_alchemistic` (so both run during the transition). It will render the same vhosts and docker-compose files as the old roles — overwriting with equivalent content is harmless.

- [ ] **Open `playbook.yml` and find the firth play roles list**

```bash
grep -n "firth_novelathon\|firth_alchemistic\|firth_laravel" playbook.yml
```

- [ ] **Add `firth_laravel_app` after `firth_alchemistic`**

The relevant section currently looks like:

```yaml
    - firth_alchemistic
    - firth_novelathon
```

Change to:

```yaml
    - firth_alchemistic
    - firth_novelathon
    - firth_laravel_app
```

- [ ] **Run ansible-lint on the full playbook**

```bash
ansible-lint playbook.yml
```

Expected: no errors

- [ ] **Commit**

```bash
git add playbook.yml
git commit -m "⚙️ Add firth_laravel_app to firth play"
```

---

## Task 15: Check mode verification

- [ ] **Run in check mode against firth to verify the role would apply cleanly**

```bash
ansible-playbook playbook.yml -l firth --check --diff --tags firth_laravel_app 2>&1 | tee /tmp/firth-laravel-check.log
```

- [ ] **Review the output for unexpected changes**

Things to look for:
- System users being created for novelathon/alchemistic (expect: "would create" for sprouter, "ok" for existing apps)
- docker-compose.yml diffs — expect minor whitespace/formatting differences vs old templates; verify no unexpected env var changes
- nginx vhost diffs — same expectation
- Any failures or unreachable tasks

- [ ] **Fix any issues found, re-lint, re-run check mode until clean**

- [ ] **Commit any fixes**

```bash
git add -p
git commit -m "⚙️ Fix issues found in check mode"
```

---

## Task 16: Phase 2 — remove old roles

Once check mode passes cleanly, remove the old roles and run live.

- [ ] **Remove `firth_novelathon` and `firth_alchemistic` from `playbook.yml`**

The roles list for the firth play should now read:

```yaml
    - firth_laravel_app
```

(Remove the `firth_alchemistic` and `firth_novelathon` lines.)

- [ ] **Delete the old roles and vault files**

```bash
rm -rf roles/firth_novelathon roles/firth_alchemistic
rm host_vars/firth.water.gkhs.net/novelathon.yml
rm host_vars/firth.water.gkhs.net/alchemistic.yml
```

- [ ] **Run ansible-lint to confirm nothing references the deleted roles**

```bash
ansible-lint playbook.yml
```

- [ ] **Commit**

```bash
git add -A
git commit -m "❌ Remove firth_novelathon and firth_alchemistic roles"
```

---

## Task 17: Live deploy

- [ ] **Open a PR**

```bash
gh pr create --draft --title "⚙️ Add firth_laravel_app role (replaces novelathon + alchemistic, adds sprouter)" --body "$(cat <<'EOF'
## Summary
- Replaces `firth_novelathon` and `firth_alchemistic` with single parametric `firth_laravel_app` role
- Deploys Sprouter at `social.istic.net` as first new app
- All apps configured via `firth_laravel_apps` list in host_vars

## Test plan
- [ ] `ansible-lint` passes
- [ ] Check mode passes cleanly against firth
- [ ] Live deploy: novelathon.com still loads
- [ ] Live deploy: manage.istic.systems still loads
- [ ] Live deploy: social.istic.net loads after DNS is configured

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Run the playbook live against firth**

```bash
ansible-playbook playbook.yml -l firth
```

- [ ] **Verify novelathon.com loads correctly**

- [ ] **Verify manage.istic.systems loads correctly**

- [ ] **Verify Sprouter: check containers are running**

```bash
ssh novelathon@firth.water.gkhs.net "docker ps | grep sprouter"
ssh sprouter@firth.water.gkhs.net "docker ps"
```

Expected: `sprouter-app-1` running

- [ ] **Verify `social.istic.net` resolves and loads once DNS is pointed at firth**

---

## Self-review notes

- `firth_alchemistic_github_deploy_token` — verify this vault var exists in `alchemistic.yml` before running; alchemistic was developed earlier and may not have it. If missing, add it to the vault file before Phase 2.
- The `ssl_snippet: istic` used for `manage.istic.systems` maps to `/etc/letsencrypt/live/istic.net/` — this is how the existing alchemistic vhost works today; preserve it.
- Sprouter's `port: 8000` must not conflict with anything else on firth. Verify with `ss -tlnp | grep 8000` on the host before live deploy.
- `APP_NAME` in `fla_ctx` is derived from `fla.app_name | default(fla.name | capitalize)`. For `novelathon` this yields `Novelathon` ✓, for `alchemistic` → `Alchemistic` ✓, for `sprouter` → `Sprouter` ✓.
