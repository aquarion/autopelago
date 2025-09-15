#!/bin/bash
set -o errexit  # Exit if any line fails
set -o pipefail # Exit if any piped command fails

# Error with a message if a line fails
trap 'echo "Aborting due to an error on $0 line $LINENO. Exit code: $?" >&2' ERR
set -o errtrace #Cascade that to all functions


echo "Generating certificates for firth"
sudo certbot -n -t certonly --expand --nginx --deploy-hook "service dovecot restart" --cert-name firth.water.gkhs.net \
	--domains firth.water.gkhs.net,\
		-d "istic.net" \
		-d "stream.aquarionics.com,www.aquarionics.com,aquarionics.com,old.aquarionics.com,plex.aquarionics.com,vis.aquarionics.com,panopticon.aquarionics.com,thalium.aquarionics.com,vtt.aquarionics.com,flix.aquarionics.com,dailyphoto.aquarionics.com,live.dailyphoto.aquarionics.com,feeds.aquarionics.com,wywo.aquarionics.com" \
		-d "factionfiction.net,www.factionfiction.net" \
		-d "idlespeculation.foip.me,herodiaries.foip.me,sevenmirrors.foip.me,istic.co" \
		-d "themonthlymoon.com" \
		-d "ludo.istic.co,imperial.istic.net,altru.istic.net,log.istic.net,hol.istic.net,live.art.istic.net,imperial.istic.net,material.istic.net" \
		-d "warehousebasement.com,www.warehousebasement.com" \
		-d "dagon.church,live.dagon.church,wiki.dagon.church" \
		-d "mechan.istic.net,optim.istic.net" \
		-d "www.larpfic.com,larpfic.com,www.lrpfic.com,lrpfic.com" \
		-d "iglooteas.com,www.iglooteas.com" \
		-d "deathuntodarkness.org,www.deathuntodarkness.org" \
		-d "deadbadgerdesigns.co.uk,www.deadbadgerdesigns.co.uk"

#forums.profounddecisions.co.uk
# www.iglooteas.com,\
# omnyom.com,www.omnyom.com,\
# www.cleartextcontent.co.uk,cleartextcontent.co.uk,\
#nicholasavenell.com,www.nicholasavenell.com,\

# sudo certbot -n -t certonly --expand --nginx --cert-name nicholasavenell.com --domains nicholasavenell.com,www.nicholasavenell.com,nicholasavenell.net,www.nicholasavenell.net

echo "Generating certificates for Socks & Puppets"
sudo certbot certonly --non-interactive --cert-name socksandpuppets.com --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d socksandpuppets.com,*.socksandpuppets.com --preferred-challenges dns-01
echo "Generating certificates for Aquarionics"
sudo certbot certonly --non-interactive --cert-name aquarionics.com --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d aquarionics.com,*.aquarionics.com --preferred-challenges dns-01

## Istic wildcards

export AWS_PROFILE=istic-r53
echo "Generating certificates for istic"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name istic.net --dns-route53 \
	-d "istic.net" -d "*.istic.net" \
	-d "istic.network" -d "*.istic.network" \
	-d "*.blogs.istic.network" \
	-d "*.istic.systems" -d "*.istic.systems"
echo "Generating certificates for istic.dev"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name istic.dev --dns-route53 -d "*.istic.dev"
echo "Generating certificates for Carcosa Dreams"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name carcosadreams.com --dns-route53 -d "*.carcosadreams.com" -d "*.carcosadreams.co.uk"
echo "Generating certificates for ludoistic"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name ludoistic.com --dns-route53 -d "ludoistic.com" -d "*.ludoistic.com"
echo "Generating certificates for nanocountdown"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name nanocountdown.com --dns-route53 -d nanocountdown.com -d "*.nanocountdown.com"
echo "Generating certificates for novelathon"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name novelathon.com --dns-route53 -d novelathon.com -d "*.novelathon.com"

## AqCom Wildcards
export AWS_PROFILE=aqcom

echo "Generating certificates for nicholasavenell.com"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name nicholasavenell.com -d "*.nicholasavenell.com" -d "*.nicholasavenell.net" -d nicholasavenell.com -d nicholasavenell.net
echo "Generating certificates for bromioscreations.com"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name bromioscreations.com -d "*.bromioscreations.com"
echo "Generating certificates for foip.me"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name foip.me -d "*.foip.me"
echo "Generating certificates for larp.me"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name larp.me -d "larp.me" -d "*.larp.me" -d "larp.me.uk" -d "*.larp.me.uk"
echo "Generating certificates for camlarp"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name camlarp.co.uk -d "camlarp.co.uk" -d "*.camlarp.co.uk"
echo "Generating certificates for hubris.house"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --nginx --cert-name hubris.house -d hubris.house -d "*.hubris.house"
echo "Generating certificates for forums.profounddecisions.co.uk"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --nginx --cert-name forums.profounddecisions.co.uk -d forums.profounddecisions.co.uk

echo "Setting permissions for /etc/letsencrypt"
sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

echo "Reloading nginx"
sudo service nginx reload
