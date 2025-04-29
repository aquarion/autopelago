#!/bin/bash

docker run \
	-e DEFAULT_BRANCH=main \
	-e LOG_LEVEL=DEBUG \
	-e SAVE_SUPER_LINTER_SUMMARY=true \
	-e RUN_LOCAL=true \
	-v $PWD:/tmp/lint \
	--env-file "$(git root)/.github/super-linter.local.env" \
	ghcr.io/super-linter/super-linter:slim-latest
