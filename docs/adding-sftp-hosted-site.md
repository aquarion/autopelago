# Adding a new SFTP-hosted site to firth

SFTP-hosted sites let a user upload files over SFTP and have them served as a website. Sites needing PHP or working directory listings get a sidecar container that shares the SFTP user's webroot volume — either a PHP-FPM sidecar (nginx serves static files directly and FastCGI-passes PHP requests to a Unix socket) or an Apache sidecar (nginx proxies everything to it; used for static sites needing `mod_autoindex`-style directory listings, since nginx has no equivalent). Purely static sites with no directory-listing needs skip the sidecar entirely.

kastark.co.uk is the reference implementation for the PHP-FPM pattern; socksandpuppets.com is the reference implementation for the Apache pattern.

---

## 1. Add the SFTP user

SFTP accounts (username, password, uid/gid, SSH public key) are managed entirely through Alchemistic — there's an admin flow at `manage.istic.systems` that creates an `sftp_users` row for an existing Alchemistic user, and `sftp-sync.sh` reconciles it into the running container within a minute (no ansible-playbook run needed for the account itself).

If the site needs a web-serving sidecar, add an entry keyed by that same username to `firth_sftp_docker_web_sites` in `host_vars/firth.water.gkhs.net/sftp.vault.yml` (vault-encrypted). Two backends are supported:

```yaml
firth_sftp_docker_web_sites:
  example:
    web_domain: example.com       # subdirectory under sftp/home/<user>/ served as webroot
    backend: fpm                  # default; omit this line for a plain PHP-FPM sidecar
    # php_image: php:8.2-fpm-alpine  # optional, defaults to php:8.3-fpm-alpine
```

Omit the entry entirely for a purely static site with no directory browsing needed (nginx serves it straight from `sftp/home/<user>/` via `root`, no sidecar container at all). For a static site that *does* need working directory listings (e.g. photo/art galleries with no per-directory `index.html`) — nginx has no equivalent for Apache's `.htaccess`-driven `mod_autoindex` (`IndexOptions`, `HeaderName`, `ReadmeName`) — use the `apache` backend instead:

```yaml
firth_sftp_docker_web_sites:
  example:
    web_domain: example.com
    backend: apache
    port: 4081                    # required, must be unique across all apache-backend sites
    # apache_image: httpd:2.4-alpine  # optional
```

`socksandpuppets.com` (ahdok's account) is the reference implementation for the `apache` backend; `kastark.co.uk` is the reference implementation for the default `fpm` backend.

The `web_domain` value must match the directory the user will upload to. This does require an `ansible-playbook` run (see step 5) since it changes the container's docker-compose file:
- `backend: fpm` creates a `phpfpm_example` container mounting that path as `/var/www/html`, with a Unix socket at `docker_root/sftp/run/example.sock`.
- `backend: apache` creates a `web_example` container mounting that path as `/usr/local/apache2/htdocs`, published on `127.0.0.1:<port>` for nginx to `proxy_pass` to (there's no Unix socket for this backend — it speaks plain HTTP).

---

## 2. Add the DNS zone

Create `roles/firth_dns/tasks/zones/example.yml`. Use Route53 (`aws_profile: aqcom`) for `.co.uk` / most domains, or Cloudflare (`cloudflare_api_key`) for domains managed there (see `zones/aquarionics_cf.yml` for the Cloudflare pattern).

Route53 example:

```yaml
---
- name: Example.com.
  amazon.aws.route53_zone:
    state: present
    zone: example.com.
    comment: Example site
    aws_profile: aqcom
  tags:
    - example

- name: Example.com. - A
  amazon.aws.route53:
    overwrite: true
    state: present
    zone: example.com
    record: example.com.
    aws_profile: aqcom
    type: A
    ttl: "300"
    value: "{{ loadbalancer_ip }}"
  tags:
    - example

- name: Www.example.com. - A
  amazon.aws.route53:
    overwrite: true
    state: present
    zone: example.com
    record: www.example.com.
    aws_profile: aqcom
    type: A
    ttl: "300"
    value: "{{ loadbalancer_ip }}"
  tags:
    - example
```

Then include it in `roles/firth_dns/tasks/main.yml`:

```yaml
- name: Update Route53 for example
  ansible.builtin.include_tasks: zones/example.yml
  tags:
    - aws
    - example
```

---

## 3. Add the SSL certificate

Add an entry to the `Configure SSL Config` loop in `roles/firth_nginx/tasks/main.yml`:

```yaml
loop:
  # ... existing entries ...
  - { cert_name: "example.com", file_name: "example" }
```

This generates `/etc/nginx/snippets/ssl/example_ssl.conf` from the `ssl.nginx.conf.j2` template, pointing at the Let's Encrypt cert for `example.com`.

Then add the cert to `bin/generate-firth-certbot.sh`. For Route53-managed domains:

```bash
echo "Generating certificates for example.com"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 \
    --cert-name example.com -d example.com -d www.example.com
```

For Cloudflare-managed domains:

```bash
echo "Generating certificates for example.com"
sudo certbot certonly --non-interactive --cert-name example.com \
    --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
    -d example.com,*.example.com --preferred-challenges dns-01
```

---

## 4. Add the nginx vhost

Create `roles/firth_nginx/templates/vhosts/sftp_example` (the `sftp_` prefix identifies these as SFTP-container-backed sites, consistent with other per-container vhost files like `miscweb`):

```nginx
# {{ ansible_managed }}

server {
  listen 80;
  listen [::]:80;
  server_name example.com www.example.com;
  add_header X-WhyAmI "example redirect";
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl proxy_protocol;
  listen [::]:443 ssl proxy_protocol;
  server_name example.com www.example.com;
  include /etc/nginx/snippets/ssl/example_ssl.conf;

  root {{ docker_root }}/sftp/home/example/example.com;

  error_log /var/log/nginx/example.error.log;
  access_log /var/log/nginx/example.access.log;

  add_header X-WhyAmI example;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    try_files $uri =404;
    fastcgi_pass unix:{{ docker_root }}/sftp/run/example.sock;
    fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
    fastcgi_param QUERY_STRING $query_string;
    include fastcgi_params;
  }

  include /etc/nginx/snippets/errors.conf;
  client_max_body_size 20M;
}
```

The socket path (`sftp/run/example.sock`) and webroot path (`sftp/home/example/example.com`) are both derived from the username and `web_domain` — no extra variables needed beyond `docker_root`.

For a static-only site (no entry for that username in `firth_sftp_docker_web_sites`), omit the `location ~ \.php$` block and the `try_files` fallback.

For an `apache`-backend site (see step 1), skip `root`/`try_files`/`fastcgi_pass` entirely and proxy the whole `location /` to the sidecar's published port instead — see `roles/firth_nginx/templates/vhosts/sftp_socksandpuppets` for the reference implementation:

```nginx
location / {
  proxy_pass http://127.0.0.1:4081;
  include /etc/nginx/snippets/proxy_params.nginx.conf;
}
```

---

## 5. Run the playbook

```bash
# Update DNS
ansible-playbook playbook.yml --tags aws,example

# Generate the certificate (run on firth)
./bin/generate-firth-certbot.sh

# Deploy nginx config and SFTP containers
ansible-playbook playbook.yml --tags nginx,sftp
```
