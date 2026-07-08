# firth_novelathon Ansible Role Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `firth_novelathon` Ansible role to provision novelathon.com (production) and novelathon.istic.dev (staging) on Firth as Dockerised Laravel applications.

**Architecture:** Each environment gets a Docker Compose stack with `app` (PHP-FPM) and `worker` (queue:work) services pulling from GHCR, fronted by nginx on the host with fastcgi_pass. Secrets flow from Ansible vault into the docker-compose `environment:` block via Jinja2 templates. The role follows the `firth_alchemistic` pattern for Docker/nginx and the `stream_delta` task-file structure (general/deploy_production/deploy_staging split).

**Tech Stack:** Ansible, Docker Compose, PHP-FPM, nginx, MySQL (community.mysql), Redis ACL, Amazon Route53 (amazon.aws.route53), GHCR (community.docker)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `roles/firth_novelathon/defaults/main.yml` | All role defaults |
| Create | `roles/firth_novelathon/meta/main.yml` | Role metadata |
| Create | `roles/firth_novelathon/handlers/main.yml` | Restart/reload handlers |
| Create | `roles/firth_novelathon/tasks/main.yml` | Imports all task files |
| Create | `roles/firth_novelathon/tasks/general.yml` | DNS, DB, Redis ACL, GHCR auth, Docker network, directories |
| Create | `roles/firth_novelathon/tasks/deploy_production.yml` | Production docker-compose, nginx vhost, image pull, migrations |
| Create | `roles/firth_novelathon/tasks/deploy_staging.yml` | Staging docker-compose, nginx vhost, image pull, migrations |
| Create | `roles/firth_novelathon/templates/production/docker-compose.yml.j2` | Production stack (app + worker) |
| Create | `roles/firth_novelathon/templates/staging/docker-compose.yml.j2` | Staging stack (app + worker) |
| Create | `roles/firth_novelathon/templates/vhosts/novelathon.com.conf.j2` | Production nginx vhost |
| Create | `roles/firth_novelathon/templates/vhosts/novelathon.istic.dev.conf.j2` | Staging nginx vhost |
| Create | `host_vars/firth.water.gkhs.net/novelathon.yml` | Vault-encrypted secrets |
| Modify | `playbook.yml` | Add role to "Hello Firth" play |

---

## Task 1: Role skeleton — defaults, meta, and handlers

**Files:**
- Create: `roles/firth_novelathon/defaults/main.yml`
- Create: `roles/firth_novelathon/meta/main.yml`
- Create: `roles/firth_novelathon/handlers/main.yml`

- [ ] **Step 1: Create `defaults/main.yml`**

```yaml
---
# defaults file for roles/firth_novelathon

firth_novelathon_image: ghcr.io/istic/novelathon
firth_novelathon_image_tag: latest

# Preferred GHCR credentials. If unset, falls back to ghcr_username/ghcr_token.
firth_novelathon_ghcr_username:
firth_novelathon_ghcr_token:

# www-data UID/GID — resolved at runtime in general.yml. Leave blank to auto-detect.
firth_novelathon_www_data_uid:
firth_novelathon_www_data_gid:

# FPM ports exposed to localhost (alchemistic uses 9000 — no conflict)
firth_novelathon_fpm_port: 9001
firth_novelathon_staging_fpm_port: 9002

# Domain names
firth_novelathon_server_name: novelathon.com
firth_novelathon_staging_server_name: novelathon.istic.dev

# MySQL — production
firth_novelathon_mysql_login_host: 127.0.0.1
firth_novelathon_db_host: host.docker.internal
firth_novelathon_db_port: 3306
firth_novelathon_db_name:
firth_novelathon_db_user:

# MySQL — staging
firth_novelathon_staging_db_name:
firth_novelathon_staging_db_user:

# Redis — system Redis on host, accessed via host.docker.internal from containers
firth_novelathon_redis_host: host.docker.internal
firth_novelathon_redis_port: 6379
firth_novelathon_redis_username:
firth_novelathon_staging_redis_username:

# App URLs
firth_novelathon_app_url:
firth_novelathon_staging_app_url:

# Mail (shared across environments; override staging vars if needed)
firth_novelathon_mail_host:
firth_novelathon_mail_port: 587
firth_novelathon_mail_username:
firth_novelathon_mail_from_address:
firth_novelathon_mail_from_name: Novelathon
```

- [ ] **Step 2: Create `meta/main.yml`**

