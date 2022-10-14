#!/bin/bash

sudo certbot -n -t certonly --expand --apache --cert-name cenote.gkhs.net --domains \
cenote.gkhs.net,cenote.water.gkhs.net,\
comic.mc.aqxs.net,comicpress.socksandpuppets.com,comic.socksandpuppets.com,ahdok.aqxs.net,socksandpuppets.com,www.socksandpuppets.com,\
treasuretrap.co.uk,nfnc.treasuretrap.co.uk,www.treasuretrap.co.uk,\
emptytables.org,www.emptytables.org,\
nanocountdown.com,www.nanocountdown.com,\
avenell.me.uk,www.avenell.me.uk,avenell.me,www.avenell.me,\
www.gkhs.net,\
live.dailyphoto.aquarionics.com,\
fourrivers.foip.me,larp.me.uk,www.larp.me.uk,ornithocracy.aqxs.net,forgotten.foip.me,\
maelfroth.org,lampstand.maelfroth.org,obviouslyfakeurl.foip.me,rickroll.maelfroth.org,wiki.maelfroth.org,www.maelfroth.org,\
ludo.istic.net,\
www.contrarythoughts.com,contrarythoughts.com,michael.conterio.co.uk,\
www.grantabruggehamstery.co.uk,grantabruggehamstery.co.uk,\
www.pinsandneedlescostume.co.uk,pinsandneedlescostume.co.uk,\
thomwillis.uk,thomwillis.uk,\
comeoutandplay.games,\
dhmstark.co.uk,www.dhmstark.co.uk,kastark.co.uk,www.kastark.co.uk

sudo certbot certonly -n --expand --dns-route53 -d *.aqxs.net && sudo service apache2 restart
sudo certbot certonly -n --expand --cert-name camlarp.co.uk --dns-route53 -d *.camlarp.co.uk -d camlarp.co.uk -d *.refs.camlarp.co.uk && sudo service apache2 restart

 #mothinabutterfly.net,www.mothinabutterfly.net,\
 #swatt.treasuretrap.co.uk,
#dailyphoto.aquarionics.com,
