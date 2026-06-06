# firth_laravel_app_remove Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `firth_laravel_app_remove` Ansible role that safely deprovisions Dockerised Laravel apps from firth, archiving the database dump, docker-compose file, and storage volume before any destructive steps.

**Architecture:** Standalone role mirroring `firth_laravel_app`'s structure. Each app in `firth_laravel_app_remove_apps` gets a context fact `flr_ctx` built in `app.yml`, which is used by all subtask files. Archive always runs unconditionally first; each removal step is gated by an opt-in flag. Staging runs the same sequence scoped to `{{ name }}-staging`, inheriting parent remove flags unless overridden.

**Tech Stack:** Ansible, community.mysql, community.docker, Docker CLI, alpine container for volume archival.

---

## File Map

| Path | Action | Purpose |
|---|---|---|
| `roles/firth_laravel_app_remove/defaults/main.yml` | Create | Role defaults |
| `roles/firth_laravel_app_remove/meta/main.yml` | Create | Galaxy metadata |
| `roles/firth_laravel_app_remove/tasks/main.yml` | Create | Loop over `firth_laravel_app_remove_apps` |
| `roles/firth_laravel_app_remove/tasks/app.yml` | Create | Build `flr_ctx`, orchestrate subtasks |
| `roles/firth_laravel_app_remove/tasks/archive.yml` | Create | DB dump + compose copy + volume tar + final tarball |
| `roles/firth_laravel_app_remove/tasks/containers.yml` | Create | `docker compose down --volumes` |
| `roles/firth_laravel_app_remove/tasks/mysql.yml` | Create | Drop DB and user |
| `roles/firth_laravel_app_remove/tasks/redis.yml` | Create | Remove ACL entry |
| `roles/firth_laravel_app_remove/tasks/nginx.yml` | Create | Remove vhost files, reload nginx |
| `roles/firth_laravel_app_remove/tasks/workdir.yml` | Create | `rm -rf` working directory |
| `roles/firth_laravel_app_remove/tasks/system_user.yml` | Create | Remove system user and home |
| `roles/firth_laravel_app_remove/tasks/staging.yml` | Create | Override `flr_ctx` for staging, run same subtasks |
| `host_vars/firth.water.gkhs.net/laravel_apps_remove.yml` | Create | Sprouter removal config |
| `playbook.yml` | Modify | Add `firth_laravel_app_remove` to Hello Firth play |

---

### Task 1: Role scaffold — defaults, meta, and host_vars

**Files:**
- Create: `roles/firth_laravel_app_remove/defaults/main.yml`
- Create: `roles/firth_laravel_app_remove/meta/main.yml`
- Create: `host_vars/firth.water.gkhs.net/laravel_apps_remove.yml`

- [ ] **Create defaults/main.yml**

```yaml
---
firth_laravel_app_remove_apps: []
firth_laravel_app_remove_mysql_login_host: 127.0.0.1
firth_laravel_app_remove_mysql_login_user: root
```

- [ ] **Create meta/main.yml**

```yaml
---
galaxy_info:
  author: Nicholas Avenell
  description: Deprovisions Dockerised Laravel apps from firth, archiving data before removal.
  company: Istic Co. <https://istic.co>
  license: GPL-2.0-or-later
  min_ansible_version: "2.1"
  galaxy_tags:
    - docker
    - laravel

dependencies: []
```

- [ ] **Create host_vars/firth.water.gkhs.net/laravel_apps_remove.yml**

All `remove:` flags start as `false` — flip to `true` when ready to run each step.

```yaml
---
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
      remove: {}
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors (only defaults and meta exist so far).

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/ host_vars/firth.water.gkhs.net/laravel_apps_remove.yml
git commit -m "⚙️ Scaffold firth_laravel_app_remove role with defaults and host_vars"
```

---

### Task 2: main.yml and app.yml

**Files:**
- Create: `roles/firth_laravel_app_remove/tasks/main.yml`
- Create: `roles/firth_laravel_app_remove/tasks/app.yml`

- [ ] **Create tasks/main.yml**

