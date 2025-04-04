#!/bin/bash

eval `ssh-agent -s`
ssh-add

for host in firth cenote atoll;
  do
    echo "Updating $host";
    ssh -A $host.istic.systems "sudo apt update && sudo apt upgrade -y" | ts "[$host:%T]" ;
done

wait