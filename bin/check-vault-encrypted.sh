#!/usr/bin/env bash
# Verify that all passed files are encrypted with ansible-vault
failed=0
for file in "$@"; do
	if ! head -1 "$file" | grep -q '^\$ANSIBLE_VAULT'; then
		echo "ERROR: $file is not encrypted with ansible-vault"
		failed=1
	fi
done
exit $failed
