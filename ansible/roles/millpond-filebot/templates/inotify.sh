#!/bin/bash                                                                                                                                                                                                                                                                    

HOME={{ plex_home }}
WATCH_PATH=$HOME/Torrential/Completed
LOGFILE=$HOME/inotify_watch.log

mkfifo $LOGFILE

inotifywait -drq -o $LOGFILE -e create -e moved_to $WATCH_PATH

trap "true" PIPE
cat $LOGFILE | while read  path action file; 
do
	#echo "Saw $action in $path"; 
	$HOME/bin/sortitaaht.sh; 
done
trap PIPE
