#!/bin/bash


export AWS_PROFILE=istic-r53
sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand  --dns-route53 --cert-name atoll.water.gkhs.net --domains atoll.istic.systems,voyuer.istic.net,ws.voyuer.istic.net
sudo --preserve-env=AWS_PROFILE certbot -n -t certonly --expand  --dns-route53 --cert-name voyeur.istic.net --domains voyeur.istic.net,ws.voyeur.istic.net



sudo chown -R root:certbot_access /etc/letsencrypt
sudo chmod g+rx /etc/letsencrypt
sudo find /etc/letsencrypt -type d -exec chmod g+rx {} \;
sudo find /etc/letsencrypt -type f -exec chmod g+r {} \;

sudo service nginx reload
