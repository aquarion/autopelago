#!/bin/bash

eval $(ssh-agent -s)
ssh-add

for host in firth cenote atoll; do
	echo "Updating $host"
	ssh -A $host.istic.systems "sudo apt update -qq && sudo apt upgrade -y && sudo apt autoremove -y" | ts "[$host:%T]"
done

wait
