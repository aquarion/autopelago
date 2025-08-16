#!/bin/bash

eval "$(ssh-agent -s)"
ssh-add

function update_host {
	local host=$1
	echo "Updating $host"
	ssh -A "$host.istic.systems" "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y" | ts "[$host:%T]"
	ssh -A "$host.istic.systems" "sudo apt-get autoremove -y" | ts "[$host:%T]"

	if ssh "$host.istic.systems" 'test -f /var/run/reboot-required'; then
		echo "Reboot required on $host" | ts "[$host:%T]"
		ssh -A "$host.istic.systems" "sudo reboot" | ts "[$host:%T]"
	else
		echo "No reboot required on $host" | ts "[$host:%T]"
	fi
}

for host in firth cenote atoll; do
	update_host "$host" &
done

wait
