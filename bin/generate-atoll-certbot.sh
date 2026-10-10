#!/bin/bash
set -o errexit  # Exit if any line fails
set -o pipefail # Exit if any piped command fails

# Error with a message if a line fails
trap 'echo "Aborting due to an error on $0 line $LINENO. Exit code: $?" >&2' ERR
set -o errtrace #Cascade that to all functions

###### Certbot Helper Functions ######
## Sync these to the other certbot helper scripts when you change them ##
## Last updated: 2026-10-11

function cloudflare_certbot() {
	local primary_domain=$1
	# Usage: cloudflare_certbot primary [extra_domain...]  (wildcard for primary is always included)
	local domain_args=()
	local d
	for d in "$primary_domain" "*.$primary_domain" "${@:2}"; do domain_args+=(-d "$d"); done
	echo "Generating certificates for $primary_domain"
	sudo certbot certonly --non-interactive --expand --cert-name "$primary_domain" --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini "${domain_args[@]}" --preferred-challenges dns-01
}

function route53_certbot() {
	local aws_profile=$1
	local primary_domain=$2
	local cert_name=${3:-$primary_domain}
	# Usage: route53_certbot profile primary [cert_name [extra_domain...]]
	# With no extra domains, requests primary + *.primary.
	local domain_list=("$primary_domain" "${@:4}")
	if [ $# -lt 4 ]; then domain_list+=("*.$primary_domain"); fi
	local domain_args=()
	local d
	for d in "${domain_list[@]}"; do domain_args+=(-d "$d"); done
	echo "Generating certificates for $primary_domain"
	export AWS_PROFILE="$aws_profile"
	sudo --preserve-env=AWS_PROFILE -E certbot certonly --non-interactive --expand --cert-name "$cert_name" --dns-route53 "${domain_args[@]}" --preferred-challenges dns-01
}

function nginx_certbot() {
	local primary_domain=$1
	local cert_name=${2:-$primary_domain}
	# Usage: nginx_certbot primary [cert_name [extra_domain...]]
	# No wildcard: http-01 can't validate them.
	local domain_args=()
	local d
	for d in "$primary_domain" "${@:3}"; do domain_args+=(-d "$d"); done
	echo "Generating certificates for $primary_domain"
	sudo certbot certonly --non-interactive --expand --cert-name "$cert_name" --nginx "${domain_args[@]}" --preferred-challenges http-01
}
#### End Certbot Helper Functions ####

# Checksums of every live cert, so we only reload services if something changed
function cert_fingerprint() {
	sudo find /etc/letsencrypt/live -name fullchain.pem -exec sha256sum {} + | sort
}
CERTS_BEFORE=$(cert_fingerprint)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$SCRIPT_DIR/../etc/inventory.ini"

get_host_var() {
	local host="$1"
	local var="$2"
	ansible-inventory -i "$INVENTORY" --host "$host" 2>/dev/null |
		jq -r --arg v "$var" '.[$v] // ""' 2>/dev/null ||
		true
}

ARCHIVE_PUBLIC_DOMAIN="${ARCHIVE_PUBLIC_DOMAIN:-$(get_host_var atoll.water.gkhs.net stream_delta_archive_public_domain)}"

# nginx_certbot "atoll.water.gkhs.net" "atoll.water.gkhs.net" "*.atoll.water.gkhs.net"
route53_certbot "istic-r53" "voyeur.istic.net" "voyeur.istic.net" "*.voyeur.istic.net" "*.ws.voyeur.istic.net"
cloudflare_certbot "voyeur.istic.dev" "*.ws.voyeur.istic.dev"

# sudo certbot certonly --non-interactive --expand --cert-name "voyeur.istic.dev" --dns-cloudflare --dns-cloudflare-credentials "/root/.secrets/cloudflare.ini" --domains "voyeur.istic.dev" --domains "*.voyeur.istic.dev" --domains "ws.voyeur.istic.dev" --domains "*.ws.voyeur.istic.dev"

if [ -n "${ARCHIVE_PUBLIC_DOMAIN:-}" ]; then
	echo "Generating certificate for archive domain: $ARCHIVE_PUBLIC_DOMAIN"
	nginx_certbot "$ARCHIVE_PUBLIC_DOMAIN" "$ARCHIVE_PUBLIC_DOMAIN"
else
	echo "No archive public domain specified, skipping certificate generation for archive." >/dev/stderr
fi

echo "Updating Permissions for Certbot"
sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

if [ "$CERTS_BEFORE" != "$(cert_fingerprint)" ]; then
	echo "Certbot detected changes, reloading nginx."
	sudo service nginx reload
else
	echo "No changes detected by Certbot."
fi