Loops over `firth_laravel_app_remove_apps`, delegating each app to `app.yml`. Mirrors `firth_laravel_app/tasks/main.yml`.

```yaml
---
- name: Remove Laravel applications
  ansible.builtin.include_tasks: app.yml
  loop: "{{ firth_laravel_app_remove_apps }}"
  loop_control:
    loop_var: firth_laravel_app_remove_item
    label: "{{ firth_laravel_app_remove_item.name }}"
  tags: firth_laravel_app_remove
```

- [ ] **Create tasks/app.yml**

Builds `flr` (raw item) and `flr_ctx` (resolved context), then includes subtasks in order. System user removal runs last; staging runs after all production steps.

```yaml
---
- name: Set context for {{ firth_laravel_app_remove_item.name }} # noqa: var-naming[no-role-prefix]
  ansible.builtin.set_fact:
    flr: "{{ firth_laravel_app_remove_item }}"
    flr_ctx:
      name: "{{ firth_laravel_app_remove_item.name }}"
      mysql: "{{ firth_laravel_app_remove_item.mysql | default({}) }}"
      redis: "{{ firth_laravel_app_remove_item.redis | default({}) }}"
      server_name: "{{ firth_laravel_app_remove_item.server_name }}"
      remove:
        containers: "{{ firth_laravel_app_remove_item.remove.containers | default(false) }}"
        mysql: "{{ firth_laravel_app_remove_item.remove.mysql | default(false) }}"
        redis: "{{ firth_laravel_app_remove_item.remove.redis | default(false) }}"
        nginx: "{{ firth_laravel_app_remove_item.remove.nginx | default(false) }}"
        workdir: "{{ firth_laravel_app_remove_item.remove.workdir | default(false) }}"
        system_user: "{{ firth_laravel_app_remove_item.remove.system_user | default(false) }}"
      archive_date: "{{ ansible_date_time.date }}"
  tags: [always, firth_laravel_app_remove]

- name: Archive {{ flr.name }}
  ansible.builtin.include_tasks: archive.yml
  tags: firth_laravel_app_remove

- name: Stop containers for {{ flr.name }}
  ansible.builtin.include_tasks: containers.yml
  when: flr_ctx.remove.containers
  tags: firth_laravel_app_remove

- name: Remove nginx vhost for {{ flr.name }}
  ansible.builtin.include_tasks: nginx.yml
  when: flr_ctx.remove.nginx
  tags: firth_laravel_app_remove

- name: Remove MySQL for {{ flr.name }}
  ansible.builtin.include_tasks: mysql.yml
  when: flr_ctx.remove.mysql and flr_ctx.mysql | length > 0
  tags: firth_laravel_app_remove

- name: Remove Redis user for {{ flr.name }}
  ansible.builtin.include_tasks: redis.yml
  when: flr_ctx.remove.redis and flr_ctx.redis | length > 0
  tags: firth_laravel_app_remove

- name: Remove workdir for {{ flr.name }}
  ansible.builtin.include_tasks: workdir.yml
  when: flr_ctx.remove.workdir
  tags: firth_laravel_app_remove

- name: Remove system user for {{ flr.name }}
  ansible.builtin.include_tasks: system_user.yml
  when: flr_ctx.remove.system_user
  tags: firth_laravel_app_remove

- name: Remove staging environment for {{ flr.name }}
  ansible.builtin.include_tasks: staging.yml
  when: flr.staging is defined
  tags: firth_laravel_app_remove
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors.

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/tasks/
git commit -m "⚙️ Add main.yml and app.yml orchestration for firth_laravel_app_remove"
```

---

### Task 3: archive.yml

**Files:**
- Create: `roles/firth_laravel_app_remove/tasks/archive.yml`

The most complex task file. Runs unconditionally. Fails if an archive already exists. Creates `/tmp` intermediates, combines them into a final tarball in `docker_root`, then cleans up.

- [ ] **Create tasks/archive.yml**

