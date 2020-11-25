#!/bin/bash
#sudo service nginx stop
sudo letsencrypt -v -t --expand --apache --domains \
treacle.mine.nu,\
kettle.treacle.mine.nu,\
media.treacle.mine.nu

#sudo service nginx start
