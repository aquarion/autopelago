#!/bin/sh
# {{ ansible_managed }}

{% if verbose is not defined %}
{% set verbose = "" %}
{% else %}
{% set verbose = "#" %}
{% endif %}

if [ -z "$1" ]; then
	FILEPATH="{{ transmission_complete }}"
else
	FILEPATH=$1
fi

export JAVA_OPTS=-Xmx1024m
filebot -script fn:amc \
	--output "{{ media_library }}" \
	--log-file {{ media_home }}/Logs/amc.log \
	--def excludeList={{ media_home }}/Logs/amc_seen.txt \
	--def discord={{ discord_webhook_medialibrary }} \
	--def clean=y \
	--def minLengthMS=60000 \
	--apply metadata \
	--action hardlink \
	--conflict override -non-strict \
	--def music=y subtitles=en artwork=y \
	--def \
	"seriesFormat=TV/{n}/{'S'+s}/{s00e00} - {t}" \
	"animeFormat=Anime/{n}/{fn}" \
	"movieFormat=Movies/{n} {y}/{fn}" \
	"musicFormat=Music/{n}/{fn}" \
	"$FILEPATH" {{ verbose }} {{ media_home }}/Logs/amc.stdout.log >

{{ media_home }}/bin/sync_or_swim.sh
