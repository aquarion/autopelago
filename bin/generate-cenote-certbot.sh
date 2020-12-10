#!/bin/bash

sudo certbot -n -t certonly --expand --standalone --cert-name cenote.gkhs.net --pre-hook "service apache2 stop" --post-hook "service apache2 start" --domains \
cenote.gkhs.net,cenote.water.gkhs.net,ssl.aqxs.net,\
advent.aqxs.net,advent-knowledge.info,www.advent-knowledge.info,\
ashires.aqxs.net,bluebottle.aqxs.net,chesswiki.aqxs.net,dgold.aqxs.net,entimix.aqxs.net,locksmith.aqxs.net,makai.aqxs.net,martindenton.aqxs.net,rho21.aqxs.net,rjw76.aqxs.net,salavant.aqxs.net,taxellor.aqxs.net,tdk27.aqxs.net,\
comic.mc.aqxs.net,comicpress.socksandpuppets.com,comic.socksandpuppets.com,ahdok.aqxs.net,socksandpuppets.com,www.socksandpuppets.com,\
camlarp.co.uk,www.camlarp.co.uk,bw.camlarp.co.uk,nfnc.camlarp.co.uk,refs.bw.camlarp.co.uk,refs.nfnc.camlarp.co.uk,citadel.camlarp.co.uk,obscura.camlarp.co.uk,\
treasuretrap.co.uk,nfnc.treasuretrap.co.uk,www.treasuretrap.co.uk,\
aquarion.aqxs.net,\
emptytables.org,www.emptytables.org,\
isittheweekend.com,www.isittheweekend.com,\
nanocountdown.com,www.nanocountdown.com,\
wherearemyfuckingkeys.com,www.wherearemyfuckingkeys.com,\
avenell.me.uk,www.avenell.me.uk,avenell.me,www.avenell.me,\
www.gkhs.net,\
aqxs.net,www.aqxs.net,\
live.dailyphoto.aquarionics.com,\
empireproxy.aqxs.net,fourrivers.foip.me,larp.me.uk,www.larp.me.uk,ornithocracy.aqxs.net,forgotten.foip.me,\
maelfroth.org,lampstand.aqxs.net,lampstand.maelfroth.org,obviouslyfakeurl.foip.me,rickroll.maelfroth.org,wiki.maelfroth.org,www.maelfroth.org,\
lottery.aqxs.net,snakesandladders.aqxs.net,spycattes.aqxs.net,unhelpfulclue.aqxs.net,\
ludo.istic.net,\
mc.aqxs.net,mcwp.aqxs.net,www.contrarythoughts.com,contrarythoughts.com,michael.conterio.co.uk,\
nicholasavenell.com,www.nicholasavenell.com,\
voicemail.aqxs.net,\
www.deadbadgerdesigns.co.uk,deadbadgerdesigns.co.uk,\
www.grantabruggehamstery.aqxs.net,www.grantabruggehamstery.co.uk,grantabruggehamstery.co.uk,\
www.pinsandneedlescostume.co.uk,pinsandneedlescostume.co.uk,\
thomwillis.uk,thomwillis.uk,moth.aqxs.net,\
comeoutandplay.aqxs.net,comeoutandplay.games,\
dhmstark.co.uk,www.dhmstark.co.uk,kastark.co.uk,www.kastark.co.uk

sudo certbot certonly -n --expand --dns-route53 -d *.aqxs.net && sudo service apache2 restart

sudo certbot -n -t certonly --expand --standalone --pre-hook "service apache2 stop" --post-hook "service apache2 start" --domains nicholasavenell.com,www.nicholasavenell.com
 #mothinabutterfly.net,www.mothinabutterfly.net,\
 #swatt.treasuretrap.co.uk,
#dailyphoto.aquarionics.com,