```yaml
---
- name: Archive {{ flr_ctx.name }}
  tags: firth_laravel_app_remove
  block:
    - name: Check for existing archive of {{ flr_ctx.name }}
      ansible.builtin.stat:
        path: "{{ docker_root }}/{{ flr_ctx.name }}-archive-{{ flr_ctx.archive_date }}.tar.gz"
      register: flr_archive_stat

    - name: Fail if archive already exists for {{ flr_ctx.name }}
      ansible.builtin.fail:
        msg: >
          Archive {{ docker_root }}/{{ flr_ctx.name }}-archive-{{ flr_ctx.archive_date }}.tar.gz
          already exists. Remove it manually before re-running.
      when: flr_archive_stat.stat.exists

    - name: Dump database for {{ flr_ctx.name }}
      ansible.builtin.shell:
        cmd: >
          mysqldump
          -h {{ firth_laravel_app_remove_mysql_login_host }}
          -u {{ firth_laravel_app_remove_mysql_login_user }}
          -p'{{ mysql_root_password }}'
          {{ flr_ctx.mysql.db_name }}
          > /tmp/{{ flr_ctx.name }}-{{ flr_ctx.archive_date }}.sql
      when: flr_ctx.mysql | length > 0
      no_log: true
      changed_when: true

    - name: Copy docker-compose.yml for {{ flr_ctx.name }}
      ansible.builtin.copy:
        src: "{{ docker_root }}/{{ flr_ctx.name }}/docker-compose.yml"
        dest: "/tmp/{{ flr_ctx.name }}-docker-compose-{{ flr_ctx.archive_date }}.yml"
        remote_src: true
        owner: root
        group: root
        mode: "0640"

    - name: Archive storage volume for {{ flr_ctx.name }}
      ansible.builtin.shell:
        cmd: >
          docker run --rm
          -v {{ flr_ctx.name }}_storage:/storage
          alpine
          tar -C /storage -czf - .
          > /tmp/{{ flr_ctx.name }}-storage-{{ flr_ctx.archive_date }}.tar.gz
      changed_when: true

    - name: Set archive file list for {{ flr_ctx.name }}
      ansible.builtin.set_fact:
        flr_archive_files: >-
          {{ flr_ctx.name }}-docker-compose-{{ flr_ctx.archive_date }}.yml
          {{ flr_ctx.name }}-storage-{{ flr_ctx.archive_date }}.tar.gz
          {%- if flr_ctx.mysql | length > 0 %} {{ flr_ctx.name }}-{{ flr_ctx.archive_date }}.sql{% endif %}

    - name: Create archive tarball for {{ flr_ctx.name }}
      ansible.builtin.shell:
        cmd: >
          tar -czf
          {{ docker_root }}/{{ flr_ctx.name }}-archive-{{ flr_ctx.archive_date }}.tar.gz
          -C /tmp {{ flr_archive_files }}
      changed_when: true

    - name: Set ownership on archive for {{ flr_ctx.name }}
      ansible.builtin.file:
        path: "{{ docker_root }}/{{ flr_ctx.name }}-archive-{{ flr_ctx.archive_date }}.tar.gz"
        owner: root
        group: root
        mode: "0640"

    - name: Remove temp files for {{ flr_ctx.name }}
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - "/tmp/{{ flr_ctx.name }}-docker-compose-{{ flr_ctx.archive_date }}.yml"
        - "/tmp/{{ flr_ctx.name }}-storage-{{ flr_ctx.archive_date }}.tar.gz"
        - "/tmp/{{ flr_ctx.name }}-{{ flr_ctx.archive_date }}.sql"

  rescue:
    - name: Debug archive failure for {{ flr_ctx.name }}
      ansible.builtin.debug:
        msg: >
          Failed to archive {{ flr_ctx.name }}.
          Check mysql_root_password, Docker availability, and that
          {{ docker_root }}/{{ flr_ctx.name }}/docker-compose.yml exists.

    - name: Abort after archive failure for {{ flr_ctx.name }}
      ansible.builtin.fail:
        msg: "Cannot continue: archive of {{ flr_ctx.name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors.

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/tasks/archive.yml
git commit -m "⚙️ Add archive.yml for firth_laravel_app_remove"
```

---

### Task 4: containers.yml and workdir.yml

