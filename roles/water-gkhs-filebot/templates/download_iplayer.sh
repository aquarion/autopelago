#!/bin/bash
# "{{ ansible_managed }}"

# Download BBC iPlayer shows using get_iplayer

get_iplayer --no-proxy --refresh | ts >> "{{ media_logs }}/iplayer-refresh.log" 2>&1
get_iplayer --pvr | ts >> "{{ media_logs }}/iplayer-pvr.log" 2>&1
