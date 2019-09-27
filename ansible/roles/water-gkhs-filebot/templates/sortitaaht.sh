#!/bin/sh

if [ -z "$1" ]
  then
    FILEPATH={{ transmission_complete }}
else
    FILEPATH=$1
fi

export JAVA_OPTS=-Xmx1024m
filebot -script fn:amc \
        --output "{{ media_home }}" \
        --log-file {{ plex_home }}/Logs/amc.log \
        --action hardlink \
        --conflict override -non-strict \
        --def music=y subtitles=en artwork=y \
        --def \
                "seriesFormat=TV/{n}/{'S'+s}/{s00e00} - {t}" \
                "animeFormat=Anime/{n}/{fn}" \
                "movieFormat=Movies/{n} {y}/{fn}" \
                "musicFormat=Music/{n}/{fn}" \
        "$FILEPATH" > {{ plex_home }}/Logs/amc.stdout.log