```yaml
---
galaxy_info:
  author: Nicholas Avenell
  description: An Ansible role to deploy the Novelathon Laravel application.
  company: Istic Co. <https://istic.co>
  license: GPL-2.0-or-later
  min_ansible_version: "2.1"
  galaxy_tags:
    - docker
    - laravel

dependencies: []
```

- [ ] **Step 3: Create `handlers/main.yml`**

```yaml
---
# handlers file for roles/firth_novelathon

- name: Restart Novelathon
  ansible.builtin.command: docker compose up -d --force-recreate
  args:
    chdir: "{{ docker_root }}/novelathon"

- name: Restart Novelathon Staging
  ansible.builtin.command: docker compose up -d --force-recreate
  args:
    chdir: "{{ docker_root }}/novelathon-staging"

- name: Reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded
```

- [ ] **Step 4: Run ansible-lint on the new files**

```bash
ansible-lint roles/firth_novelathon/
```

Expected: no errors or warnings.

- [ ] **Step 5: Commit**

```bash
git add roles/firth_novelathon/
git commit -m "🎇 Add firth_novelathon role skeleton — defaults, meta, handlers"
```

---

## Task 2: `tasks/general.yml` — DNS, database, Redis ACL, GHCR, Docker infra

**Files:**
- Create: `roles/firth_novelathon/tasks/general.yml`

- [ ] **Step 1: Create `tasks/general.yml`**

