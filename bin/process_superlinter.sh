#!/bin/bash

for file in super-linter-output/super-linter/super-linter-parallel-command-exit-code-*; do
  echo "$file"
  echo "$JOB"
  FILENAME=$(basename "$file")
  DIRNAME=$(dirname "$file")
  JOB=$(echo "$FILENAME" | cut -d"-" -f 7)
  if [[ $(cat "$DIRNAME/$FILENAME") == "0" ]]; then
    echo "Job $JOB completed successfully"
    # rm -f "$file"
    rm -f "super-linter-output/super-linter/super-linter-*-$JOB"
    rm -f "super-linter-output/super-linter/super-linter-*-$JOB.json"
  else
    echo "Job $JOB failed"
    # exit 1
  fi

done
