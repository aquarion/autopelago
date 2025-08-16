#!/bin/bash

export AWS_PROFILE=istic-r53
echo "Generating certificates for atoll"
sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand --dns-route53 --cert-name atoll.water.gkhs.net --domains atoll.istic.systems,voyuer.istic.net,ws.voyuer.istic.net
echo "Generating certificates for voyeur"
sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand --dns-route53 --cert-name voyeur.istic.net --domains voyeur.istic.net,ws.voyeur.istic.net

echo "Updating Permissions for Certbot"
sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

echo "Reloading nginx"
sudo service nginx reload
