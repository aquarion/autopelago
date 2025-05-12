#!/bin/bash

sudo certbot -n -t certonly --expand --nginx --deploy-hook "service dovecot restart" --cert-name firth.water.gkhs.net \
	--domains firth.water.gkhs.net,istic.net,stream.aquarionics.com,www.aquarionics.com,aquarionics.com,old.aquarionics.com,plex.aquarionics.com,vis.aquarionics.com,panopticon.aquarionics.com,thalium.aquarionics.com,vtt.aquarionics.com,dailyphoto.aquarionics.com,live.dailyphoto.aquarionics.com,feeds.aquarionics.com,wywo.aquarionics.com,factionfiction.net,www.factionfiction.net,idlespeculation.foip.me,herodiaries.foip.me,sevenmirrors.foip.me,istic.co,istic.systems,istic.network,casu.istic.net,wildfeathers.casu.istic.net,pdforums.casu.istic.net,themonthlymoon.com,ludo.istic.co,imperial.istic.net,altru.istic.net,log.istic.net,hol.istic.net,live.art.istic.net,imperial.istic.net,material.istic.net,warehousebasement.com,www.warehousebasement.com,dagon.church,live.dagon.church,wiki.dagon.church,mechan.istic.net,larp.me,www.larp.me,optim.istic.net,www.larpfic.com,larpfic.com,www.lrpfic.com,lrpfic.com,www.iglooteas.com,www.deathuntodarkness.org,deadbadgerdesigns.co.uk,www.deadbadgerdesigns.co.uk

#forums.profounddecisions.co.uk
# www.iglooteas.com,\
# omnyom.com,www.omnyom.com,\
# www.cleartextcontent.co.uk,cleartextcontent.co.uk,\
#nicholasavenell.com,www.nicholasavenell.com,\

# sudo certbot -n -t certonly --expand --nginx --cert-name nicholasavenell.com --domains nicholasavenell.com,www.nicholasavenell.com,nicholasavenell.net,www.nicholasavenell.net

sudo certbot certonly --non-interactive --cert-name socksandpuppets.com --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d socksandpuppets.com,*.socksandpuppets.com --preferred-challenges dns-01
sudo certbot certonly --non-interactive --cert-name aquarionics.com --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d aquarionics.com,*.aquarionics.com --preferred-challenges dns-01

## Istic wildcards

export AWS_PROFILE=istic-r53

sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name istic.net --dns-route53 -d "*.istic.net" -d "*.istic.network" -d "*.istic.systems" -d "*.istic.systems"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name istic.dev --dns-route53 -d "*.istic.dev"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name carcosadreams.com --dns-route53 -d "*.carcosadreams.com" -d "*.carcosadreams.co.uk"
sudo --preserve-env=AWS_PROFILE -E certbot -n certonly --expand --cert-name ludoistic.com --dns-route53 -d "*.ludoistic.com"

## AqCom Wildcards
export AWS_PROFILE=aqcom

sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name nicholasavenell.com -d "*.nicholasavenell.com" -d "*.nicholasavenell.net" -d nicholasavenell.com -d nicholasavenell.net
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name bromioscreations.com -d "*.bromioscreations.com"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name foip.me -d "*.foip.me"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --dns-route53 --cert-name hubris.house -d hubris.house -d "*.hubris.house"
sudo --preserve-env=AWS_PROFILE certbot certonly -n --expand --nginx --cert-name forums.profounddecisions.co.uk -d forums.profounddecisions.co.uk

sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

sudo service nginx reload
