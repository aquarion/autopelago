# SFTP Docker Role

An Ansible role that deploys a containerized SFTP server using Docker, with support for multiple chrooted users and SSH key authentication.

## Requirements

- Docker and Docker Compose installed on the target host
- Ansible collections:
  - `community.docker`
  - `ansible.posix`

## Role Variables

### Required Variables

- `docker_root`: Base directory for Docker volumes and configurations (e.g., `/opt/docker`)
- `firth_sftp_docker_users`: List of SFTP users to create

### Optional Variables

- `firth_sftp_docker_user`: System user for running the Docker container (default: `sftp_docker`)
- `firth_sftp_docker_group`: System group for the Docker container (default: `sftp_docker`)
- `firth_sftp_docker_www_data_uid`: Override UID used for `www-data` in containers that share website files (default: host `www-data` UID, fallback `33`)
- `firth_sftp_docker_www_data_gid`: Override GID used for `www-data` in containers that share website files (default: host `www-data` GID, fallback `33`)

### SFTP User Configuration

Each user in `firth_sftp_docker_users` should have the following structure:

```yaml
firth_sftp_docker_users:
  - name: username
    password: "hashed-password"  # pre-hashed (MD5-crypt or SHA-512); omit for key-only
    userid: 1001                 # optional: custom UID for the user
    groupid: 100                 # optional: custom GID for the user
    php_web_domain: example.com  # optional: serve this subdirectory via PHP-FPM
```

SSH public keys are deployed by placing `.pub` files in `files/user_keys.d/<username>.pub` — there is no `ssh_key` field in the user struct.

## Dependencies

This role depends on Docker being installed and configured on the target system. Consider using a Docker installation role before running this role.

## Example Playbook

```yaml
---
- name: Deploy SFTP Docker server
  hosts: sftp_servers
  become: yes
  vars:
    docker_root: /opt/docker
    firth_sftp_docker_users:
      - name: client1
        userid: 2001
        groupid: 2001
      - name: client2
        userid: 2002
        groupid: 2002
  roles:
    - firth-sftp-docker
```

Place SSH public keys in `files/user_keys.d/client1.pub`, `files/user_keys.d/client2.pub`, etc.

## Directory Structure

The role creates the following directory structure:

```text
{{ docker_root }}/sftp/
├── docker-compose.yml
├── etc/
│   └── users.conf
├── keys/
│   ├── ssh_host_rsa_key
│   ├── ssh_host_rsa_key.pub
│   └── ... (other host keys)
├── bin/
│   └── bind_mounts.sh
└── home/
    ├── client1/
    │   └── .ssh/
    │       └── authorized_keys
    └── client2/
        └── .ssh/
            └── authorized_keys
```

## Security Features

- Users are chrooted to their home directories
- SSH key and/or password authentication (password field accepts a pre-hashed MD5-crypt or SHA-512 value)
- Dedicated system user runs the container
- Proper file permissions and ownership
- Per-user home roots are reconciled to each user UID/GID during sync so content under `username/` stays user-owned
- SSH host key persistence across container restarts

## Testing

Run the included test playbook:

```bash
ansible-playbook roles/firth_sftp_docker/tests/test.yml
```

## License

MIT

## Author Information

Created for the Autopelago infrastructure management system.
