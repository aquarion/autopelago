#!/bin/bash
# {{ ansible_managed }}

# Remove stray files from downloaded torrents

find {{ transmission_complete }}/completed -name .xattr -type d -exec rm -rf {} \;
find {{ transmission_complete }}/completed -links +1 -type f -delete -print
find {{ transmission_complete }}/completed -iname screen\*.jpg -type f -delete -print
find {{ transmission_complete }}/completed -iname screen\*.png -type f -delete -print
find {{ transmission_complete }}/completed -name \*\.txt -delete -print
find {{ transmission_complete }}/completed -name \*nfo -delete -print
find {{ transmission_complete }}/completed -name \*sample\.??? -delete -print
find {{ transmission_complete }}/completed -name \*srt -delete -print
find {{ transmission_complete }}/completed -name RARBG.txt -delete -print
find {{ transmission_complete }}/completed -name RARBG_DO_NOT_MIRROR.exe -delete -print
find {{ transmission_complete }}/completed -name \*tvm.jpg -delete -print
find {{ transmission_complete }}/completed -type d -exec rmdir {} \;
find {{ transmission_complete }}/completed -name www.YTS.MX.jpg -delete -print