**Files:**
- Create: `roles/firth_laravel_app_remove/tasks/containers.yml`
- Create: `roles/firth_laravel_app_remove/tasks/workdir.yml`

- [ ] **Create tasks/containers.yml**

Checks the working directory exists before attempting `docker compose down --volumes`. Runs as the app system user (matching how the existing role does docker operations).

```yaml
---
- name: Stop containers for {{ flr_ctx.name }}
  tags: firth_laravel_app_remove
  block:
    - name: Check if working directory exists for {{ flr_ctx.name }}
      ansible.builtin.stat:
        path: "{{ docker_root }}/{{ flr_ctx.name }}"
      register: flr_workdir_stat

    - name: Run docker compose down --volumes for {{ flr_ctx.name }}
      ansible.builtin.command:
        cmd: docker compose down --volumes
        chdir: "{{ docker_root }}/{{ flr_ctx.name }}"
      become: true
      become_user: "{{ flr_ctx.name }}"
      when: flr_workdir_stat.stat.exists
      changed_when: true

  rescue:
    - name: Debug containers failure for {{ flr_ctx.name }}
      ansible.builtin.debug:
        msg: "Failed to stop containers for {{ flr_ctx.name }}."

    - name: Abort after containers failure for {{ flr_ctx.name }}
      ansible.builtin.fail:
        msg: "Cannot continue: container teardown for {{ flr_ctx.name }} failed."
```

- [ ] **Create tasks/workdir.yml**

Removes `{{ docker_root }}/{{ flr_ctx.name }}`. When called from `staging.yml`, `flr_ctx.name` is already set to `{{ name }}-staging`, so the same file handles both cases.

```yaml
---
- name: Remove working directory for {{ flr_ctx.name }}
  ansible.builtin.file:
    path: "{{ docker_root }}/{{ flr_ctx.name }}"
    state: absent
  tags: firth_laravel_app_remove
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors.

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/tasks/containers.yml \
        roles/firth_laravel_app_remove/tasks/workdir.yml
git commit -m "⚙️ Add containers.yml and workdir.yml for firth_laravel_app_remove"
```

---

### Task 5: mysql.yml and redis.yml

**Files:**
- Create: `roles/firth_laravel_app_remove/tasks/mysql.yml`
- Create: `roles/firth_laravel_app_remove/tasks/redis.yml`

- [ ] **Create tasks/mysql.yml**

Mirrors `firth_laravel_app/tasks/mysql.yml` but uses `state: absent`.

```yaml
---
- name: Remove MySQL database and user for {{ flr_ctx.name }}
  tags: firth_laravel_app_remove
  block:
    - name: Ensure python3-mysqldb is installed
      ansible.builtin.apt:
        name: python3-mysqldb
        state: present

    - name: Drop database for {{ flr_ctx.name }}
      community.mysql.mysql_db:
        name: "{{ flr_ctx.mysql.db_name }}"
        state: absent
        login_host: "{{ firth_laravel_app_remove_mysql_login_host }}"
        login_user: "{{ firth_laravel_app_remove_mysql_login_user }}"
        login_password: "{{ mysql_root_password }}"

    - name: Drop database user for {{ flr_ctx.name }}
      community.mysql.mysql_user:
        name: "{{ flr_ctx.mysql.db_user }}"
        host: "%"
        state: absent
        login_host: "{{ firth_laravel_app_remove_mysql_login_host }}"
        login_user: "{{ firth_laravel_app_remove_mysql_login_user }}"
        login_password: "{{ mysql_root_password }}"
        column_case_sensitive: true

  rescue:
    - name: Debug MySQL removal failure for {{ flr_ctx.name }}
      ansible.builtin.debug:
        msg: "Failed to remove MySQL database/user for {{ flr_ctx.name }}."

    - name: Abort after MySQL removal failure for {{ flr_ctx.name }}
      ansible.builtin.fail:
        msg: "Cannot continue: MySQL removal for {{ flr_ctx.name }} failed."
```

- [ ] **Create tasks/redis.yml**

Mirrors `firth_laravel_app/tasks/redis.yml` but removes the line instead of adding it.

