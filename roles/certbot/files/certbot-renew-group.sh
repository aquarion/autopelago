#!/bin/sh
# Renew the given certificates, one `certbot renew` per cert: --cert-name only accepts a
# single value, so a multi-name command would renew just the last one.
# Keeps going after a failure so one broken cert can't stop the rest, and exits non-zero
# if any of them failed so systemd marks the unit as failed.
# Usage: certbot-renew-group CERT_NAME...
rc=0
for cert in "$@"; do
	"${CERTBOT:-/usr/bin/certbot}" renew --quiet --no-random-sleep-on-renew --cert-name "$cert" || rc=1
done
exit "$rc"
