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
- `sftp_users`: List of SFTP users to create

### Optional Variables

- `sftp_docker_user`: System user for running the Docker container (default: `sftp_docker`)
- `sftp_docker_group`: System group for the Docker container (default: `sftp_docker`)

### SFTP User Configuration

Each user in `sftp_users` should have the following structure:

```yaml
sftp_users:
  - name: username
    ssh_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbq... user@domain.com"
    uid: 1001 # Optional: custom UID for the user
    gid: 100 # Optional: custom GID for the user
```

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
    sftp_users:
      - name: client1
        ssh_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbq... client1@company.com"
        uid: 2001
        gid: 2001
      - name: client2
        ssh_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD8xyz... client2@company.com"
        uid: 2002
        gid: 2002
  roles:
    - firth-sftp-docker
```

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
- SSH key-only authentication (no passwords)
- Dedicated system user runs the container
- Proper file permissions and ownership
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
