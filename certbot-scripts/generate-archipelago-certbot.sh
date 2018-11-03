#!/bin/bash
#sudo service nginx stop
sudo certbot -t certonly --expand --standalone --pre-hook "service nginx stop" --post-hook "service nginx start" --domains \
istic.net,\
archipelago.water.gkhs.net,\
stream.aquarionics.com,aquarionics.blogs.water.gkhs.net,www.aquarionics.com,aquarionics.com,old.aquarionics.com,plex.aquarionics.com,\
wywo.blogs.water.gkhs.net,wywo.aquarionics.com,\
factionfiction.net,www.factionfiction.net,factionfiction.blogs.water.gkhs.net,\
cleartextcontent.blogs.water.gkhs.net,www.cleartextcontent.co.uk,cleartextcontent.co.uk,\
idlespeculation.blogs.water.gkhs.net,idlespeculation.foip.me,\
omnyom.blogs.water.gkhs.net,omnyom.com,www.omnyom.com,\
herodiaries.blogs.water.gkhs.net,herodiaries.foip.me,\
sevenmirrors.foip.me,\
istic.blogs.water.gkhs.net,istic.co,istic.systems,istic.network,\
casu.istic.net,wildfeathers.casu.istic.net,pdforums.casu.istic.net,\
monthlymoon.blogs.water.gkhs.net,themonthlymoon.com,\
blogs.water.gkhs.net,\
ludo.istic.co,ludoistic.com,www.ludoistic.com,\
skute.me,alpha.skute.me,\
forums.profounddecisions.co.uk,\
imperial.istic.net,altru.istic.net,log.istic.net,hol.istic.net,\
live.art.istic.net,imperial.istic.net,material.istic.net,\
warehousebasement.com,www.warehousebasement.com,\
dagon.church,live.dagon.church,wiki.dagon.church,\
mechan.istic.net,\
larp.me,api.larp.me,staging.larp.me,api.staging.larp.me,locations.larp.me,\
diaspora.foip.me,\
bless.ojaqs.foip.me,ojaqs.foip.me,\
www.iglooteas.com,iglooteas.blogs.water.gkhs.net,\
orion.nicholasavenell.com

#sudo service nginx start
