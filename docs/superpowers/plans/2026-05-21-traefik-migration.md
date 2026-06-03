# Traefik Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-service host-nginx routing with a Traefik reverse proxy that auto-discovers Docker containers, eliminating per-service nginx vhost files and manual port management.

**Architecture:** Traefik runs as a container listening on ports 80/443, auto-discovers Docker services via container labels and the Docker socket. **Cert management stays with certbot** — Traefik reads existing `/etc/letsencrypt/live/` certs via file provider (avoiding the need to consolidate credentials across two AWS accounts and Cloudflare into Traefik's ACME). Non-Docker services (Thalium/PHP-FPM, Jellyfin, PD Discourse) remain behind nginx on an internal port (127.0.0.1:8180), with Traefik routing to them via file provider. Migration is incremental: Traefik starts on an internal port (8889), nginx proxies migrated services to it, then Traefik cuts over to 80/443.

**Tech Stack:** Traefik v3, Docker Compose, Ansible, Let's Encrypt (via existing certbot — not Traefik ACME).

---

## Context: Two Repos

This plan touches two repositories:
- **autopelago** (`/home/aquarion/code/aquarion/autopelago`) — Ansible playbooks and roles
- **docker-config** (`/home/aquarion/code/aquarion/docker-config`) — Docker Compose files for each service

Both need a feature branch before starting.

## Context: DNS Provider Mapping

Most domains are on Route53. Cloudflare manages `aquarionics.com` (partially) and `socksandpuppets.com`. Each Traefik router label will specify its resolver (`cloudflare` or `route53`) based on which provider controls that domain. Services with domains split across both providers need two routers (one per resolver/cert group).

## Context: Non-Docker Services

These cannot be served directly by Traefik and must stay behind nginx:
- **Thalium** (`thalium.aquarionics.com`) — PHP-FPM via unix socket, nginx handles FastCGI
- **Jellyfin** (`vis.aquarionics.com`) — Native apt install, nginx proxies to localhost:8096

During cutover, nginx moves from port 80/443 to 127.0.0.1:8180, and Traefik routes those hostnames to it via file provider.

## Context: PD Discourse (Discourse Launcher)

PD Discourse is managed by [Discourse Launcher](https://github.com/discourse/discourse_docker), not docker-compose. Its config lives in `app.yml` (currently untracked at `/var/discourse/containers/app.yml`). The `pd_discourse` directory is gitignored from docker-config (contains data/uploads, not just config).

For Traefik integration, Discourse runs in "standalone without SSL" mode: `app.yml` uses `web.template.yml` (not `web.ssl.template.yml`), exposes port 7080 on localhost only, and Traefik routes via file provider — the same pattern as Thalium/Jellyfin. The `app.yml` template lives in the new `firth_pddiscourse` Ansible role (not docker-config, since it's not docker-compose). See Task 11a.

IAM credentials for S3 uploads/backups are already managed by the `aws_pdforums` role.

## Context: Out-of-Scope Services

- **Elasticsearch/Kibana** (ports 9200, 5601) — Direct port access only, no nginx vhost, no change needed.
- **VPN/Transmission** (port 9091) — Direct port, not HTTP-proxied, no change needed.

---

## Task 1: Create Feature Branches

**Files:**
- Branch: `feature/traefik-migration` in autopelago
- Branch: `feature/traefik-migration` in docker-config

- [ ] **Step 1: Check current branch in autopelago**

```bash
cd /home/aquarion/code/aquarion/autopelago
git branch --show-current
git status
```
Expected: clean working tree.

- [ ] **Step 2: Create and switch branch in autopelago**

```bash
git checkout main && git pull
git checkout -b feature/traefik-migration
```

- [ ] **Step 3: Create and switch branch in docker-config**

```bash
cd /home/aquarion/code/aquarion/docker-config
git checkout main && git pull
git checkout -b feature/traefik-migration
```

---

## Task 2: Create Traefik Docker Network and Compose Stack

**Files:**
- Create: `docker-config/traefik/docker-compose.yml`

The `traefik` Docker network is external (created once on the host, shared by all stacks). Traefik runs on 127.0.0.1:8888 initially so nginx can keep 80/443 during incremental migration. The final cutover to 80/443 happens in Task 11.

- [ ] **Step 1: Create the compose file**

Create `/home/aquarion/code/aquarion/docker-config/traefik/docker-compose.yml`:

```yaml
name: traefik
services:
  traefik:
    image: traefik:v3
    ports:
      - "127.0.0.1:8888:8888"
      - "127.0.0.1:8889:8889"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /home/docker/traefik/dynamic:/etc/traefik/dynamic:ro
    command:
      - --providers.docker=true
      - --providers.docker.exposedByDefault=false
      - --providers.docker.network=traefik
      - --providers.file.directory=/etc/traefik/dynamic
      - --providers.file.watch=true
      - --entrypoints.web.address=:8888
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.websecure.address=:8889
    networks:
      - traefik
    restart: always
    logging:
      driver: journald
      options:
        tag: '{{.Name}}/{{.ID}}'

networks:
  traefik:
    name: traefik
    external: true
```

No ACME config — certbot continues managing certs. Traefik reads them from `/etc/letsencrypt` (certbot sets `g+r` on these; Traefik runs as root so it can read them). The `/home/docker/traefik/dynamic/` directory is managed by Ansible and contains certs and non-Docker service routing.

- [ ] **Step 2: Validate compose syntax**

```bash
cd /home/aquarion/code/aquarion/docker-config/traefik
docker compose config
```
Expected: rendered config with no errors.

- [ ] **Step 3: Commit in docker-config**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add traefik/docker-compose.yml
git commit -m "🎇 Add Traefik compose stack (internal port, migration phase)"
```

---

## Task 3: Create firth_traefik Ansible Role

**Files:**
- Create: `roles/firth_traefik/tasks/main.yml`
- Create: `roles/firth_traefik/handlers/main.yml`
- Create: `roles/firth_traefik/defaults/main.yml`
- Create: `roles/firth_traefik/templates/dynamic.yml.j2`
- Modify: `host_vars/firth.water.gkhs.net/traefik.yml` (new vault file for credentials)
- Modify: `playbook.yml` (add role after firth_docker)

This role:
1. Creates the `traefik` Docker network
2. Creates `/home/docker/traefik/dynamic/` directory
3. Deploys the Traefik compose stack
4. Renders the file-provider dynamic config (cert list + non-Docker service routing)

No credentials needed — certbot manages cert issuance; Traefik only reads `/etc/letsencrypt`.

- [ ] **Step 1: Create defaults**

Create `roles/firth_traefik/defaults/main.yml`:

```yaml
---
traefik_data_dir: /home/docker/traefik
traefik_compose_dir: /home/aquarion/docker/traefik
```

- [ ] **Step 2: Create handlers**

Create `roles/firth_traefik/handlers/main.yml`:

```yaml
---
- name: Restart Traefik
  community.docker.docker_compose_v2:
    project_src: "{{ traefik_compose_dir }}"
    state: restarted
```

- [ ] **Step 3: Create tasks**

Create `roles/firth_traefik/tasks/main.yml`:

```yaml
---
- name: Create traefik Docker network
  community.docker.docker_network:
    name: traefik
    state: present

- name: Create traefik directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: docker
    mode: "0750"
  loop:
    - "{{ traefik_data_dir }}"
    - "{{ traefik_compose_dir }}"

- name: Copy compose file to host
  ansible.builtin.copy:
    src: "{{ playbook_dir }}/../docker-config/traefik/docker-compose.yml"
    dest: "{{ traefik_compose_dir }}/docker-compose.yml"
    mode: "0644"
  notify:
    - Restart Traefik

- name: Render file-provider dynamic config
  ansible.builtin.template:
    src: dynamic.yml.j2
    dest: "{{ traefik_data_dir }}/dynamic/config.yml"
    mode: "0644"

- name: Start Traefik
  community.docker.docker_compose_v2:
    project_src: "{{ traefik_compose_dir }}"
    state: present
```

- [ ] **Step 4: Create file-provider dynamic config template**

Create `roles/firth_traefik/templates/dynamic.yml.j2`. This lists all existing certbot certs so Traefik can serve them. Cross-reference `bin/generate-firth-certbot.sh` for the full cert name list:

```jinja2
tls:
  certificates:
    # Cloudflare-issued
    - certFile: /etc/letsencrypt/live/aquarionics.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/aquarionics.com/privkey.pem
    - certFile: /etc/letsencrypt/live/socksandpuppets.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/socksandpuppets.com/privkey.pem
    # Route53-issued (istic-r53)
    - certFile: /etc/letsencrypt/live/istic.net/fullchain.pem
      keyFile: /etc/letsencrypt/live/istic.net/privkey.pem
    - certFile: /etc/letsencrypt/live/istic.dev/fullchain.pem
      keyFile: /etc/letsencrypt/live/istic.dev/privkey.pem
    - certFile: /etc/letsencrypt/live/carcosadreams.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/carcosadreams.com/privkey.pem
    - certFile: /etc/letsencrypt/live/ludoistic.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/ludoistic.com/privkey.pem
    - certFile: /etc/letsencrypt/live/nanocountdown.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/nanocountdown.com/privkey.pem
    - certFile: /etc/letsencrypt/live/novelathon.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/novelathon.com/privkey.pem
    # Route53-issued (aqcom)
    - certFile: /etc/letsencrypt/live/nicholasavenell.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/nicholasavenell.com/privkey.pem
    - certFile: /etc/letsencrypt/live/bromioscreations.com/fullchain.pem
      keyFile: /etc/letsencrypt/live/bromioscreations.com/privkey.pem
    - certFile: /etc/letsencrypt/live/foip.me/fullchain.pem
      keyFile: /etc/letsencrypt/live/foip.me/privkey.pem
    - certFile: /etc/letsencrypt/live/larp.me/fullchain.pem
      keyFile: /etc/letsencrypt/live/larp.me/privkey.pem
    - certFile: /etc/letsencrypt/live/camlarp.co.uk/fullchain.pem
      keyFile: /etc/letsencrypt/live/camlarp.co.uk/privkey.pem
    - certFile: /etc/letsencrypt/live/hubris.house/fullchain.pem
      keyFile: /etc/letsencrypt/live/hubris.house/privkey.pem
    - certFile: /etc/letsencrypt/live/kastark.co.uk/fullchain.pem
      keyFile: /etc/letsencrypt/live/kastark.co.uk/privkey.pem
    - certFile: /etc/letsencrypt/live/forums.profounddecisions.co.uk/fullchain.pem
      keyFile: /etc/letsencrypt/live/forums.profounddecisions.co.uk/privkey.pem
    - certFile: /etc/letsencrypt/live/michael.conterio.co.uk/fullchain.pem
      keyFile: /etc/letsencrypt/live/michael.conterio.co.uk/privkey.pem
    # nginx HTTP-challenge (firth.water.gkhs.net multi-domain cert)
    - certFile: /etc/letsencrypt/live/firth.water.gkhs.net/fullchain.pem
      keyFile: /etc/letsencrypt/live/firth.water.gkhs.net/privkey.pem

# Non-Docker service routing. Populated in Task 11.
http:
  routers: {}
  services: {}
```

Verify the actual cert names on the server match before deploying:
```bash
ssh firth.water.gkhs.net 'ls /etc/letsencrypt/live/'
```

- [ ] **Step 5: Add role to playbook.yml after firth_docker**

In `playbook.yml`, in the "Hello Firth" play, add after `firth_docker`:

```yaml
    - firth_traefik
```

- [ ] **Step 6: Lint**

```bash
cd /home/aquarion/code/aquarion/autopelago
ansible-lint roles/firth_traefik/
```
Expected: no errors.

- [ ] **Step 7: Commit in autopelago**

```bash
git add roles/firth_traefik/ playbook.yml
git commit -m "🎇 Add firth_traefik Ansible role"
```

---

## Task 4: Deploy and Verify Traefik Infrastructure

Run the role against firth and verify Traefik starts.

- [ ] **Step 1: Deploy Traefik**

```bash
cd /home/aquarion/code/aquarion/autopelago
ansible-playbook playbook.yml -l firth --tags docker -v
```

- [ ] **Step 2: Verify Traefik container is running**

```bash
ssh firth.water.gkhs.net 'docker ps --filter name=traefik'
```
Expected: traefik container in `Up` state.

- [ ] **Step 3: Verify traefik network exists**

```bash
ssh firth.water.gkhs.net 'docker network inspect traefik'
```
Expected: network present, no containers connected yet.

- [ ] **Step 4: Check Traefik logs for certificate resolver startup**

```bash
ssh firth.water.gkhs.net 'docker logs traefik-traefik-1 2>&1 | tail -20'
```
Expected: no fatal errors, both certificate resolvers (cloudflare, route53) initialised.

---

## Task 5: Migrate WordPress Stack

**Files:**
- Modify: `docker-config/wordpress/docker-compose.yml`
- Modify: `roles/firth_nginx/templates/vhosts/aquarionics`

The wordpress container serves these domains (all Route53 except `blogs.istic.network` domains which are istic/Route53 too, and `aquarionics.com` which splits across CF and Route53). Use two routers: one `cloudflare` resolver for aquarionics.com domains, one `route53` resolver for everything else.

The nginx vhost will be updated to proxy to Traefik on port 8889 (internal HTTPS) for these hostnames; the container's published port 2080 stays until cutover.

- [ ] **Step 1: Update wordpress compose to add labels and traefik network**

Edit `docker-config/wordpress/docker-compose.yml`. Add to the `wordpress` service:

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.wordpress.rule: >-
        Host(`wywo.aquarionics.com`) || Host(`www.aquarionics.com`) ||
        Host(`live.aquarionics.com`) || Host(`feeds.aquarionics.com`) ||
        Host(`blogs.istic.network`) || Host(`herodiaries.foip.me`) ||
        Host(`idlespeculation.foip.me`) || Host(`themonthlymoon.com`) ||
        Host(`factionfiction.net`) || Host(`omnyom.com`) ||
        Host(`www.cleartextcontent.co.uk`) ||
        HostRegexp(`{subdomain:[a-z0-9-]+}.blogs.water.gkhs.net`) ||
        Host(`blogs.water.gkhs.net`)
      traefik.http.routers.wordpress.entrypoints: websecure
      traefik.http.routers.wordpress.tls: "true"
      traefik.http.services.wordpress.loadbalancer.server.port: "80"
```

Traefik selects the correct cert automatically by SNI from the file-provider cert list — no `certresolver` needed since certbot manages issuance.

Add `traefik` to the service networks section:
```yaml
    networks:
      default: null
      traefik:
        external: true
```

Add at the bottom of the file:
```yaml
networks:
  default:
    name: wordpress_default
  traefik:
    name: traefik
    external: true
```

Keep `ports:` unchanged (port 2080 stays for now).

- [ ] **Step 2: Validate compose**

```bash
cd /home/aquarion/code/aquarion/docker-config/wordpress
docker compose config
```
Expected: no errors.

- [ ] **Step 3: Update nginx vhost to proxy via Traefik**

In `roles/firth_nginx/templates/vhosts/aquarionics`, change all `proxy_pass http://container-wordpress;` lines to:
```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $http_host;
```

Remove the `upstream container-wordpress { ... }` block from the top of the file.

- [ ] **Step 4: Run ansible-lint**

```bash
ansible-lint roles/firth_nginx/
```
Expected: no errors.

- [ ] **Step 5: Deploy compose changes on firth**

```bash
ssh firth.water.gkhs.net 'cd /home/aquarion/docker/wordpress && docker compose up -d'
```

- [ ] **Step 6: Deploy nginx changes**

```bash
ansible-playbook playbook.yml -l firth --tags nginx -v
```

- [ ] **Step 7: Verify wordpress responds**

```bash
curl -sk https://www.aquarionics.com -o /dev/null -w '%{http_code}'
```
Expected: 200.

```bash
curl -sk https://factionfiction.net -o /dev/null -w '%{http_code}'
```
Expected: 200.

- [ ] **Step 8: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add wordpress/docker-compose.yml
git commit -m "🔄 Add Traefik labels to wordpress stack"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/aquarionics
git commit -m "🔄 Route wordpress nginx vhost via Traefik"
```

---

## Task 6: Migrate Carcosadreams Stack

**Files:**
- Modify: `docker-config/carcosadreams/docker-compose.yml`
- Modify: `roles/firth_nginx/templates/vhosts/carcosadreams`

Carcosadreams domains are on Route53 (carcosadreams.yml in firth_dns). The nginx vhost has redirects from co.uk → .com which should stay in nginx for now (Traefik can handle redirects via middleware, but not worth doing yet).

- [ ] **Step 1: Update carcosadreams compose**

Add to `docker-config/carcosadreams/docker-compose.yml` service `carcosadreams`:

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.carcosadreams.rule: >-
        Host(`www.carcosadreams.com`) ||
        HostRegexp(`{subdomain:[a-z0-9-]+}.carcosadreams.com`)
      traefik.http.routers.carcosadreams.entrypoints: websecure
      traefik.http.routers.carcosadreams.tls: "true"
      traefik.http.services.carcosadreams.loadbalancer.server.port: "80"
    networks:
      default: null
      traefik:
        external: true
```

Add the networks section to bottom of file:
```yaml
networks:
  default:
    name: carcosadreams_default
  traefik:
    name: traefik
    external: true
```

- [ ] **Step 2: Update nginx vhost**

In `roles/firth_nginx/templates/vhosts/carcosadreams`, remove the `upstream container-carcosadreams { ... }` block and change the two `proxy_pass http://container-carcosadreams;` lines to:
```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $http_host;
```

- [ ] **Step 3: Validate, deploy, verify**

```bash
cd /home/aquarion/code/aquarion/docker-config/carcosadreams
docker compose config

ssh firth.water.gkhs.net 'cd /home/docker/carcosadreams && docker compose up -d'
ansible-playbook playbook.yml -l firth --tags nginx -v

curl -sk https://www.carcosadreams.com -o /dev/null -w '%{http_code}'
```
Expected: 200.

- [ ] **Step 4: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add carcosadreams/docker-compose.yml
git commit -m "🔄 Add Traefik labels to carcosadreams stack"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/carcosadreams
git commit -m "🔄 Route carcosadreams nginx vhost via Traefik"
```

---

## Task 7: Migrate Ludoistic Stack

**Files:**
- Modify: `docker-config/ludoistic/docker-compose.yml`
- Modify: `roles/firth_nginx/templates/vhosts/ludoistic`

Ludoistic domains are on Route53 (ludoistic.yml in firth_dns).

- [ ] **Step 1: Update ludoistic compose**

Note: ludoistic uses `network_mode: bridge` — this must change to use named networks. Remove `network_mode: bridge` and `extra_hosts`, replacing with explicit traefik network (the `host.docker.internal` workaround for MariaDB access needs to move to `WORDPRESS_DB_HOST: 172.17.0.1:3306` or a proper host-gateway entry):

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.ludoistic.rule: >-
        Host(`ludoistic.com`) || Host(`ludoistic.net`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.ludoistic.com`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.ludoistic.net`)
      traefik.http.routers.ludoistic.entrypoints: websecure
      traefik.http.routers.ludoistic.tls: "true"
      traefik.http.services.ludoistic.loadbalancer.server.port: "80"
    extra_hosts:
      - host.docker.internal=host-gateway
    networks:
      default: null
      traefik:
        external: true
```

Add networks block:
```yaml
networks:
  default:
    name: ludoistic_default
  traefik:
    name: traefik
    external: true
```

Remove `network_mode: bridge` line.

- [ ] **Step 2: Update nginx vhost**

In `roles/firth_nginx/templates/vhosts/ludoistic`, remove `upstream container-ludoistic-wordpress { ... }` and change `proxy_pass http://container-ludoistic-wordpress;` to:
```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $http_host;
```

- [ ] **Step 3: Validate, deploy, verify**

```bash
cd /home/aquarion/code/aquarion/docker-config/ludoistic
docker compose config

ssh firth.water.gkhs.net 'cd /home/docker/ludoistic && docker compose up -d'
ansible-playbook playbook.yml -l firth --tags nginx -v

curl -sk https://ludoistic.com -o /dev/null -w '%{http_code}'
```
Expected: 200.

- [ ] **Step 4: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add ludoistic/docker-compose.yml
git commit -m "🔄 Add Traefik labels to ludoistic stack"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/ludoistic
git commit -m "🔄 Route ludoistic nginx vhost via Traefik"
```

---

## Task 8: Migrate Miscweb Stack

**Files:**
- Modify: `docker-config/miscweb/docker-compose.yml`
- Modify: `roles/firth_nginx/templates/vhosts/miscweb`

Miscweb serves the most domains across many wildcard certs. Since Traefik picks certs by SNI automatically, all domains go in one router.

- [ ] **Step 1: Update miscweb compose**

Add to `docker-config/miscweb/docker-compose.yml`:

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.miscweb.rule: >-
        Host(`istic.co`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.istic.net`) || Host(`istic.net`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.istic.dev`) || Host(`istic.dev`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.foip.me`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.hubris.house`) || Host(`hubris.house`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.larp.me`) || Host(`larp.me`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.larp.me.uk`) || Host(`larp.me.uk`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.camlarp.co.uk`) || Host(`camlarp.co.uk`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.nanocountdown.com`) || Host(`nanocountdown.com`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.bromioscreations.com`) || Host(`bromioscreations.com`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.nicholasavenell.com`) || Host(`nicholasavenell.com`) ||
        HostRegexp(`{sub:[a-z0-9-]+}.nicholasavenell.net`) || Host(`nicholasavenell.net`) ||
        Host(`michael.conterio.co.uk`) || Host(`www.michael.conterio.co.uk`) ||
        Host(`deadbadgerdesigns.co.uk`) || Host(`www.deadbadgerdesigns.co.uk`) ||
        Host(`warehousebasement.com`) || Host(`dagon.church`) ||
        Host(`www.deathuntodarkness.org`) || Host(`firth.water.gkhs.net`) ||
        Host(`comicpress.socksandpuppets.com`)
      traefik.http.routers.miscweb.entrypoints: websecure
      traefik.http.routers.miscweb.tls: "true"
      traefik.http.services.miscweb.loadbalancer.server.port: "80"
    networks:
      default: null
      traefik:
        external: true
```

Add networks block:
```yaml
networks:
  default:
    name: miscweb_default
  traefik:
    name: traefik
    external: true
```

- [ ] **Step 2: Update nginx vhost**

In `roles/firth_nginx/templates/vhosts/miscweb`, remove `upstream docker-miscweb { ... }` and replace all `proxy_pass http://docker-miscweb;` lines with:
```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $http_host;
```

- [ ] **Step 3: Validate, deploy, verify**

```bash
cd /home/aquarion/code/aquarion/docker-config/miscweb
docker compose config

ssh firth.water.gkhs.net 'cd /home/docker/miscweb && docker compose up -d'
ansible-playbook playbook.yml -l firth --tags nginx -v

curl -sk https://istic.co -o /dev/null -w '%{http_code}'
curl -sk https://hubris.house -o /dev/null -w '%{http_code}'
```
Expected: 200 for both.

- [ ] **Step 4: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add miscweb/docker-compose.yml
git commit -m "🔄 Add Traefik labels to miscweb stack"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/miscweb
git commit -m "🔄 Route miscweb nginx vhost via Traefik"
```

---

## Task 9: Migrate Jenkins Stack

**Files:**
- Modify: `docker-config/jenkins/docker-compose.yml`
- Modify: `roles/firth_nginx/templates/vhosts/jenkins`

Jenkins is on mechan.istic.net (Route53/istic). Port 50000 (agent JNLP) stays as a direct published port — Traefik only handles the HTTP UI on port 8080.

- [ ] **Step 1: Update jenkins compose**

In `docker-config/jenkins/docker-compose.yml`, keep the port 50000 publish, replace port 6081 with Traefik labels:

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.jenkins.rule: "Host(`mechan.istic.net`)"
      traefik.http.routers.jenkins.entrypoints: websecure
      traefik.http.routers.jenkins.tls: "true"
      traefik.http.services.jenkins.loadbalancer.server.port: "8080"
    ports:
      - mode: ingress
        target: 50000
        published: "50000"
        protocol: tcp
    networks:
      default: null
      traefik:
        external: true
```

Remove the port 6081 publish.

Add networks block:
```yaml
networks:
  default:
    name: jenkins_default
  traefik:
    name: traefik
    external: true
```

- [ ] **Step 2: Update nginx vhost**

In `roles/firth_nginx/templates/vhosts/jenkins`, remove `upstream container-jenkins { ... }` and change `proxy_pass http://container-jenkins;` to:
```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $http_host;
```

- [ ] **Step 3: Validate, deploy, verify**

```bash
cd /home/aquarion/code/aquarion/docker-config/jenkins
docker compose config

ssh firth.water.gkhs.net 'cd /home/docker/jenkins && docker compose up -d'
ansible-playbook playbook.yml -l firth --tags nginx -v

curl -sk https://mechan.istic.net -o /dev/null -w '%{http_code}'
```
Expected: 200 or 403 (Jenkins login page).

- [ ] **Step 4: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add jenkins/docker-compose.yml
git commit -m "🔄 Add Traefik labels to jenkins stack, remove port 6081"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/jenkins
git commit -m "🔄 Route jenkins nginx vhost via Traefik"
```

---

## Task 10: Migrate Foundry VTT Stack

**Files:**
- Modify: `docker-config/foundry/docker-compose.yml`
- Modify: `roles/firth_nginx/templates/vhosts/foundryvtt`

Foundry is already proxy-aware (`FOUNDRY_PROXY_SSL=true`). It's on aquarionics.com (Cloudflare-managed). The container needs to stay aware it's behind HTTPS.

- [ ] **Step 1: Update foundry compose**

In `docker-config/foundry/docker-compose.yml`, add Traefik labels and network. Remove the published port 30000:

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.foundry.rule: "Host(`vtt.aquarionics.com`)"
      traefik.http.routers.foundry.entrypoints: websecure
      traefik.http.routers.foundry.tls: "true"
      traefik.http.services.foundry.loadbalancer.server.port: "30000"
    networks:
      default: null
      traefik:
        external: true
```

Remove the ports section entirely (port 30000 was previously published).

Add networks block:
```yaml
networks:
  default:
    name: foundry_default
  traefik:
    name: traefik
    external: true
```

- [ ] **Step 2: Update nginx vhost**

In `roles/firth_nginx/templates/vhosts/foundryvtt`, change `proxy_pass http://localhost:30000;` to:
```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $host;
```

- [ ] **Step 3: Validate, deploy, verify**

```bash
cd /home/aquarion/code/aquarion/docker-config/foundry
docker compose config

ssh firth.water.gkhs.net 'cd /home/docker/foundry && docker compose up -d'
ansible-playbook playbook.yml -l firth --tags nginx -v

curl -sk https://vtt.aquarionics.com -o /dev/null -w '%{http_code}'
```
Expected: 200 or 302 (Foundry login redirect).

- [ ] **Step 4: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add foundry/docker-compose.yml
git commit -m "🔄 Add Traefik labels to foundry stack, remove direct port"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/foundryvtt
git commit -m "🔄 Route foundry nginx vhost via Traefik"
```

---

## Task 11: Configure Non-Docker Services via File Provider

**Files:**
- Modify: `roles/firth_traefik/templates/dynamic.yml.j2`
- Modify: `roles/firth_nginx/templates/vhosts/thalium` (move to internal port listen)
- Modify: `roles/firth_nginx/templates/vhosts/jellyfin` (move to internal port listen)

Thalium (PHP-FPM/FastCGI) and Jellyfin (native) cannot be served directly by Traefik. They stay on nginx, but nginx moves to listening on `127.0.0.1:8180` instead of 80/443. Traefik's file provider routes their hostnames to `http://127.0.0.1:8180`.

This task prepares both sides but does NOT switch nginx off 80/443 yet — that happens in Task 12.

- [ ] **Step 1: Update firth_nginx to add internal-port server blocks**

In `roles/firth_nginx/templates/vhosts/thalium`, add an additional server block listening on the internal port before the existing blocks:

```nginx
# Internal listen for Traefik passthrough (pre-cutover)
server {
    listen 127.0.0.1:8180;
    server_name thalium.aquarionics.com;
    # Copy of the existing thalium location blocks here (root, PHP-FPM, etc.)
    # ... (same content as existing thalium https server block)
}
```

In `roles/firth_nginx/templates/vhosts/jellyfin`, add:
```nginx
server {
    listen 127.0.0.1:8180;
    server_name vis.aquarionics.com;
    set $jellyfin 127.0.0.1;
    # ... (same proxy locations as existing jellyfin https server block)
}
```

- [ ] **Step 2: Update Traefik file-provider template**

Update `roles/firth_traefik/templates/dynamic.yml.j2`:

```jinja2
http:
  routers:
    thalium:
      rule: "Host(`thalium.aquarionics.com`)"
      entrypoints:
        - websecure
      tls: {}
      service: nginx-internal
    jellyfin:
      rule: "Host(`vis.aquarionics.com`)"
      entrypoints:
        - websecure
      tls: {}
      service: nginx-internal
  services:
    nginx-internal:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8180"
```

`tls: {}` tells Traefik to use TLS with the default store (the certs loaded via the file provider in `dynamic/config.yml`).

- [ ] **Step 3: Deploy both changes**

```bash
ansible-lint roles/firth_nginx/ roles/firth_traefik/
ansible-playbook playbook.yml -l firth --tags nginx -v
ansible-playbook playbook.yml -l firth -v  # deploy traefik role for updated dynamic config
```

- [ ] **Step 4: Verify internal-port nginx works (pre-cutover test)**

```bash
ssh firth.water.gkhs.net 'curl -s -H "Host: thalium.aquarionics.com" http://127.0.0.1:8180/ -o /dev/null -w "%{http_code}"'
```
Expected: 200 or 302.

- [ ] **Step 5: Commit**

```bash
cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/vhosts/thalium roles/firth_nginx/templates/vhosts/jellyfin
git add roles/firth_traefik/templates/dynamic.yml.j2
git commit -m "🔄 Add internal-port nginx blocks and Traefik file-provider routes for Thalium/Jellyfin"
```

---

## Task 11a: Manage PD Discourse app.yml and Add to Traefik

**Files:**
- Create: `roles/firth_pddiscourse/tasks/main.yml`
- Create: `roles/firth_pddiscourse/handlers/main.yml`
- Create: `roles/firth_pddiscourse/templates/app.yml.j2`
- Modify: `host_vars/firth.water.gkhs.net/pddiscourse.yml` (vault file for Discourse secrets)
- Modify: `roles/firth_traefik/templates/dynamic.yml.j2` (add Discourse routers)
- Modify: `playbook.yml` (add firth_pddiscourse to Hello Firth play)

**Before starting this task:** SSH to firth and copy the current app.yml as the starting template:
```bash
ssh firth.water.gkhs.net 'cat /var/discourse/containers/app.yml'
```
Paste the output into `roles/firth_pddiscourse/templates/app.yml.j2` then replace secrets with vault variable references.

- [ ] **Step 1: Create the firth_pddiscourse role structure**

```bash
mkdir -p /home/aquarion/code/aquarion/autopelago/roles/firth_pddiscourse/{tasks,handlers,templates}
```

- [ ] **Step 2: Create handlers**

Create `roles/firth_pddiscourse/handlers/main.yml`:

```yaml
---
- name: Rebuild Discourse
  ansible.builtin.command:
    cmd: /var/discourse/launcher rebuild app
    chdir: /var/discourse
  become: true
```

- [ ] **Step 3: Create tasks**

Create `roles/firth_pddiscourse/tasks/main.yml`:

```yaml
---
- name: Deploy Discourse app.yml
  ansible.builtin.template:
    src: app.yml.j2
    dest: /var/discourse/containers/app.yml
    owner: root
    group: root
    mode: "0640"
  notify:
    - Rebuild Discourse
```

- [ ] **Step 4: Create app.yml template**

Create `roles/firth_pddiscourse/templates/app.yml.j2` based on the existing app.yml from the server (see "Before starting" note above). The critical sections to adjust for Traefik:

The `expose:` section must use localhost-only binding:
```yaml
expose:
  - "127.0.0.1:7080:80"
```

The `templates:` section must NOT include `templates/web.ssl.template.yml`. It should be:
```yaml
templates:
  - "templates/postgres.template.yml"
  - "templates/redis.template.yml"
  - "templates/web.template.yml"
```

Replace any hardcoded secrets with vault variable references. For example:
```yaml
  - "DISCOURSE_SMTP_PASSWORD: {{ discourse_smtp_password }}"
  - "DISCOURSE_S3_SECRET_ACCESS_KEY: {{ discourse_s3_secret_access_key }}"
```

- [ ] **Step 5: Create vault vars file**

Identify which values in the current app.yml are secrets (SMTP password, S3 keys, Redis password, db password, API keys). Create and encrypt:

```bash
cat > /tmp/discourse_vault.yml << 'EOF'
discourse_smtp_password: "FILL_IN"
discourse_s3_access_key_id: "FILL_IN"
discourse_s3_secret_access_key: "FILL_IN"
# add any other secrets found in app.yml
EOF
ansible-vault encrypt /tmp/discourse_vault.yml \
  --output host_vars/firth.water.gkhs.net/pddiscourse.yml
rm /tmp/discourse_vault.yml
ansible-vault edit host_vars/firth.water.gkhs.net/pddiscourse.yml
```

- [ ] **Step 6: Add Discourse to Traefik file-provider template**

Update `roles/firth_traefik/templates/dynamic.yml.j2` to add Discourse routers alongside Thalium/Jellyfin:

```jinja2
    pddiscourse:
      rule: >-
        Host(`pdforums.casu.istic.net`) ||
        Host(`forums.profounddecisions.co.uk`) ||
        Host(`pdforums.larp.me.uk`)
      entrypoints:
        - websecure
      tls: {}
      service: discourse-internal
  services:
    nginx-internal:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8180"
    discourse-internal:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:7080"
```

Note: use `discourse-internal` service (not `nginx-internal`) for the pddiscourse router since Discourse has its own internal HTTP server and doesn't need nginx.

- [ ] **Step 7: Add role to playbook.yml**

In `playbook.yml`, in the "Hello Firth" play, add after `firth_docker`:

```yaml
    - firth_pddiscourse
```

- [ ] **Step 8: Lint**

```bash
ansible-lint roles/firth_pddiscourse/ roles/firth_traefik/
```
Expected: no errors.

- [ ] **Step 9: Update nginx vhost to proxy via Traefik**

In `roles/firth_nginx/templates/vhosts/pddiscourse`, remove `upstream container-pddiscourse { ... }` and change `proxy_pass http://container-pddiscourse;` to:

```nginx
proxy_pass https://127.0.0.1:8889;
proxy_ssl_verify off;
proxy_set_header Host $http_host;
```

- [ ] **Step 10: Deploy**

```bash
ansible-playbook playbook.yml -l firth -v
```

If the `app.yml` changed from what's on the server, this will trigger a Discourse rebuild (takes ~5 minutes — plan for downtime on the forums during this step).

- [ ] **Step 11: Verify Discourse responds**

```bash
curl -sk https://forums.profounddecisions.co.uk -o /dev/null -w '%{http_code}'
```
Expected: 200.

- [ ] **Step 12: Commit**

```bash
cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_pddiscourse/ \
        host_vars/firth.water.gkhs.net/pddiscourse.yml \
        roles/firth_traefik/templates/dynamic.yml.j2 \
        roles/firth_nginx/templates/vhosts/pddiscourse \
        playbook.yml
git commit -m "🎇 Add firth_pddiscourse role: manage app.yml and route via Traefik"
```

---

## Task 12: Cutover — Traefik Takes Ports 80/443

**Files:**
- Modify: `docker-config/traefik/docker-compose.yml`
- Modify: `roles/firth_traefik/tasks/main.yml`
- Modify: `roles/firth_nginx/tasks/main.yml` (stop nginx on 80/443 or change listen)

This is the cutover step. Plan for a short maintenance window (~5 minutes). After this, nginx no longer owns 80/443.

- [ ] **Step 1: Update Traefik compose to bind on 80/443**

In `docker-config/traefik/docker-compose.yml`, change the ports section:

```yaml
    ports:
      - "80:8888"
      - "443:8889"
```

Remove `127.0.0.1:` prefix so it binds on all interfaces.

- [ ] **Step 2: Stop nginx on the host**

Add to `roles/firth_nginx/tasks/main.yml` at the top (before install):

```yaml
- name: Stop nginx before Traefik takes 80/443
  ansible.builtin.service:
    name: nginx
    state: stopped
  tags:
    - nginx_cutover
```

After cutover is verified, this step will be replaced by permanently disabling nginx or moving it to a different port. For now it just stops it so Traefik can bind.

- [ ] **Step 3: Update nginx listen directives to not use 80/443**

In all vhost files that still have `listen 80` or `listen 443`, for the non-Docker service vhosts (thalium, jellyfin) leave only the `127.0.0.1:8180` block. Remove the 80/443 blocks from those files.

For the Docker service vhosts, they can be removed entirely (handled in Task 13 cleanup).

- [ ] **Step 4: Run cutover playbook**

```bash
cd /home/aquarion/code/aquarion/autopelago
# Stop nginx
ansible-playbook playbook.yml -l firth --tags nginx_cutover -v

# Deploy updated Traefik
ssh firth.water.gkhs.net 'cd /home/docker/traefik && docker compose up -d'
```

- [ ] **Step 5: Verify all services respond on real ports**

```bash
curl -s https://www.aquarionics.com -o /dev/null -w '%{http_code}'
curl -s https://ludoistic.com -o /dev/null -w '%{http_code}'
curl -s https://www.carcosadreams.com -o /dev/null -w '%{http_code}'
curl -s https://mechan.istic.net -o /dev/null -w '%{http_code}'
curl -s https://vtt.aquarionics.com -o /dev/null -w '%{http_code}'
curl -s https://thalium.aquarionics.com -o /dev/null -w '%{http_code}'
curl -s https://vis.aquarionics.com -o /dev/null -w '%{http_code}'
```
Expected: all 200 or redirect responses (not connection refused).

- [ ] **Step 6: Commit both repos**

```bash
cd /home/aquarion/code/aquarion/docker-config
git add traefik/docker-compose.yml
git commit -m "🔄 Traefik cutover: bind on 80/443"

cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/
git commit -m "🔄 Traefik cutover: stop nginx on 80/443"
```

---

## Task 13: Cleanup — Remove Old nginx Docker Vhosts

**Files:**
- Delete: `roles/firth_nginx/templates/vhosts/aquarionics`
- Delete: `roles/firth_nginx/templates/vhosts/carcosadreams`
- Delete: `roles/firth_nginx/templates/vhosts/ludoistic`
- Delete: `roles/firth_nginx/templates/vhosts/miscweb`
- Delete: `roles/firth_nginx/templates/vhosts/jenkins`
- Delete: `roles/firth_nginx/templates/vhosts/foundryvtt`
- Move to: `roles/firth_nginx/templates/deleted_vhosts/` for nginx to clean them up from sites-enabled

The firth_nginx role will detect moved files via `deleted_vhosts` and remove their symlinks.

- [ ] **Step 1: Move Docker service vhosts to deleted_vhosts**

```bash
cd /home/aquarion/code/aquarion/autopelago/roles/firth_nginx/templates
mv vhosts/aquarionics deleted_vhosts/
mv vhosts/carcosadreams deleted_vhosts/
mv vhosts/ludoistic deleted_vhosts/
mv vhosts/miscweb deleted_vhosts/
mv vhosts/jenkins deleted_vhosts/
mv vhosts/foundryvtt deleted_vhosts/
```

- [ ] **Step 2: Deploy to remove stale nginx configs**

```bash
ansible-playbook playbook.yml -l firth --tags nginx -v
```

- [ ] **Step 3: Re-verify services still work after cleanup**

```bash
curl -s https://www.aquarionics.com -o /dev/null -w '%{http_code}'
curl -s https://vtt.aquarionics.com -o /dev/null -w '%{http_code}'
curl -s https://thalium.aquarionics.com -o /dev/null -w '%{http_code}'
```
Expected: all 200.

- [ ] **Step 4: Remove published ports from remaining compose files**

In each of the migrated compose files, remove the ports section (or any remaining host-port bindings for port 2080, 3080, 4080, 2180 — they've been replaced by Traefik):

```bash
cd /home/aquarion/code/aquarion/docker-config
# Verify no containers still have unnecessary published ports
ssh firth.water.gkhs.net 'docker ps --format "{{.Names}}: {{.Ports}}"'
```

- [ ] **Step 5: Commit final cleanup**

```bash
cd /home/aquarion/code/aquarion/autopelago
git add roles/firth_nginx/templates/
git commit -m "❌ Remove Docker service nginx vhosts (now managed by Traefik)"
```

---

## Task 14: Open Pull Requests

- [ ] **Step 1: Push and open docker-config PR**

```bash
cd /home/aquarion/code/aquarion/docker-config
git push -u origin feature/traefik-migration
gh pr create --draft --title "Migrate Docker services to Traefik reverse proxy" \
  --body "Adds Traefik labels to all Docker Compose stacks and removes direct port publishing. Part of nginx → Traefik migration. Pair with autopelago PR."
```

- [ ] **Step 2: Push and open autopelago PR**

```bash
cd /home/aquarion/code/aquarion/autopelago
git push -u origin feature/traefik-migration
gh pr create --draft --title "Traefik migration: new role, nginx cleanup, Thalium/Jellyfin via file provider" \
  --body "Adds firth_traefik Ansible role, migrates Docker service nginx vhosts to Traefik routing, moves non-Docker services (Thalium, Jellyfin) to nginx on internal port. Pair with docker-config PR."
```
