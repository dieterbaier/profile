#!/usr/bin/env bash
# Proves that a token may write to a repository without changing it: a dry-run
# push asks the server for push access, and a token without it is rejected.

set -euo pipefail

repository="$1"
user="$2"
: "${CHECK_TOKEN:?CHECK_TOKEN is required}"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

git clone --quiet --depth 1 "https://${user}:${CHECK_TOKEN}@${repository}" "$workdir/repo"
git -C "$workdir/repo" push --dry-run origin HEAD:main
