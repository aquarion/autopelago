#!/bin/bash
#sudo service nginx stop
sudo certbot -v -t --expand --apache --domains \
`ls -1 /var/www/hosts | grep "\." | grep -v 109.74.192.161 | paste -sd "," -`

#sudo service nginx start