```yaml
---
- name: Resolve host www-data identity defaults
  tags:
    - novelathon
    - docker
  block:
    - name: Lookup host passwd entry for www-data
      ansible.builtin.getent:
        database: passwd
        key: www-data
        fail_key: false
      changed_when: false

    - name: Lookup host group entry for www-data
      ansible.builtin.getent:
        database: group
        key: www-data
        fail_key: false
      changed_when: false

    - name: Resolve www-data UID/GID for Novelathon role
      ansible.builtin.set_fact:
        firth_novelathon_www_data_uid_resolved: >-
          {{
            (firth_novelathon_www_data_uid | string | length > 0)
            | ternary(
              firth_novelathon_www_data_uid | int,
              ((ansible_facts.getent_passwd | default({})).get('www-data', ['x', '33'])[1] | int)
            )
          }}
        firth_novelathon_www_data_gid_resolved: >-
          {{
            (firth_novelathon_www_data_gid | string | length > 0)
            | ternary(
              firth_novelathon_www_data_gid | int,
              ((ansible_facts.getent_group | default({})).get('www-data', ['x', '33'])[1] | int)
            )
          }}
      changed_when: false

  rescue:
    - name: Fallback www-data UID/GID for Novelathon role
      ansible.builtin.set_fact:
        firth_novelathon_www_data_uid_resolved: 33
        firth_novelathon_www_data_gid_resolved: 33
      changed_when: false

- name: Register Novelathon DNS
  tags:
    - novelathon
    - dns
    - aws
  block:
    - name: novelathon.com - A
      amazon.aws.route53:
        overwrite: true
        state: present
        zone: novelathon.com
        record: "novelathon.com."
        type: A
        ttl: "300"
        value: "{{ loadbalancer_ip }}"
        aws_profile: istic
      connection: local
      become: false

    - name: novelathon.istic.dev - A
      amazon.aws.route53:
        overwrite: true
        state: present
        zone: istic.dev
        record: "novelathon.istic.dev."
        type: A
        ttl: "300"
        value: "{{ loadbalancer_ip }}"
        aws_profile: istic
      connection: local
      become: false

  rescue:
    - name: Debug failure to create Route53 records for Novelathon
      ansible.builtin.debug:
        msg: "Failed to create Route53 records for Novelathon. Check loadbalancer_ip and AWS credentials."

- name: Setup Novelathon databases
  tags:
    - novelathon
    - database
  block:
    - name: Ensure python3-mysqldb is installed
      ansible.builtin.apt:
        name: python3-mysqldb
        state: present

    - name: Create Novelathon production database
      community.mysql.mysql_db:
        name: "{{ firth_novelathon_db_name }}"
        state: present
        login_host: "{{ firth_novelathon_mysql_login_host }}"
        login_user: root
        login_password: "{{ mysql_root_password }}"

    - name: Create Novelathon production database user
      community.mysql.mysql_user:
        name: "{{ firth_novelathon_db_user }}"
        password: "{{ firth_novelathon_db_password }}"
        priv: "{{ firth_novelathon_db_name }}.*:ALL"
        host: "%"
        state: present
        login_host: "{{ firth_novelathon_mysql_login_host }}"
        login_user: root
        login_password: "{{ mysql_root_password }}"
        column_case_sensitive: true

    - name: Create Novelathon staging database
      community.mysql.mysql_db:
        name: "{{ firth_novelathon_staging_db_name }}"
        state: present
        login_host: "{{ firth_novelathon_mysql_login_host }}"
        login_user: root
        login_password: "{{ mysql_root_password }}"

    - name: Create Novelathon staging database user
      community.mysql.mysql_user:
        name: "{{ firth_novelathon_staging_db_user }}"
        password: "{{ firth_novelathon_staging_db_password }}"
        priv: "{{ firth_novelathon_staging_db_name }}.*:ALL"
        host: "%"
        state: present
        login_host: "{{ firth_novelathon_mysql_login_host }}"
        login_user: root
        login_password: "{{ mysql_root_password }}"
        column_case_sensitive: true

  rescue:
    - name: Debug failure to setup Novelathon databases
      ansible.builtin.debug:
        msg: "Failed to setup Novelathon databases. Check mysql_root_password and firth_novelathon_db_* variables."

- name: Configure Redis ACL users for Novelathon
  tags:
    - novelathon
    - redis
  block:
    - name: Configure Redis production user
      ansible.builtin.lineinfile:
        path: /etc/redis/users.acl
        line: "user {{ firth_novelathon_redis_username }} on +@all -DEBUG ~* >{{ firth_novelathon_redis_password }}"
        regexp: "^user {{ firth_novelathon_redis_username }}"
      notify:
        - Reload Redis ACL

    - name: Configure Redis staging user
      ansible.builtin.lineinfile:
        path: /etc/redis/users.acl
        line: "user {{ firth_novelathon_staging_redis_username }} on +@all -DEBUG ~* >{{ firth_novelathon_staging_redis_password }}"
        regexp: "^user {{ firth_novelathon_staging_redis_username }}"
      notify:
        - Reload Redis ACL

  rescue:
    - name: Debug failure to configure Redis ACL for Novelathon
      ansible.builtin.debug:
        msg: "Failed to configure Redis ACL for Novelathon. Check /etc/redis/users.acl exists and is writable."

- name: Log in to GitHub Container Registry
  tags:
    - novelathon
    - docker
  when: firth_novelathon_image is match('^ghcr\\.io/.+')
  block:
    - name: Resolve GHCR credentials for Novelathon image
      ansible.builtin.set_fact:
        firth_novelathon_ghcr_username_resolved: "{{ firth_novelathon_ghcr_username | default(ghcr_username | default(''), true) }}"
        firth_novelathon_ghcr_token_resolved: "{{ firth_novelathon_ghcr_token | default(ghcr_token | default(''), true) }}"
      changed_when: false
      no_log: true

    - name: Validate GHCR credentials are configured
      ansible.builtin.assert:
        that:
          - firth_novelathon_ghcr_username_resolved | length > 0
          - firth_novelathon_ghcr_token_resolved | length > 0
        fail_msg: >-
          Missing GHCR credentials for image {{ firth_novelathon_image }}.
          Set firth_novelathon_ghcr_username/firth_novelathon_ghcr_token
          or legacy ghcr_username/ghcr_token. Token must have read:packages scope.
      no_log: true

    - name: Authenticate to GHCR
      community.docker.docker_login:
        registry_url: ghcr.io
        username: "{{ firth_novelathon_ghcr_username_resolved }}"
        password: "{{ firth_novelathon_ghcr_token_resolved }}"
      no_log: true

- name: Ensure shared Docker network exists
  tags:
    - novelathon
    - docker
  community.docker.docker_network:
    name: "{{ firth_services_docker_network }}"
    state: present

- name: Create Novelathon working directories
  tags:
    - novelathon
    - docker
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop:
    - "{{ docker_root }}/novelathon"
    - "{{ docker_root }}/novelathon/public"
    - "{{ docker_root }}/novelathon-staging"
    - "{{ docker_root }}/novelathon-staging/public"
```

- [ ] **Step 2: Run ansible-lint**

```bash
ansible-lint roles/firth_novelathon/tasks/general.yml
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add roles/firth_novelathon/tasks/general.yml
git commit -m "🎇 Add firth_novelathon general.yml — DNS, DB, Redis ACL, Docker infra"
```

---

## Task 3: Production Docker Compose template

**Files:**
- Create: `roles/firth_novelathon/templates/production/docker-compose.yml.j2`

- [ ] **Step 1: Create `templates/production/docker-compose.yml.j2`**

