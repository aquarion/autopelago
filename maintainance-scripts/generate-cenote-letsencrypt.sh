#!/bin/bash
#sudo service nginx stop
sudo certbot -v -t --expand --apache --domains \
nicholasavenell.com

#sudo service nginx start
