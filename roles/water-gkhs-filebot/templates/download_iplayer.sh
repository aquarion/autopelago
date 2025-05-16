#!/bin/bash
# "{{ ansible_managed }}"

exec 2>&1
exec > >(logger --tag iPlayer --server="{{ medialibrary_remote_syslog_host }}" --port="{{ medialibrary_remote_syslog_port }}")

get_iplayer --no-proxy --refresh | logger --tag iPlayer --server="{{ medialibrary_remote_syslog_host }}" --port="{{ medialibrary_remote_syslog_port }}"
get_iplayer --pvr | logger --tag iPlayer --server="{{ medialibrary_remote_syslog_host }}" --port="{{ medialibrary_remote_syslog_port }}"
