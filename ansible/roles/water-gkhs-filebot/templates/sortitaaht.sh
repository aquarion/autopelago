#!/bin/sh

{% if verbose is not defined %}
{% set verbose = "" %}
{% else %}
{% set verbose = "#" %}
{% endif %}

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
        --def excludeList={{ plex_home }}/Logs/amc_seen.txt \
        --def discord={{ discord_webhook_plex }}  \
        --def clean=y \
        --def plex=localhost:{{ plex_token }} \
        --action hardlink \
        --conflict override -non-strict \
        --def music=y subtitles=en artwork=y extras=y \
        --def \
                "seriesFormat=TV/{n}/{'S'+s}/{s00e00} - {t}" \
                "animeFormat=Anime/{n}/{fn}" \
                "movieFormat=Movies/{n} {y}/{fn}" \
                "musicFormat=Music/{n}/{fn}" \
        "$FILEPATH" {{ verbose }} > {{ plex_home }}/Logs/amc.stdout.log
