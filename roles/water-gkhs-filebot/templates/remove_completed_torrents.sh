#!/bin/bash
# {{ ansible_managed }}

# Script to remove completed torrents from Transmission

# Transmission server connection details are set in .netrc file in home directory

if ! hash transmission-remote 2>/dev/null; then
	echo "transmission-remote command not found. Please install Transmission CLI tools."
	exit 1
fi

if ! hash jq 2>/dev/null; then
	echo "jq command not found. Please install jq JSON processor."
	exit 1
fi

# use transmission-remote to get torrent list from transmission-remote list
TORRENTLIST=$(transmission-remote --json --list | jq -r '.arguments.torrents[].id')

if [ -z "$TORRENTLIST" ]; then
	echo "No torrents found in Transmission."
	exit 0
fi

if [[ $TERM == "dumb" ]]; then # No color support
	RED=""
	GREEN=""
	YELLOW=""
	NC=""
else
	RED="\e[31m"
	GREEN="\e[32m"
	YELLOW="\e[33m"
	NC="\e[0m" # No Color
fi

TXT_COMPLETE="${GREEN}Completed${NC}"
TXT_INCOMPLETE="${YELLOW}Incomplete${NC}"
TXT_AGEDOUT="${RED}Aged Out${NC}"

CURRENT_EPOCH=$(date +%s)
AGE_OUT_CUTOFF=$((2 * 30 * 24 * 60 * 60)) # 60 days in seconds

# for each torrent in the list
transmission-remote --json --list | jq -r '.arguments.torrents[].id' | while read -r TORRENTID; do
	INFO=$(transmission-remote --torrent "$TORRENTID" --json --info)
	NAME=$(echo "$INFO" | jq -r .arguments.torrents[0].name)
	FINISHED=$(echo "$INFO" | jq -r .arguments.torrents[0].isFinished)
	RATIO=$(echo "$INFO" | jq -r .arguments.torrents[0].uploadRatio)
	LAST_ACTIVITY=$(echo "$INFO" | jq -r .arguments.torrents[0].activityDate)
	AGE=$((CURRENT_EPOCH - LAST_ACTIVITY))

	if [[ $LAST_ACTIVITY == "null" ]]; then
		LAST_ACTIVITY_WORDS="N/A"
	else
		LAST_ACTIVITY_WORDS=$(date -d @"$LAST_ACTIVITY" +"%Y-%m-%d %H:%M:%S")
	fi

	echo -en "#$TORRENTID - $NAME - "

	# Check if the torrent is finished
	if [ "$FINISHED" = "true" ]; then
		echo -e " is ${GREEN}${TXT_COMPLETE}${NC} Removing."
		transmission-remote --torrent "$TORRENTID" --remove
	else
		if ((AGE > AGE_OUT_CUTOFF)); then
			echo -e " is ${RED}${TXT_AGEDOUT}${NC}, Last activity $LAST_ACTIVITY_WORDS. Removing."
			transmission-remote --torrent "$TORRENTID" --remove
			continue
		else
			echo -e " is ${YELLOW}${TXT_INCOMPLETE}${NC}, Ratio is $RATIO. Ignoring."
		fi
	fi
done
