#!/bin/bash
# {{ ansible_managed }}

MEDIAHOME="{{ media_home }}"

function debug_out {
    [ ! -z "$VERBOSE" ] && echo $@
}

while getopts d:hv flag
do
    case "${flag}" in
        d) MEDIAHOME=${OPTARG};;
        h) SHOWHELP=Help;;
        v) VERBOSE=Yes
    esac
done

if [[ ! -z $SHOWHELP ]];
then
    echo $0 [-d DIRECTORY]
    echo "Sync non-TV shows to their own libraries"
    echo "Usage:"
    echo " -h - This"
    echo " -d - Directory to start at. Defaults to {{ media_home }}"
    echo " -v - Be noisy about it"
    exit 4
fi


if [[ -z $MEDIAHOME ]]
then
    echo "Directory not set"
    exit 5
fi;

if [[ ! -d $MEDIAHOME ]]
then
    echo "Directory not found at $MEDIAHOME"
    exit 5
fi;

debug_out "Hello $MEDIAHOME"

for dir in $MEDIAHOME/*;
do
    if [[ $dir == $MEDIAHOME/TV ]];
    then
        debug_out "Ignoring TV dir";
        continue;
    fi;
    if [[ $dir == $MEDIAHOME/Music ]];
    then
        debug_out "Ignoring Music dir";
        continue;
    fi;
    debug_out "Process $dir";
    find $dir -maxdepth 1 -mindepth 1 -type d | while read showpath;
    do
        show=`basename "$showpath"`
        # debug_out "   - Is there a " $show " in TV?";
        if [[ -d "$MEDIAHOME/TV/$show" ]];
        then
            debug_out "   - Syncing " TV/$show " -> " $dir/$show
            rsync -aWhv --progress --remove-source-files  "$MEDIAHOME/TV/$show" "$dir/"
            find "$MEDIAHOME/TV/$show" -type d -exec rmdir --ignore-fail-on-non-empty "{}" \;
        # else
            # debug_out "   - Nope. Moving on..."
        fi
    done
done
