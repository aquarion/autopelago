#!/bin/bash

#eval "$(ssh-agent -s)"
#ssh-add

for host in firth atoll; do
	# echo "Updating autopelago on $host.istic.systems"
	# ssh -A $host.istic.systems "cd code/autopelago/bin/ && git pull" 2>&1 | ts "[$host:%T]"
	echo "Updating certbot on $host.istic.systems"
	cat bin/generate-$host-certbot.sh | ssh -A $host.istic.systems "bash -s" 2>&1 | ts "[$host:%T]" &
done

wait