```yaml
---
- name: Remove Redis ACL user for {{ flr_ctx.name }}
  ansible.builtin.lineinfile:
    path: /etc/redis/users.acl
    regexp: "^user {{ flr_ctx.redis.username | regex_escape }} "
    state: absent
  notify: Reload Redis ACL
  tags: firth_laravel_app_remove
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors.

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/tasks/mysql.yml \
        roles/firth_laravel_app_remove/tasks/redis.yml
git commit -m "⚙️ Add mysql.yml and redis.yml for firth_laravel_app_remove"
```

---

### Task 6: nginx.yml and system_user.yml

**Files:**
- Create: `roles/firth_laravel_app_remove/tasks/nginx.yml`
- Create: `roles/firth_laravel_app_remove/tasks/system_user.yml`

- [ ] **Create tasks/nginx.yml**

Removes the symlink first (sites-enabled), then the config file (sites-available), then reloads nginx. Matches the paths used by `firth_laravel_app/tasks/nginx.yml`.

```yaml
---
- name: Remove nginx vhost for {{ flr_ctx.name }}
  tags: firth_laravel_app_remove
  block:
    - name: Remove nginx sites-enabled symlink for {{ flr_ctx.server_name }}
      ansible.builtin.file:
        path: "/etc/nginx/sites-enabled/{{ flr_ctx.server_name }}.conf"
        state: absent
      notify: Reload Nginx

    - name: Remove nginx sites-available config for {{ flr_ctx.server_name }}
      ansible.builtin.file:
        path: "/etc/nginx/sites-available/{{ flr_ctx.server_name }}.conf"
        state: absent
      notify: Reload Nginx

  rescue:
    - name: Debug nginx removal failure for {{ flr_ctx.name }}
      ansible.builtin.debug:
        msg: "Failed to remove nginx vhost for {{ flr_ctx.server_name }}."

    - name: Abort after nginx removal failure for {{ flr_ctx.name }}
      ansible.builtin.fail:
        msg: "Cannot continue: nginx vhost removal for {{ flr_ctx.name }} failed."
```

- [ ] **Create tasks/system_user.yml**

Removes the system user and its home directory (`/var/lib/{{ flr_ctx.name }}`), including the production/staging symlinks inside it. Only called once per app (not from staging.yml) since production and staging share the same system user.

```yaml
---
- name: Remove system user for {{ flr_ctx.name }}
  tags: firth_laravel_app_remove
  block:
    - name: Remove system user {{ flr_ctx.name }}
      ansible.builtin.user:
        name: "{{ flr_ctx.name }}"
        state: absent
        remove: true
        force: true

  rescue:
    - name: Debug system user removal failure for {{ flr_ctx.name }}
      ansible.builtin.debug:
        msg: "Failed to remove system user {{ flr_ctx.name }}."

    - name: Abort after system user removal failure for {{ flr_ctx.name }}
      ansible.builtin.fail:
        msg: "Cannot continue: system user removal for {{ flr_ctx.name }} failed."
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors.

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/tasks/nginx.yml \
        roles/firth_laravel_app_remove/tasks/system_user.yml
git commit -m "⚙️ Add nginx.yml and system_user.yml for firth_laravel_app_remove"
```

---

### Task 7: staging.yml

**Files:**
- Create: `roles/firth_laravel_app_remove/tasks/staging.yml`

Overrides `flr_ctx` with staging values — `name` becomes `{{ flr.name }}-staging`, staging inherits parent `remove:` flags unless it has its own. Then runs the same subtasks as `app.yml` except `system_user.yml` (the system user is shared between production and staging).

- [ ] **Create tasks/staging.yml**

