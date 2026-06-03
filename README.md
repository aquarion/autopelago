# Autopelago

Ansible automation for my server network.

Started as scripts to manage a single public server, it's expanded to cover two servers (firth and atoll), DNS, Docker services, Laravel app deployments, media automation, and shared infrastructure like MySQL, Redis, nginx, and email.

It's also an experiment in working in public — this repository is open despite containing detailed information about how the servers are set up. Secrets are encrypted with Ansible Vault.

Some roles could probably be spun out as standalone projects, but I'm not willing to take on the maintenance burden, and part of the reason some of them exist is because others have rolled their own solutions without genericising them. I'm not keen to make that situation worse. Feel free to use these as a basis for your own setup.

## Structure

Roles follow the naming convention `{hostname}_{job}` for host-specific roles and `water_gkhs_{job}` for roles that apply across the host group.

Host variables live in `host_vars/{hostname}/`, with vault-encrypted files using the `.vault.yml` suffix. Per-service vault files are grouped into subdirectories (e.g. `host_vars/firth.water.gkhs.net/laravel/`).

## Key roles

- **`firth_laravel_app`** — parametric role that deploys Laravel apps as Docker containers. Handles system user creation, MySQL/Redis provisioning, GHCR authentication, nginx vhosts, GitHub Actions deploy key upload, and optional staging environments. See [`docs/adding-laravel-app.md`](docs/adding-laravel-app.md).
- **`firth_nginx`** — nginx vhosts and SSL config for services on firth
- **`firth_sftp_docker`** — SFTP-hosted sites with PHP-FPM sidecars. See [`docs/adding-sftp-hosted-site.md`](docs/adding-sftp-hosted-site.md).
- **`firth_dns`** — Route53 and Cloudflare DNS management
- **`stream_delta`** — media automation (Flexget, Filebot, etc.)
- **`water_gkhs_*`** — shared infrastructure across all servers

## Docs

- [Adding a Laravel app](docs/adding-laravel-app.md)
- [Adding an SFTP-hosted site](docs/adding-sftp-hosted-site.md)
