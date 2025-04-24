#!/bin/bash

eval `ssh-agent -s`
ssh-add

for host in firth cenote atoll;
  do
    echo "Updating $host";
    if `ssh $host.istic.systems "test -f /var/run/reboot-required"`; then
      echo "Reboot required on $host"
      ssh -A $host.istic.systems "sudo reboot" | ts "[$host:%T]" ;
    else
      echo "No reboot required on $host"
    fi
done

wait

