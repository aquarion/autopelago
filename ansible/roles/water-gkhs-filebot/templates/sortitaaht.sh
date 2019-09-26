#!/bin/sh
# SPDX-License-Identifier: MIT
 
## Copyright (C) 2009 Przemyslaw Pawelczyk <przemoc@gmail.com>
##
## This script is licensed under the terms of the MIT license.
## https://opensource.org/licenses/MIT
#
# Lockable script boilerplate
 
### HEADER ###
 
LOCKFILE="/var/lock/`basename $0`"
LOCKFD=99
 
# PRIVATE
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }
 
# ON START
_prepare_locking
 
# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
exlock()            { _lock x; }   # obtain an exclusive lock
shlock()            { _lock s; }   # obtain a shared lock
unlock()            { _lock u; }   # drop a lock
 
### BEGIN OF SCRIPT ###
 
# Simplest example is avoiding running multiple instances of script.
exlock_now || exit 1
 

export JAVA_OPTS=-Xmx1024m
filebot -script fn:amc \
        --output "{{ media_home }}" \
        --log-file amc.log \
        --action hardlink \
        --conflict override -non-strict \
        --def music=y subtitles=en artwork=y \
        --def \
                "seriesFormat=TV/{n}/{'S'+s}/{s00e00} - {t}" \
                "animeFormat=Anime/{n}/{fn}" \
                "movieFormat=Movies/{n} {y}/{fn}" \
                "musicFormat=Music/{n}/{fn}" \
        "{{ transmission_complete }}" > ~/amc.stdout.log