```yaml
# Docker Compose file for Novelathon (production)
# {{ ansible_managed }}
name: novelathon
services:
  app:
    image: "{{ firth_novelathon_image }}:{{ firth_novelathon_image_tag }}"
    user: "{{ firth_novelathon_www_data_uid_resolved | default(33) }}:{{ firth_novelathon_www_data_gid_resolved | default(33) }}"
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{ firth_novelathon_fpm_port }}:9000"
    environment:
      APP_NAME: Novelathon
      APP_ENV: production
      APP_KEY: "{{ firth_novelathon_app_key }}"
      APP_DEBUG: "false"
      APP_URL: "{{ firth_novelathon_app_url }}"
      LOG_STACK: "stderr,single"
      DB_CONNECTION: mysql
      DB_HOST: "{{ firth_novelathon_db_host }}"
      DB_PORT: "{{ firth_novelathon_db_port }}"
      DB_DATABASE: "{{ firth_novelathon_db_name }}"
      DB_USERNAME: "{{ firth_novelathon_db_user }}"
      DB_PASSWORD: "{{ firth_novelathon_db_password }}"
      REDIS_HOST: "{{ firth_novelathon_redis_host }}"
      REDIS_PORT: "{{ firth_novelathon_redis_port }}"
      REDIS_USERNAME: "{{ firth_novelathon_redis_username }}"
      REDIS_PASSWORD: "{{ firth_novelathon_redis_password }}"
      MAIL_MAILER: smtp
      MAIL_HOST: "{{ firth_novelathon_mail_host }}"
      MAIL_PORT: "{{ firth_novelathon_mail_port }}"
      MAIL_USERNAME: "{{ firth_novelathon_mail_username }}"
      MAIL_PASSWORD: "{{ firth_novelathon_mail_password }}"
      MAIL_FROM_ADDRESS: "{{ firth_novelathon_mail_from_address }}"
      MAIL_FROM_NAME: "{{ firth_novelathon_mail_from_name }}"
    volumes:
      - novelathon_storage:/var/www/html/storage
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - firth_services
    logging:
      driver: journald
      options:
        tag: "$${.Name}/$${.ID}"

  worker:
    image: "{{ firth_novelathon_image }}:{{ firth_novelathon_image_tag }}"
    restart: unless-stopped
    command: ["php", "artisan", "queue:work"]
    environment:
      APP_NAME: Novelathon
      APP_ENV: production
      APP_KEY: "{{ firth_novelathon_app_key }}"
      APP_DEBUG: "false"
      APP_URL: "{{ firth_novelathon_app_url }}"
      LOG_STACK: "stderr,single"
      DB_CONNECTION: mysql
      DB_HOST: "{{ firth_novelathon_db_host }}"
      DB_PORT: "{{ firth_novelathon_db_port }}"
      DB_DATABASE: "{{ firth_novelathon_db_name }}"
      DB_USERNAME: "{{ firth_novelathon_db_user }}"
      DB_PASSWORD: "{{ firth_novelathon_db_password }}"
      REDIS_HOST: "{{ firth_novelathon_redis_host }}"
      REDIS_PORT: "{{ firth_novelathon_redis_port }}"
      REDIS_USERNAME: "{{ firth_novelathon_redis_username }}"
      REDIS_PASSWORD: "{{ firth_novelathon_redis_password }}"
      MAIL_MAILER: smtp
      MAIL_HOST: "{{ firth_novelathon_mail_host }}"
      MAIL_PORT: "{{ firth_novelathon_mail_port }}"
      MAIL_USERNAME: "{{ firth_novelathon_mail_username }}"
      MAIL_PASSWORD: "{{ firth_novelathon_mail_password }}"
      MAIL_FROM_ADDRESS: "{{ firth_novelathon_mail_from_address }}"
      MAIL_FROM_NAME: "{{ firth_novelathon_mail_from_name }}"
    volumes:
      - novelathon_storage:/var/www/html/storage
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - firth_services
    logging:
      driver: journald
      options:
        tag: "$${.Name}/$${.ID}"

volumes:
  novelathon_storage:

networks:
  firth_services:
    external: true
    name: "{{ firth_services_docker_network }}"
```

- [ ] **Step 2: Verify the template renders valid YAML by checking Jinja2 syntax visually** — confirm all `{{ }}` references match variable names in `defaults/main.yml` or the vault file. No `undefined` references.

- [ ] **Step 3: Commit**

```bash
git add roles/firth_novelathon/templates/production/
git commit -m "🎇 Add firth_novelathon production docker-compose template"
```

---

