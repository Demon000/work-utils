#!/bin/bash

set -euo pipefail

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

. "$SCRIPT_DIR/commit-utils.sh"
. "$SCRIPT_DIR/meta-utils.sh"

print_help() {
	echo "usage: $0 [options] <commits>"
	echo "commits: commits to gather notes for"
}

if [[ $# -eq 0 ]]; then
	print_help
	exit 1
fi

COMMITS=()
parse_commitish COMMITS "$@"

for COMMIT in "${COMMITS[@]}"; do
	CHANGE_ID=$(git log -1 --format=%B "$COMMIT" | get_change_id)
	if [[ -z "$CHANGE_ID" ]]; then
		continue
	fi

	META_CONTENT=$(get_change_id_meta_content "$CHANGE_ID")
    if [[ -z "$META_CONTENT" ]]; then
        continue
    fi

    echo "$META_CONTENT"
done | "$SCRIPT_DIR/gather_notes.py"
