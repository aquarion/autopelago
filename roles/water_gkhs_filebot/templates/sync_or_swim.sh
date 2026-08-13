#!/bin/bash
# {{ ansible_managed }}

MEDIAHOME="{{ media_library }}"
SOURCEDIR="TV"
TOTAL_FAILURES=0

BASH_YELLOW="\033[0;33m"
BASH_CLEAR="\033[0m" # No Color
BASH_RED="\033[0;31m"

function debug_out {
	[ -n "$VERBOSE" ] && echo "$@"
}

function warn_out {
	echo -e "${BASH_YELLOW}WARNING:${BASH_CLEAR} $*" >&2
}

function error_out {
	echo -e "${BASH_RED}ERROR:${BASH_CLEAR} $*" >&2
	exit 1
}

function merge_dir {
	local src=$1 dest=$2
	local fail=0 file rel
	while IFS= read -r -d '' file; do
		rel="${file#"$src"/}"
		if [[ -e "$dest/$rel" ]]; then
			debug_out "   - Skipping $rel (already present at destination)"
			continue
		fi
		if ! mkdir -p "$dest/$(dirname "$rel")"; then
			warn_out "Could not create $dest/$(dirname "$rel")"
			fail=1
			continue
		fi
		if ! mv -n "$file" "$dest/$rel"; then
			warn_out "Failed to move $rel"
			fail=1
		fi
	done < <(find -L "$src" -mindepth 1 -type f -print0)
	find -L "$src" -depth -type d -empty -delete
	return $fail
}

while getopts ":d:s:hv" flag; do
	case "${flag}" in
	d) MEDIAHOME=${OPTARG} ;;
	s) SOURCEDIR=${OPTARG} ;;
	h) SHOWHELP=Help ;;
	v) VERBOSE=Yes ;;
	\?)
		echo "Invalid option: -$OPTARG" >&2
		exit 2
		;;
	:)
		echo "Option -$OPTARG requires an argument" >&2
		exit 2
		;;
	esac
done
SOURCEDIR="${SOURCEDIR%/}"

if [[ ! -z $SHOWHELP ]]; then
	echo "$0 [-d DIRECTORY] [-s SUBDIR]"
	echo "Sync non-TV shows to their own libraries"
	echo "Usage:"
	echo " -h - This"
	echo " -d - Directory to start at. Defaults to {{ media_library }}"
	echo " -s - Subdirectory to sync shows from. Defaults to TV"
	echo " -v - Be noisy about it"
	exit 4
fi

if [[ -z $MEDIAHOME ]]; then
	error_out "Directory not set"
fi

if [[ ! -d $MEDIAHOME ]]; then
	error_out "Directory not found at $MEDIAHOME"
fi

debug_out "Hello $MEDIAHOME"

if [[ ! -d "$MEDIAHOME/$SOURCEDIR" ]]; then
	error_out "Source directory not found at $MEDIAHOME/$SOURCEDIR"
fi

for dir in "$MEDIAHOME"/*; do
	if [[ $dir == "$MEDIAHOME/$SOURCEDIR" ]]; then
		debug_out "Ignoring $SOURCEDIR dir"
		continue
	fi
	if [[ $dir == "$MEDIAHOME/Music" ]]; then
		debug_out "Ignoring Music dir"
		continue
	fi
	debug_out "Process $dir"
	while IFS= read -r -d '' showpath; do
		show=$(basename "$showpath")
		if [[ -d "$MEDIAHOME/$SOURCEDIR/$show" ]]; then
			debug_out "   - Syncing " "$SOURCEDIR"/"$show" " -> " "$dir"/"$show"
			merge_dir "$MEDIAHOME/$SOURCEDIR/$show" "$dir/$show" || ((TOTAL_FAILURES++))
		fi
	done < <(find -L "$dir" -maxdepth 1 -mindepth 1 -type d -print0)
done

if [[ $TOTAL_FAILURES -gt 0 ]]; then
	error_out "$TOTAL_FAILURES show(s) had errors during sync"
fi
