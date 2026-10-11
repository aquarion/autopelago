#!/bin/sh
# {{ ansible_managed }}
# Run by certbot after any certificate is issued or renewed.
set -e
{% for cmd in certbot_deploy_commands %}
{{ cmd }}
{% endfor %}
