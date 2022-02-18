#!/bin/bash

sudo certbot -n -t certonly --expand --nginx --cert-name firth.water.gkhs.net --domains firth.water.gkhs.net,\
istic.net,\
stream.aquarionics.com,www.aquarionics.com,aquarionics.com,old.aquarionics.com,plex.aquarionics.com,vis.aquarionics.com,panopticon.aquarionics.com,thalium.aquarionics.com,wiki.aquarionics.com,\
wywo.aquarionics.com,\
factionfiction.net,www.factionfiction.net,\
idlespeculation.foip.me,\
herodiaries.foip.me,\
sevenmirrors.foip.me,\
istic.co,istic.systems,istic.network,\
casu.istic.net,wildfeathers.casu.istic.net,pdforums.casu.istic.net,\
themonthlymoon.com,\
ludo.istic.co,ludoistic.com,www.ludoistic.com,\
imperial.istic.net,altru.istic.net,log.istic.net,hol.istic.net,\
live.art.istic.net,imperial.istic.net,material.istic.net,\
warehousebasement.com,www.warehousebasement.com,\
dagon.church,live.dagon.church,wiki.dagon.church,\
mechan.istic.net,\
larp.me,api.larp.me,staging.larp.me,api.staging.larp.me,locations.larp.me,www.larp.me,\
optim.istic.net,\
www.larpfic.com,larpfic.com,www.lrpfic.com,lrpfic.com,\
www.deathuntodarkness.org
#forums.profounddecisions.co.uk
#www.iglooteas.com,\
# www.iglooteas.com,\
# omnyom.com,www.omnyom.com,\
# www.cleartextcontent.co.uk,cleartextcontent.co.uk,\
#nicholasavenell.com,www.nicholasavenell.com,\

sudo certbot -n -t certonly --expand --nginx --cert-name nicholasavenell.com --domains nicholasavenell.com,www.nicholasavenell.com

## Istic wildcards

AWS_PROFILE=istic-r53 sudo -E certbot -n certonly --expand --cert-name istic.net --dns-route53 -d *.istic.net
AWS_PROFILE=istic-r53 sudo -E certbot -n certonly --expand --cert-name carcosadreams.com --dns-route53 -d *.carcosadreams.com -d *.carcosadreams.co.uk

## AqCom Wildcards

sudo certbot certonly -n --expand --dns-route53 --cert-name bromioscreations.com -d *.bromioscreations.com
sudo certbot certonly -n --expand --dns-route53 --cert-name foip.me -d *.foip.me
sudo certbot certonly -n --expand --dns-route53 --cert-name hubris.house -d hubris.house -d *.hubris.house
sudo certbot certonly -n --expand --nginx --cert-name forums.profounddecisions.co.uk -d forums.profounddecisions.co.uk 

sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

sudo service nginx reload