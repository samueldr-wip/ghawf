#!/usr/bin/env bash

export INPUTS_JSON
INPUTS_JSON='{
"dry-run": "true",
"verbose": "false",
"Xadditional-apt-patterns": "x y z",
"enable-remove-default-apt-patterns": "true",
"enable-remove-default-space-hogs": "true",
"enable-remove-usr-local": "true",
"enable-remove-home-folder-hogs": "true",
"enable-remove-non-package-usr": "false"
}'

./get-more-space.sh "$@"
