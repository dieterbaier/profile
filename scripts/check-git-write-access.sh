#!/usr/bin/env bash
# Proves that a token has push permission on a repository without changing it:
# a dry-run push opens the server's receive side, which rejects a token without
# push permission. It sends no ref update, so it does not prove that a real push
# to main passes branch rules or server hooks.

set -euo pipefail

repository="$1"
user="$2"
: "${CHECK_TOKEN:?CHECK_TOKEN is required}"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

git clone --quiet --depth 1 "https://${user}:${CHECK_TOKEN}@${repository}" "$workdir/repo"
git -C "$workdir/repo" push --dry-run origin HEAD:main