## Task 4: Staging Docker Compose template

**Files:**
- Create: `roles/firth_novelathon/templates/staging/docker-compose.yml.j2`

- [ ] **Step 1: Create `templates/staging/docker-compose.yml.j2`**

```yaml
# Docker Compose file for Novelathon (staging)
# {{ ansible_managed }}
name: novelathon-staging
services:
  app:
    image: "{{ firth_novelathon_image }}:{{ firth_novelathon_image_tag }}"
    user: "{{ firth_novelathon_www_data_uid_resolved | default(33) }}:{{ firth_novelathon_www_data_gid_resolved | default(33) }}"
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{ firth_novelathon_staging_fpm_port }}:9000"
    environment:
      APP_NAME: "Novelathon Staging"
      APP_ENV: staging
      APP_KEY: "{{ firth_novelathon_staging_app_key }}"
      APP_DEBUG: "true"
      APP_URL: "{{ firth_novelathon_staging_app_url }}"
      LOG_STACK: "stderr,single"
      DB_CONNECTION: mysql
      DB_HOST: "{{ firth_novelathon_db_host }}"
      DB_PORT: "{{ firth_novelathon_db_port }}"
      DB_DATABASE: "{{ firth_novelathon_staging_db_name }}"
      DB_USERNAME: "{{ firth_novelathon_staging_db_user }}"
      DB_PASSWORD: "{{ firth_novelathon_staging_db_password }}"
      REDIS_HOST: "{{ firth_novelathon_redis_host }}"
      REDIS_PORT: "{{ firth_novelathon_redis_port }}"
      REDIS_USERNAME: "{{ firth_novelathon_staging_redis_username }}"
      REDIS_PASSWORD: "{{ firth_novelathon_staging_redis_password }}"
      MAIL_MAILER: smtp
      MAIL_HOST: "{{ firth_novelathon_mail_host }}"
      MAIL_PORT: "{{ firth_novelathon_mail_port }}"
      MAIL_USERNAME: "{{ firth_novelathon_mail_username }}"
      MAIL_PASSWORD: "{{ firth_novelathon_mail_password }}"
      MAIL_FROM_ADDRESS: "{{ firth_novelathon_mail_from_address }}"
      MAIL_FROM_NAME: "{{ firth_novelathon_mail_from_name }}"
    volumes:
      - novelathon_staging_storage:/var/www/html/storage
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - firth_services
    logging:
      driver: journald
      options:
        tag: "$${.Name}/$${.ID}"

  worker:
    image: "{{ firth_novelathon_image }}:{{ firth_novelathon_image_tag }}"
    restart: unless-stopped
    command: ["php", "artisan", "queue:work"]
    environment:
      APP_NAME: "Novelathon Staging"
      APP_ENV: staging
      APP_KEY: "{{ firth_novelathon_staging_app_key }}"
      APP_DEBUG: "true"
      APP_URL: "{{ firth_novelathon_staging_app_url }}"
      LOG_STACK: "stderr,single"
      DB_CONNECTION: mysql
      DB_HOST: "{{ firth_novelathon_db_host }}"
      DB_PORT: "{{ firth_novelathon_db_port }}"
      DB_DATABASE: "{{ firth_novelathon_staging_db_name }}"
      DB_USERNAME: "{{ firth_novelathon_staging_db_user }}"
      DB_PASSWORD: "{{ firth_novelathon_staging_db_password }}"
      REDIS_HOST: "{{ firth_novelathon_redis_host }}"
      REDIS_PORT: "{{ firth_novelathon_redis_port }}"
      REDIS_USERNAME: "{{ firth_novelathon_staging_redis_username }}"
      REDIS_PASSWORD: "{{ firth_novelathon_staging_redis_password }}"
      MAIL_MAILER: smtp
      MAIL_HOST: "{{ firth_novelathon_mail_host }}"
      MAIL_PORT: "{{ firth_novelathon_mail_port }}"
      MAIL_USERNAME: "{{ firth_novelathon_mail_username }}"
      MAIL_PASSWORD: "{{ firth_novelathon_mail_password }}"
      MAIL_FROM_ADDRESS: "{{ firth_novelathon_mail_from_address }}"
      MAIL_FROM_NAME: "{{ firth_novelathon_mail_from_name }}"
    volumes:
      - novelathon_staging_storage:/var/www/html/storage
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - firth_services
    logging:
      driver: journald
      options:
        tag: "$${.Name}/$${.ID}"

volumes:
  novelathon_staging_storage:

networks:
  firth_services:
    external: true
    name: "{{ firth_services_docker_network }}"
```

