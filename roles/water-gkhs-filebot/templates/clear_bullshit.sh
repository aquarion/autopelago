#!/bin/bash
# {{ ansible_managed }}

# Remove stray files from downloaded torrents

find "{{ transmission_complete }}/completed" -iname ".xattr" -type d -exec rm -rf {} \;
find "{{ transmission_complete }}/completed" -links +1 -type f -delete -print
find "{{ transmission_complete }}/completed" -iname "screen*.jpg" -type f -delete -print
find "{{ transmission_complete }}/completed" -iname "screen*.png" -type f -delete -print
find "{{ transmission_complete }}/completed" -iname "*.txt" -delete -print
find "{{ transmission_complete }}/completed" -iname "*nfo" -delete -print
find "{{ transmission_complete }}/completed" -iname "*sample.???" -delete -print
find "{{ transmission_complete }}/completed" -iname "*srt" -delete -print
find "{{ transmission_complete }}/completed" -iname "RARBG.txt" -delete -print
find "{{ transmission_complete }}/completed" -iname "RARBG_DO_NOT_MIRROR.exe" -delete -print
find "{{ transmission_complete }}/completed" -iname "*tvm.jpg" -delete -print
find "{{ transmission_complete }}/completed" -type d -exec rmdir {} \;
find "{{ transmission_complete }}/completed" -iname "www.YTS.MX.jpg" -delete -print
