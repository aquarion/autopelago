#!/bin/bash
# {{ ansible_managed }}

# Remove stray files from downloaded torrents


if [ -z "$1" ]; then
	FILEPATH="{{ transmission_complete }}"
else
	FILEPATH=$1
fi


find "$FILEPATH/completed" -iname ".xattr" -type d -exec rm -rf {} \;
find "$FILEPATH/completed" -links +1 -type f -delete -print
find "$FILEPATH/completed" -iname "screen*.jpg" -type f -delete -print
find "$FILEPATH/completed" -iname "screen*.png" -type f -delete -print
find "$FILEPATH/completed" -iname "*.txt" -delete -print
find "$FILEPATH/completed" -iname "*nfo" -delete -print
find "$FILEPATH/completed" -iname "*sample.???" -delete -print
find "$FILEPATH/completed" -iname "*srt" -delete -print
find "$FILEPATH/completed" -iname "RARBG.txt" -delete -print
find "$FILEPATH/completed" -iname "RARBG_DO_NOT_MIRROR.exe" -delete -print
find "$FILEPATH/completed" -iname "*tvm.jpg" -delete -print
find "$FILEPATH/completed" -type d -exec rmdir {} \;
find "$FILEPATH/completed" -iname "www.YTS.MX.jpg" -delete -print
