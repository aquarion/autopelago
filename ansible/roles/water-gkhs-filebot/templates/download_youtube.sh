#!/bin/bash
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

 
exec 2>&1
exec > >(logger --tag Youtube --server={{ plex_remote_syslog_host }} --port={{ plex_remote_syslog_port }})


function dienow {
	echo "Lock found $LOCKFILE"
	exit 5
}
### BEGIN OF SCRIPT ###
 
# Simplest example is avoiding running multiple instances of script.
exlock_now || dienow
 
# Remember! Lock file is removed when one of the scripts exits and it is
#           the only script holding the lock or lock is not acquired at all.

DIR={{ media_home }}/Youtube
SCRATCH=$HOME/yt_scratch


function download {
	CHANNEL="$1"
	SERIES="$2"
	PLAYLIST="$3"
	SEASON="$4"
	FILTER_VALUE="$5"

	if [ $6 == 'only' ]
	then
		FILTER='--match-title'
	elif [ $6 == 'except' ]
	then
		FILTER='--reject-title'
	fi

	echo $CHANNEL $SERIES

	mkdir -p $SCRATCH
	cd $SCRATCH

	/usr/local/bin/youtube-dl \
		--download-archive "$DIR/downloads-${CHANNEL}-${PLAYLIST}.txt" \
		-i \
                -4 \
		-o "${CHANNEL}/${SERIES}/${SERIES} - S${SEASON}E%(playlist_index)s - %(title)s.%(ext)s" \
	       	-f bestvideo[ext=mp4]+bestaudio[ext=m4a] \
	       	--merge-output-format mp4 \
		--add-metadata \
		--write-sub \
                --embed-subs \
                --embed-thumbnail \
		--convert-subs srt \
		--write-all-thumbnails \
		--embed-thumbnail \
		--write-info-json \
		--all-subs \
		--external-downloader aria2c --external-downloader-args "-q -c -j 3 -x 3 -s 3 -k 1M" \
		$FILTER "$FILTER_VALUE" \
		$PLAYLIST
	rsync -r --remove-source-files $SCRATCH/ $DIR
	rm -rf $SCRATCH
}


{{ download_playlists }}

curl http://{{ plex_domain }}:32400/library/sections/{{ plex_youtube_library }}/refresh?X-Plex-Token={{ plex_token }}
