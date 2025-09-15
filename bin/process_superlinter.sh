#!/bin/bash
set -o errexit  # Exit if any line fails
set -o pipefail # Exit if any piped command fails

# Error with a message if a line fails
trap 'echo "Aborting due to an error on $0 line $LINENO. Exit code: $?" >&2' ERR
set -o errtrace #Cascade that to all functions

OUT=$PWD/super-linter-output/super-linter
TRASH=$OUT/.Trash
mkdir -p "$TRASH"

for file in "$OUT/super-linter-parallel-command-exit-code-"*; do
	echo "$file"
	echo "$JOB"
	FILENAME=$(basename "$file")
	DIRNAME=$(dirname "$file")
	JOB=$(echo "$FILENAME" | cut -d"-" -f 7)
	if [[ $(cat "$DIRNAME/$FILENAME") == "0" ]]; then
		echo "Job $JOB completed successfully"
		for OUTFILE in \
			$OUT/super-linter-parallel-stdout-$JOB \
			$OUT/super-linter-parallel-stderr-$JOB \
			$OUT/super-linter-worker-results-$JOB.json; do
			if [[ -f "$OUTFILE" ]]; then
				echo "Moving $OUTFILE to $TRASH"
				mv "$OUTFILE" "$TRASH/"
			fi
		done

		mv -v "$file" "$TRASH/$FILENAME"
	else
		echo "Job $JOB failed"
		# exit 1
	fi

done

rm -rf "$TRASH"

cat super-linter-output/super-linter-summary.md
ls -l "$OUT"
