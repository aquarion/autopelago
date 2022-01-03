#!/bin/bash

# port, username, password
#SERVER="localhost:9091 --auth user:pass"

# use transmission-remote to get torrent list from transmission-remote list
TORRENTLIST=`transmission-remote --list | sed -e '1d' -e '$d' | awk '{print $1}' | sed -e 's/[^0-9]*//g'`

# for each torrent in the list
for TORRENTID in $TORRENTLIST
do
    INFO=$(transmission-remote $SERVER --torrent $TORRENTID --info)
    echo -e "Processing #$TORRENTID - $(echo $INFO | sed -e 's/.*Name: \(.*\) Hash.*/\1/')"

    # check if torrent download is completed
    DL_COMPLETED=`echo $INFO | grep "Done: 100%\|Done: 99\..%"`
    # check torrents current state is
    STATE_STOPPED=`echo $INFO | grep "State: Seeding\|State: Stopped\|State: Finished\|State: Idle"`

    # if the torrent is "Stopped", "Finished", or "Idle after downloading 100%"
    if [ "$DL_COMPLETED" ] && [ "$STATE_STOPPED" ]; then
        echo "Torrent #$TORRENTID is completed. Removing torrent from list."
        transmission-remote $SERVER --torrent $TORRENTID --remove
    else
        echo "Torrent #$TORRENTID is not completed. It is`transmission-remote $SERVER --torrent $TORRENTID --info | grep "Done:"` Ignoring."
    fi
done