```yaml
---
- name: Set staging context for {{ flr.name }} # noqa: var-naming[no-role-prefix]
  ansible.builtin.set_fact:
    flr_ctx:
      name: "{{ flr.name }}-staging"
      mysql: "{{ flr.staging.mysql | default({}) }}"
      redis: "{{ flr.staging.redis | default({}) }}"
      server_name: "{{ flr.staging.server_name }}"
      remove: "{{ flr.staging.remove | default(flr.remove) }}"
      archive_date: "{{ ansible_date_time.date }}"
  tags: [always, firth_laravel_app_remove]

- name: Archive {{ flr_ctx.name }}
  ansible.builtin.include_tasks: archive.yml
  tags: firth_laravel_app_remove

- name: Stop containers for {{ flr_ctx.name }}
  ansible.builtin.include_tasks: containers.yml
  when: flr_ctx.remove.containers | default(false)
  tags: firth_laravel_app_remove

- name: Remove nginx vhost for {{ flr_ctx.name }}
  ansible.builtin.include_tasks: nginx.yml
  when: flr_ctx.remove.nginx | default(false)
  tags: firth_laravel_app_remove

- name: Remove MySQL for {{ flr_ctx.name }}
  ansible.builtin.include_tasks: mysql.yml
  when: flr_ctx.remove.mysql | default(false) and flr_ctx.mysql | length > 0
  tags: firth_laravel_app_remove

- name: Remove Redis user for {{ flr_ctx.name }}
  ansible.builtin.include_tasks: redis.yml
  when: flr_ctx.remove.redis | default(false) and flr_ctx.redis | length > 0
  tags: firth_laravel_app_remove

- name: Remove workdir for {{ flr_ctx.name }}
  ansible.builtin.include_tasks: workdir.yml
  when: flr_ctx.remove.workdir | default(false)
  tags: firth_laravel_app_remove
```

- [ ] **Run ansible-lint**

```bash
ansible-lint roles/firth_laravel_app_remove/
```

Expected: no errors.

- [ ] **Commit**

```bash
git add roles/firth_laravel_app_remove/tasks/staging.yml
git commit -m "⚙️ Add staging.yml for firth_laravel_app_remove"
```

---

### Task 8: Wire into playbook.yml and final check

**Files:**
- Modify: `playbook.yml`

- [ ] **Add role to Hello Firth play in playbook.yml**

Add `firth_laravel_app_remove` after `firth_laravel_app`. Since `firth_laravel_app_remove_apps` defaults to `[]`, this is always a no-op unless the host_vars list is populated.

```yaml
    - firth_laravel_app
    - firth_laravel_app_remove
```

- [ ] **Run ansible-lint on the full playbook**

```bash
ansible-lint playbook.yml
```

Expected: no errors.

- [ ] **Verify role structure is complete**

```bash
find roles/firth_laravel_app_remove -name "*.yml" | sort
```

Expected output:
```
roles/firth_laravel_app_remove/defaults/main.yml
roles/firth_laravel_app_remove/meta/main.yml
roles/firth_laravel_app_remove/tasks/app.yml
roles/firth_laravel_app_remove/tasks/archive.yml
roles/firth_laravel_app_remove/tasks/containers.yml
roles/firth_laravel_app_remove/tasks/main.yml
roles/firth_laravel_app_remove/tasks/mysql.yml
roles/firth_laravel_app_remove/tasks/nginx.yml
roles/firth_laravel_app_remove/tasks/redis.yml
roles/firth_laravel_app_remove/tasks/staging.yml
roles/firth_laravel_app_remove/tasks/system_user.yml
roles/firth_laravel_app_remove/tasks/workdir.yml
```

- [ ] **Commit**

```bash
git add playbook.yml
git commit -m "⚙️ Add firth_laravel_app_remove to Hello Firth play"
```

---

## Operator runbook (post-implementation)

Before running against firth:

1. Ensure `laravel_apps_remove.yml` has the correct app name, DB names, Redis username, and server_name.
2. Flip `remove:` flags to `true` for each step you want to run (start conservative — archive-only first).
3. Decrypt and rename `host_vars/firth.water.gkhs.net/laravel/sprouter.vault.yml` → `bloom.vault.yml` with updated variable names (separate manual step).
4. Run: `ansible-playbook playbook.yml --limit firth --tags firth_laravel_app_remove`
5. Verify the archive exists at `{{ docker_root }}/sprouter-archive-YYYY-MM-DD.tar.gz` before proceeding with removal steps.
6. After full teardown, remove the entry from `laravel_apps_remove.yml` and from `laravel_apps.yml`.