- [ ] **Step 2: Verify all `_staging_` variable references match defaults/vault variable names. Key differences from production: `firth_novelathon_staging_fpm_port`, `firth_novelathon_staging_app_key`, `firth_novelathon_staging_app_url`, `firth_novelathon_staging_db_name`, `firth_novelathon_staging_db_user`, `firth_novelathon_staging_db_password`, `firth_novelathon_staging_redis_username`, `firth_novelathon_staging_redis_password`.**

- [ ] **Step 3: Commit**

```bash
git add roles/firth_novelathon/templates/staging/
git commit -m "🎇 Add firth_novelathon staging docker-compose template"
```

---

## Task 5: Nginx vhost templates

**Files:**
- Create: `roles/firth_novelathon/templates/vhosts/novelathon.com.conf.j2`
- Create: `roles/firth_novelathon/templates/vhosts/novelathon.istic.dev.conf.j2`

- [ ] **Step 1: Create `templates/vhosts/novelathon.com.conf.j2`**

```nginx
# {{ ansible_managed }}
server {
    listen 80;
    listen [::]:80;
    server_name {{ firth_novelathon_server_name }};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl proxy_protocol;
    listen [::]:443 ssl proxy_protocol;
    server_name {{ firth_novelathon_server_name }};

    include /etc/nginx/snippets/errors.conf;
    include /etc/nginx/snippets/ssl/novelathon.com_ssl.conf;

    error_log  /var/log/nginx/novelathon.error.log;
    access_log /var/log/nginx/novelathon.access.log;

    add_header X-WhyAmI novelathon;

    location /build/ {
        alias {{ docker_root }}/novelathon/public/build/;
        expires max;
        add_header Cache-Control "public, immutable";
    }

    location / {
        fastcgi_pass 127.0.0.1:{{ firth_novelathon_fpm_port }};
        fastcgi_param SCRIPT_FILENAME /var/www/html/public/index.php;
        fastcgi_param QUERY_STRING $query_string;
        include fastcgi_params;
    }
}
```

- [ ] **Step 2: Create `templates/vhosts/novelathon.istic.dev.conf.j2`**

```nginx
# {{ ansible_managed }}
server {
    listen 80;
    listen [::]:80;
    server_name {{ firth_novelathon_staging_server_name }};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl proxy_protocol;
    listen [::]:443 ssl proxy_protocol;
    server_name {{ firth_novelathon_staging_server_name }};

    include /etc/nginx/snippets/errors.conf;
    include /etc/nginx/snippets/ssl/istic_dev_ssl.conf;

    error_log  /var/log/nginx/novelathon-staging.error.log;
    access_log /var/log/nginx/novelathon-staging.access.log;

    add_header X-WhyAmI novelathon-staging;

    location /build/ {
        alias {{ docker_root }}/novelathon-staging/public/build/;
        expires max;
        add_header Cache-Control "public, immutable";
    }

    location / {
        fastcgi_pass 127.0.0.1:{{ firth_novelathon_staging_fpm_port }};
        fastcgi_param SCRIPT_FILENAME /var/www/html/public/index.php;
        fastcgi_param QUERY_STRING $query_string;
        include fastcgi_params;
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add roles/firth_novelathon/templates/vhosts/
git commit -m "🎇 Add firth_novelathon nginx vhost templates"
```

---

## Task 6: `tasks/deploy_production.yml`

**Files:**
- Create: `roles/firth_novelathon/tasks/deploy_production.yml`

- [ ] **Step 1: Create `tasks/deploy_production.yml`**

