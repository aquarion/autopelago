#!/bin/bash                                                                                                                                                                                                                                                                    


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
 
# Remember! Lock file is removed when one of the scripts exits and it is
#           the only script holding the lock or lock is not acquired at all.

HOME=/home/aquarion
WATCH_PATH=$HOME/Dropbox/IFTTT
WATCHFILE=$HOME/logs/inotify_ifttt.fifo
LOGFILE=$HOME/logs/inotify_ifttt.log

# Close STDOUT file descriptor
exec 1<&-
# Close STDERR FD
exec 2<&-

# Open STDOUT as $LOG_FILE file for read and write.
exec 1<>$LOGFILE

# Redirect STDERR to STDOUT
exec 2>&1

if [[ -p $WATCHFILE ]];
then
	true;
else
	mkfifo $WATCHFILE
fi

echo "Hello World  (`date`)"

inotifywait -drq -o $WATCHFILE -e create -e moved_to $WATCH_PATH

trap "true" PIPE
cat $WATCHFILE | while read  path action file; 
do
	SUM=`md5sum "$path$file" | cut -d\  -f1` 
	echo Hello $path$file $SUM
	if [[ "$SUM" == "394f8b4fa928b5f2d0c13645f99e2d33" ]]
	then 
		echo "Looks like the old IFTTT 404"
		rm -v "$path$file"
	elif  [[ "$SUM" == "96ff1cee0b824f18612629b4bcf24e91" ]]
	then
		echo "Looks like the new IFTTT 404 JPG"
		rm -v "$path$file"
	elif  [[ "$SUM" == "4d3559b444eb8d78b1a9e0ee15132434" ]]
	then
		echo "Looks like the new IFTTT 404 PNG"
		rm -v "$path$file"
	else
		echo "No idea about $SUM"
	fi
done
trap PIPE
