#!/bin/bash

sudo certbot -t certonly --expand --standalone --pre-hook "service nginx stop" --post-hook "service nginx start" --domains \
 archipelago.water.gkhs.net,\
istic.net,\
stream.aquarionics.com,aquarionics.blogs.water.gkhs.net,www.aquarionics.com,aquarionics.com,old.aquarionics.com,plex.aquarionics.com,vis.aquarionics.com,\
wywo.blogs.water.gkhs.net,wywo.aquarionics.com,\
factionfiction.net,www.factionfiction.net,factionfiction.blogs.water.gkhs.net,\
cleartextcontent.blogs.water.gkhs.net,www.cleartextcontent.co.uk,cleartextcontent.co.uk,\
idlespeculation.blogs.water.gkhs.net,idlespeculation.foip.me,\
herodiaries.blogs.water.gkhs.net,herodiaries.foip.me,\
sevenmirrors.foip.me,\
istic.blogs.water.gkhs.net,istic.co,istic.systems,istic.network,\
casu.istic.net,wildfeathers.casu.istic.net,pdforums.casu.istic.net,\
monthlymoon.blogs.water.gkhs.net,themonthlymoon.com,\
blogs.water.gkhs.net,\
ludo.istic.co,ludoistic.com,www.ludoistic.com,\
imperial.istic.net,altru.istic.net,log.istic.net,hol.istic.net,\
live.art.istic.net,imperial.istic.net,material.istic.net,\
warehousebasement.com,www.warehousebasement.com,\
dagon.church,live.dagon.church,wiki.dagon.church,\
mechan.istic.net,\
www.iglooteas.com,iglooteas.com,\
larp.me,api.larp.me,staging.larp.me,api.staging.larp.me,locations.larp.me,www.larp.me,\
optim.istic.net,\
www.larpfic.com,larpfic.com,www.lrpfic.com,lrpfic.com,\
www.deathuntodarkness.org,\
forums.profounddecisions.co.uk
# www.iglooteas.com,iglooteas.blogs.water.gkhs.net,\
# omnyom.blogs.water.gkhs.net,omnyom.com,www.omnyom.com,\


## Istic wildcards

AWS_PROFILE=istic-r53 sudo -E certbot certonly --expand --dns-route53 -d *.istic.net && sudo service nginx restart
AWS_PROFILE=istic-r53 sudo -E certbot certonly --expand --dns-route53 -d *.carcosadreams.com -d *.carcosadreams.co.uk && sudo service nginx restart

## AqCom Wildcards

sudo certbot certonly --expand --dns-route53 -d *.foip.me && sudo service nginx restart
sudo certbot certonly --expand --dns-route53 -d hubris.house -d *.hubris.house && sudo service nginx restart
