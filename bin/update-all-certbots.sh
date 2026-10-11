#!/bin/bash
set -o errexit
set -o pipefail

# The generate-*-certbot.sh scripts run on the remote host over ssh, where there is no
# repo or inventory, so anything needing ansible vars is resolved here and passed in.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Fails loudly if ansible-inventory/jq break; empty only if the var is genuinely unset.
ARCHIVE_PUBLIC_DOMAIN="${ARCHIVE_PUBLIC_DOMAIN:-$(ansible-inventory --host atoll.water.gkhs.net | jq -r '.stream_delta_archive_public_domain // ""')}"

for host in firth atoll; do
	echo "Updating certbot on $host.istic.systems"
	# Only generate-atoll-certbot.sh reads ARCHIVE_PUBLIC_DOMAIN; it's harmless for firth.
	cat bin/generate-$host-certbot.sh | ssh -A $host.istic.systems "ARCHIVE_PUBLIC_DOMAIN=$(printf '%q' "$ARCHIVE_PUBLIC_DOMAIN") bash -s" 2>&1 | ts "[$host:%T]" &
done

wait
