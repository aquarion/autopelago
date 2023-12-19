#!/bin/bash

eval "$(direnv export bash)"

TARGET=roles

clear
ansible-lint

inotifywait -m -r -e modify -e create $TARGET --format="%f" \
        | while read FILENAME
                do
                        clear
                        echo Detected $FILENAME
                        ansible-lint --write
                        # mv "$TARGET/$FILENAME" "$PROCESSED/$FILENAME"
                        # gzip "$PROCESSED/$FILENAME"
                done
               
