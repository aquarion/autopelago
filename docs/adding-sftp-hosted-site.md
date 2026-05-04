# Adding a new SFTP-hosted site to firth

SFTP-hosted sites let a user upload files over SFTP and have them served as a website with PHP support. Each site gets a PHP-FPM sidecar container that shares the SFTP user's webroot volume; nginx on the host serves static files directly and FastCGI-passes PHP requests to a Unix socket.

kastark.co.uk is the reference implementation for this pattern.

---

## 1. Add the SFTP user

In `host_vars/firth.water.gkhs.net/sftp.yml` (vault-encrypted), add an entry to `firth_sftp_docker_users`:

```yaml
firth_sftp_docker_users:
  - name: example          # becomes the SFTP username and container name suffix
    password: "hashed"     # MD5-crypt hash; generate with:
                           #   echo -n "password" | docker run -i --rm atmoz/makepasswd --crypt-md5 --clearfrom=-
    userid: 1099
    groupid: 1099
    php_web_domain: example.com   # subdirectory under sftp/home/<user>/ served as webroot
                                  # omit entirely for static-only sites (no PHP-FPM container)
```

The `php_web_domain` value must match the directory the user will upload to. The SFTP docker-compose will automatically create a `phpfpm_example` container mounting that path as `/var/www/html`, with a Unix socket at `docker_root/sftp/run/example.sock`.

To use a different PHP version, add `php_image: php:8.2-fpm-alpine` (defaults to `php:8.3-fpm-alpine`).

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
    command: present
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
    command: present
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

The socket path (`sftp/run/example.sock`) and webroot path (`sftp/home/example/example.com`) are both derived from the username and `php_web_domain` — no extra variables needed beyond `docker_root`.

For a static-only site (no `php_web_domain` in the user config), omit the `location ~ \.php$` block and the `try_files` fallback.

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