```yaml
---
- name: Deploy Novelathon production Docker Compose
  tags:
    - novelathon
    - docker
  notify: Restart Novelathon
  block:
    - name: Template docker-compose.yml for Novelathon production
      ansible.builtin.template:
        src: production/docker-compose.yml.j2
        dest: "{{ docker_root }}/novelathon/docker-compose.yml"
        owner: root
        group: docker
        mode: "0660"

  rescue:
    - name: Debug failure to deploy Novelathon production Docker Compose
      ansible.builtin.debug:
        msg: "Failed to deploy Novelathon production Docker Compose."

- name: Pull Novelathon production image
  tags:
    - novelathon
    - docker
  ansible.builtin.command: docker compose pull
  args:
    chdir: "{{ docker_root }}/novelathon"
  register: firth_novelathon_pull
  changed_when: "'Pulled' in firth_novelathon_pull.stderr"
  notify: Restart Novelathon

- name: Start Novelathon production
  tags:
    - novelathon
    - docker
  ansible.builtin.command: docker compose up -d
  args:
    chdir: "{{ docker_root }}/novelathon"
  when: firth_novelathon_pull.changed

- name: Copy Vite build assets from Novelathon production container to host
  tags:
    - novelathon
    - docker
  ansible.builtin.command: docker compose cp app:/var/www/html/public/build public/build
  args:
    chdir: "{{ docker_root }}/novelathon"
  when: firth_novelathon_pull.changed

- name: Deploy Novelathon production nginx vhost
  tags:
    - novelathon
    - nginx
  block:
    - name: Deploy nginx vhost to sites-available
      ansible.builtin.template:
        src: vhosts/novelathon.com.conf.j2
        dest: /etc/nginx/sites-available/novelathon.com.conf
        owner: root
        group: root
        mode: "0644"
      notify: Reload nginx

    - name: Enable nginx vhost
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/novelathon.com.conf
        src: ../sites-available/novelathon.com.conf
        state: link
      notify: Reload nginx

- name: Run Novelathon production database migrations
  tags:
    - novelathon
    - migrations
  ansible.builtin.command: >
    docker compose exec -T app php artisan migrate --force
  args:
    chdir: "{{ docker_root }}/novelathon"
```

- [ ] **Step 2: Run ansible-lint**

```bash
ansible-lint roles/firth_novelathon/tasks/deploy_production.yml
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add roles/firth_novelathon/tasks/deploy_production.yml
git commit -m "🎇 Add firth_novelathon deploy_production.yml"
```

---

## Task 7: `tasks/deploy_staging.yml`

**Files:**
- Create: `roles/firth_novelathon/tasks/deploy_staging.yml`

- [ ] **Step 1: Create `tasks/deploy_staging.yml`**

```yaml
---
- name: Deploy Novelathon staging Docker Compose
  tags:
    - novelathon
    - docker
  notify: Restart Novelathon Staging
  block:
    - name: Template docker-compose.yml for Novelathon staging
      ansible.builtin.template:
        src: staging/docker-compose.yml.j2
        dest: "{{ docker_root }}/novelathon-staging/docker-compose.yml"
        owner: root
        group: docker
        mode: "0660"

  rescue:
    - name: Debug failure to deploy Novelathon staging Docker Compose
      ansible.builtin.debug:
        msg: "Failed to deploy Novelathon staging Docker Compose."

- name: Pull Novelathon staging image
  tags:
    - novelathon
    - docker
  ansible.builtin.command: docker compose pull
  args:
    chdir: "{{ docker_root }}/novelathon-staging"
  register: firth_novelathon_staging_pull
  changed_when: "'Pulled' in firth_novelathon_staging_pull.stderr"
  notify: Restart Novelathon Staging

- name: Start Novelathon staging
  tags:
    - novelathon
    - docker
  ansible.builtin.command: docker compose up -d
  args:
    chdir: "{{ docker_root }}/novelathon-staging"
  when: firth_novelathon_staging_pull.changed

- name: Copy Vite build assets from Novelathon staging container to host
  tags:
    - novelathon
    - docker
  ansible.builtin.command: docker compose cp app:/var/www/html/public/build public/build
  args:
    chdir: "{{ docker_root }}/novelathon-staging"
  when: firth_novelathon_staging_pull.changed

- name: Deploy Novelathon staging nginx vhost
  tags:
    - novelathon
    - nginx
  block:
    - name: Deploy nginx vhost to sites-available
      ansible.builtin.template:
        src: vhosts/novelathon.istic.dev.conf.j2
        dest: /etc/nginx/sites-available/novelathon.istic.dev.conf
        owner: root
        group: root
        mode: "0644"
      notify: Reload nginx

    - name: Enable nginx vhost
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/novelathon.istic.dev.conf
        src: ../sites-available/novelathon.istic.dev.conf
        state: link
      notify: Reload nginx

- name: Run Novelathon staging database migrations
  tags:
    - novelathon
    - migrations
  ansible.builtin.command: >
    docker compose exec -T app php artisan migrate --force
  args:
    chdir: "{{ docker_root }}/novelathon-staging"
```

- [ ] **Step 2: Run ansible-lint**

```bash
ansible-lint roles/firth_novelathon/tasks/deploy_staging.yml
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add roles/firth_novelathon/tasks/deploy_staging.yml
git commit -m "🎇 Add firth_novelathon deploy_staging.yml"
```

---

## Task 8: `tasks/main.yml` and wire into playbook

