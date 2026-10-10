#!/bin/bash
set -o errexit  # Exit if any line fails
set -o pipefail # Exit if any piped command fails

# Error with a message if a line fails
trap 'echo "Aborting due to an error on $0 line $LINENO. Exit code: $?" >&2' ERR
set -o errtrace #Cascade that to all functions

# Run by certbot after each cert is issued (and saved in that cert's renewal config,
# so timer-driven renewals reload services too).
CERTBOT_DEPLOY_HOOK="service nginx reload; service dovecot restart"

###### Certbot Helper Functions ######
## Copy-pasted into each generate-*-certbot.sh: update-all-certbots.sh pipes each script
## over ssh stdin, so they can't source a shared file. Keep this block identical in all
## of them (diff them after editing). Needs CERTBOT_DEPLOY_HOOK set by the calling script.

function cloudflare_certbot() {
	# Usage: cloudflare_certbot primary [extra_domain...]
	# Always requests primary + *.primary, plus any extras.
	local primary_domain=$1
	local domain_args=()
	local d
	for d in "$primary_domain" "*.$primary_domain" "${@:2}"; do domain_args+=(-d "$d"); done
	echo "Generating certificates for $primary_domain"
	sudo certbot certonly --non-interactive --expand --cert-name "$primary_domain" --deploy-hook "${CERTBOT_DEPLOY_HOOK:?CERTBOT_DEPLOY_HOOK must be set}" --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini "${domain_args[@]}" --preferred-challenges dns-01
}

function route53_certbot() {
	# Usage: route53_certbot profile primary [cert_name [extra_domain...]]
	# With no extra domains, requests primary + *.primary. With extras, requests
	# primary + extras only, so list any wildcard you want explicitly.
	# Exports AWS_PROFILE for the rest of the calling script.
	local aws_profile=$1
	local primary_domain=$2
	local cert_name=${3:-$primary_domain}
	local domain_list=("$primary_domain" "${@:4}")
	if [ $# -lt 4 ]; then domain_list+=("*.$primary_domain"); fi
	local domain_args=()
	local d
	for d in "${domain_list[@]}"; do domain_args+=(-d "$d"); done
	echo "Generating certificates for $primary_domain"
	export AWS_PROFILE="$aws_profile"
	sudo --preserve-env=AWS_PROFILE -E certbot certonly --non-interactive --expand --cert-name "$cert_name" --deploy-hook "${CERTBOT_DEPLOY_HOOK:?CERTBOT_DEPLOY_HOOK must be set}" --dns-route53 "${domain_args[@]}" --preferred-challenges dns-01
}

function nginx_certbot() {
	# Usage: nginx_certbot primary [cert_name [extra_domain...]]
	# Requests primary + extras only. No wildcards: http-01 can't validate them.
	local primary_domain=$1
	local cert_name=${2:-$primary_domain}
	local domain_args=()
	local d
	for d in "$primary_domain" "${@:3}"; do domain_args+=(-d "$d"); done
	echo "Generating certificates for $primary_domain"
	sudo certbot certonly --non-interactive --expand --cert-name "$cert_name" --deploy-hook "${CERTBOT_DEPLOY_HOOK:?CERTBOT_DEPLOY_HOOK must be set}" --nginx "${domain_args[@]}" --preferred-challenges http-01
}
#### End Certbot Helper Functions ####

#### Generate Certificates ####

nginx_certbot "firth.water.gkhs.net" "firth.water.gkhs.net" \
	"istic.net" \
	"factionfiction.net" \
	"www.factionfiction.net" \
	"themonthlymoon.com" \
	"ludo.istic.co" \
	"imperial.istic.net" \
	"altru.istic.net" \
	"log.istic.net" \
	"hol.istic.net" \
	"live.art.istic.net" \
	"material.istic.net" \
	"istic.co" \
	"warehousebasement.com" \
	"www.warehousebasement.com" \
	"dagon.church" \
	"live.dagon.church" \
	"wiki.dagon.church" \
	"mechan.istic.net" \
	"optim.istic.net" \
	"www.larpfic.com" \
	"larpfic.com" \
	"www.lrpfic.com" \
	"lrpfic.com" \
	"www.deathuntodarkness.org" \
	"deadbadgerdesigns.co.uk" \
	"www.deadbadgerdesigns.co.uk" \
	"live.dailyphoto.aquarionics.com"

# Cloudflare-hosted zones (istic.dev moved here from Route53)
cloudflare_certbot "socksandpuppets.com"
cloudflare_certbot "aquarionics.com"
cloudflare_certbot "novelathon.com"
cloudflare_certbot "istic.dev"

## Istic wildcards

export AWS_PROFILE=istic-r53
route53_certbot "istic-r53" "istic.net" "istic.net" "*.istic.net" "istic.network" "*.istic.network" "*.blogs.istic.network" "istic.systems" "*.istic.systems"
route53_certbot "istic-r53" "svc.istic.systems" "svc.istic.systems" "*.svc.istic.systems"

route53_certbot "istic-r53" "carcosadreams.com" "carcosadreams.com" "*.carcosadreams.com" "*.carcosadreams.co.uk"
route53_certbot "istic-r53" "ludoistic.com" "ludoistic.com" "*.ludoistic.com"
route53_certbot "istic-r53" "nanocountdown.com" "nanocountdown.com" "*.nanocountdown.com"
route53_certbot "istic-r53" "bloomfeed.app" "bloomfeed.app" "*.bloomfeed.app"

## AqCom Wildcards
export AWS_PROFILE=aqcom

route53_certbot "aqcom" "nicholasavenell.com" "nicholasavenell.com" "*.nicholasavenell.com" "*.nicholasavenell.net" "nicholasavenell.net"
route53_certbot "aqcom" "bromioscreations.com" "bromioscreations.com" "*.bromioscreations.com"
route53_certbot "aqcom" "larp.me" "larp.me" "*.larp.me" "larp.me.uk" "*.larp.me.uk"
route53_certbot "aqcom" "camlarp.co.uk" "camlarp.co.uk" "*.camlarp.co.uk"
# DNS-01 on purpose (not nginx): the live cert includes *.hubris.house
route53_certbot "aqcom" "hubris.house"
nginx_certbot "forums.profounddecisions.co.uk"
nginx_certbot "michael.conterio.co.uk" "michael.conterio.co.uk" "www.michael.conterio.co.uk" "conterio.co.uk" "www.conterio.co.uk"
route53_certbot "aqcom" "kastark.co.uk" "kastark.co.uk" "www.kastark.co.uk" "dhmstark.co.uk" "www.dhmstark.co.uk"

## Set permissions for Let's Encrypt files, so nginx & dovecot can access them properly
echo "Setting permissions for /etc/letsencrypt"
sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;
