#!/bin/bash
set -o errexit  # Exit if any line fails
set -o pipefail # Exit if any piped command fails

# Error with a message if a line fails
trap 'echo "Aborting due to an error on $0 line $LINENO. Exit code: $?" >&2' ERR
set -o errtrace #Cascade that to all functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$SCRIPT_DIR/../etc/inventory.ini"

ARCHIVE_PUBLIC_DOMAIN="${ARCHIVE_PUBLIC_DOMAIN:-$(ansible-inventory -i "$INVENTORY" --host atoll.water.gkhs.net 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('stream_delta_archive_public_domain',''))" 2>/dev/null || true)}"

export AWS_PROFILE=istic-r53
echo "Generating certificates for atoll"
sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand --dns-route53 --cert-name atoll.water.gkhs.net --domains atoll.istic.systems,voyuer.istic.net,ws.voyuer.istic.net
echo "Generating certificates for voyeur"
sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand --dns-route53 --cert-name voyeur.istic.net --domains voyeur.istic.net,ws.voyeur.istic.net

if [ -n "${ARCHIVE_PUBLIC_DOMAIN:-}" ]; then
	echo "Generating certificate for archive domain: $ARCHIVE_PUBLIC_DOMAIN"
	sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand --dns-route53 --cert-name "$ARCHIVE_PUBLIC_DOMAIN" --domains "$ARCHIVE_PUBLIC_DOMAIN"
fi

echo "Updating Permissions for Certbot"
sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

echo "Reloading nginx"
sudo service nginx reload
