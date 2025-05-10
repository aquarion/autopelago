#!/bin/bash

eval $(ssh-agent -s)
ssh-add

for host in firth cenote atoll; do
	echo "Updating autopelago on $host.istic.systems"
	ssh -A $host.istic.systems "cd code/autopelago/bin/ && git pull" | ts "[$host:%T]"
	echo "Updating certbot on $host.istic.systems"
	ssh $host.istic.systems code/autopelago/bin/generate-$host-certbot.sh | ts "[$host:%T]" &
done

wait
