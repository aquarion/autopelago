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


HOME={{ plex_home }}
WATCH_PATH={{ transmission_complete }}/completed
LOGFILE=$HOME/Logs/filebot_inotify.log
WATCHFILE=$HOME/.filebot_inotify.fifo

if [[ -p $WATCHFILE ]];
then
	true;
else
	mkfifo $WATCHFILE || exit 5
fi


# Close STDOUT file descriptor
exec 1<&-
# Close STDERR FD
exec 2<&-

# Open STDOUT as $LOG_FILE file for read and write.
exec 1<>$LOGFILE

# Redirect STDERR to STDOUT
exec 2>&1


inotifywait -drq -o $WATCHFILE -e create -e moved_to $WATCH_PATH

trap "true" PIPE
cat $WATCHFILE | while read  path action file;
do
	echo Saw $action on $path$file
	#echo "Saw $action in $path";
	$HOME/bin/sortitaaht.sh $path$file
done
trap PIPE
