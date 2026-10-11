#!/bin/sh
# {{ ansible_managed }}
# Run by certbot after a renewal of an existing certificate.
# Every command runs even if an earlier one fails; the exit status reports any failure.
rc=0
{% for cmd in certbot_deploy_commands %}
{{ cmd }} || rc=$?
{% endfor %}
exit $rc
