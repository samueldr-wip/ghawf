#!/usr/bin/env bash

set -e
set -u
PS4=" $ "
set -x

nix-instantiate --eval --strict --json test.nix > .github/workflows/build.yml
git commit -m "… $(date)" "${@:--a}"
git push
