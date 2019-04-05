#!/bin/sh
export JAVA_OPTS=-Xmx1024m
filebot -script fn:amc \
        --output "{{ media_home }}" \
        --log-file amc.log \
        --action move \
        --conflict override -non-strict \
        --def music=y subtitles=en artwork=y \
        --def \
                "seriesFormat=TV/{n}/{'S'+s}/{s00e00} - {t}" \
                "animeFormat=Anime/{n}/{fn}" \
                "movieFormat=Movies/{n} {y}/{fn}" \
                "musicFormat=Music/{n}/{fn}" \
        "{{ transmission_complete }}"
