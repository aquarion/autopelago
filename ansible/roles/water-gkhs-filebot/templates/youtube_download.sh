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

	mkdir -p $SCRATCH
	cd $SCRATCH

	youtube-dl \
		--download-archive "$DIR/downloads-${CHANNEL}-${PLAYLIST}.txt" \
		-q \
		-i \
                -4 \
		-o "${CHANNEL}/${SERIES}/${SERIES} - S${SEASON}E%(playlist_index)s - %(title)s.%(ext)s" \
	       	-f bestvideo[ext=mp4]+bestaudio[ext=m4a] \
	       	--merge-output-format mp4 \
		--add-metadata \
		--write-thumbnail \
		--write-sub \
                --embed-subs \
                --embed-thumbnail \
		--convert-subs srt \
		$FILTER "$FILTER_VALUE" \
		$PLAYLIST
	rsync -r --remove-source-files $SCRATCH/ $DIR
	rm -rf $SCRATCH
}


{{ download_playlists }}

curl http://{{ plex_domain }}:32400/library/sections/{{ plex_youtube_library }}/refresh?X-Plex-Token={{ plex_token }}
