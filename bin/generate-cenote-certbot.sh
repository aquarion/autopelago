#!/bin/bash
set -o errexit  # Exit if any line fails
set -o pipefail # Exit if any piped command fails

# Error with a message if a line fails
trap 'echo "Aborting due to an error on $0 line $LINENO. Exit code: $?" >&2' ERR
set -o errtrace #Cascade that to all functions

echo "Generating certificates for cenote"
sudo certbot -n -t certonly --expand --apache --deploy-hook "service dovecot restart" --cert-name cenote.gkhs.net --domains \
	cenote.gkhs.net,cenote.water.gkhs.net,treasuretrap.co.uk,nfnc.treasuretrap.co.uk,www.treasuretrap.co.uk,emptytables.org,www.emptytables.org,nanocountdown.com,www.nanocountdown.com,avenell.me.uk,www.avenell.me.uk,avenell.me,www.avenell.me,www.gkhs.net,fourrivers.foip.me,ornithocracy.aqxs.net,forgotten.foip.me,maelfroth.org,lampstand.maelfroth.org,forgotten.foip.me,obviouslyfakeurl.foip.me,rickroll.maelfroth.org,wiki.maelfroth.org,www.maelfroth.org,ludo.istic.net,conterio.co.uk,www.conterio.co.uk,michael.conterio.co.uk,www.grantabruggehamstery.co.uk,grantabruggehamstery.co.uk,www.pinsandneedlescostume.co.uk,pinsandneedlescostume.co.uk,thomwillis.uk,thomwillis.uk,comeoutandplay.games,dhmstark.co.uk,www.dhmstark.co.uk,kastark.co.uk,www.kastark.co.uk,www.socksandpuppets.com

echo "Generating certificates for aqxs"
sudo certbot certonly -n --expand --dns-route53 -d "*.aqxs.net" && sudo service apache2 restart

echo "Generating certificates for camlarp"
sudo certbot certonly -n --expand --cert-name camlarp.co.uk --dns-route53 -d "*.camlarp.co.uk" -d camlarp.co.uk -d "*.refs.camlarp.co.uk" && sudo service apache2 restart

#mothinabutterfly.net,www.mothinabutterfly.net,\
#swatt.treasuretrap.co.uk,
#dailyphoto.aquarionics.com,