**Files:**
- Create: `roles/firth_novelathon/tasks/main.yml`
- Modify: `playbook.yml` (line 89, after `- firth_alchemistic`)

- [ ] **Step 1: Create `tasks/main.yml`**

```yaml
---
- name: General Novelathon setup
  ansible.builtin.import_tasks: general.yml
- name: Novelathon production deployment
  ansible.builtin.import_tasks: deploy_production.yml
- name: Novelathon staging deployment
  ansible.builtin.import_tasks: deploy_staging.yml
```

- [ ] **Step 2: Add role to `playbook.yml`**

In the "Hello Firth" play (around line 89), add `- firth_novelathon` after `- firth_alchemistic`:

```yaml
    - firth_alchemistic
    - firth_novelathon
```

- [ ] **Step 3: Run ansible-lint on the full role**

```bash
ansible-lint roles/firth_novelathon/
```

Expected: no errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add roles/firth_novelathon/tasks/main.yml playbook.yml
git commit -m "🎇 Wire firth_novelathon into playbook"
```

---

## Task 9: Vault vars file

**Files:**
- Create: `host_vars/firth.water.gkhs.net/novelathon.yml` (vault-encrypted)

- [ ] **Step 1: Create the vault file**

```bash
ansible-vault create host_vars/firth.water.gkhs.net/novelathon.yml
```

- [ ] **Step 2: Add the following variables** (fill in real values for the server):

```yaml
# Production
firth_novelathon_app_url: https://novelathon.com
firth_novelathon_app_key: base64:REPLACE_WITH_REAL_KEY
firth_novelathon_db_name: novelathon
firth_novelathon_db_user: novelathon
firth_novelathon_db_password: REPLACE_WITH_REAL_PASSWORD
firth_novelathon_redis_username: novelathon
firth_novelathon_redis_password: REPLACE_WITH_REAL_PASSWORD
firth_novelathon_mail_host: REPLACE_WITH_REAL_HOST
firth_novelathon_mail_username: REPLACE_WITH_REAL_USERNAME
firth_novelathon_mail_password: REPLACE_WITH_REAL_PASSWORD
firth_novelathon_mail_from_address: REPLACE_WITH_REAL_ADDRESS

# Staging
firth_novelathon_staging_app_url: https://novelathon.istic.dev
firth_novelathon_staging_app_key: base64:REPLACE_WITH_REAL_KEY
firth_novelathon_staging_db_name: novelathon_staging
firth_novelathon_staging_db_user: novelathon_staging
firth_novelathon_staging_db_password: REPLACE_WITH_REAL_PASSWORD
firth_novelathon_staging_redis_username: novelathon_staging
firth_novelathon_staging_redis_password: REPLACE_WITH_REAL_PASSWORD
```

- [ ] **Step 3: Verify pre-commit vault check passes**

```bash
pre-commit run --files host_vars/firth.water.gkhs.net/novelathon.yml
```

Expected: "Check host_vars are vault-encrypted ... Passed"

- [ ] **Step 4: Commit**

```bash
git add host_vars/firth.water.gkhs.net/novelathon.yml
git commit -m "🎇 Add firth_novelathon vault vars for Firth"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Route53 A records for novelathon.com + novelathon.istic.dev → loadbalancer_ip | Task 2, general.yml |
| MySQL prod + staging databases and users | Task 2, general.yml |
| Redis ACL users (prod + staging) | Task 2, general.yml |
| GHCR auth with credential fallback | Task 2, general.yml |
| Shared Docker network + working directories | Task 2, general.yml |
| www-data UID/GID resolution | Task 2, general.yml |
| Production docker-compose (app + worker) | Task 3 |
| Staging docker-compose (app + worker) | Task 4 |
| novelathon.com nginx vhost | Task 5 |
| novelathon.istic.dev nginx vhost | Task 5 |
| Production deployment tasks | Task 6 |
| Staging deployment tasks | Task 7 |
| tasks/main.yml + playbook wiring | Task 8 |
| Vault vars file | Task 9 |
| novelathon.com uses novelathon.com_ssl.conf (not istic_ssl) | Task 5, confirmed |
| novelathon.istic.dev uses istic_dev_ssl.conf | Task 5, confirmed |
| FPM ports don't conflict with alchemistic (9000) | Defaults: 9001/9002 |
| journald logging | Tasks 3, 4 |
| Vite build assets copied from container | Tasks 6, 7 |
| Migrations run unconditionally (alchemistic pattern) | Tasks 6, 7 |

All spec requirements covered. No gaps found.
