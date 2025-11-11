#!/bin/bash

set -euo pipefail

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

. "$SCRIPT_DIR/commit-utils.sh"
. "$SCRIPT_DIR/meta-utils.sh"

print_help() {
	echo "usage: $0 <commits>"
	echo "commits: commits to edit notes for"
}

if [ $# -eq 0 ]; then
	print_help
	exit 1
fi

COMMITS=()

for COMMITISH in "$@"; do
	if [[ "$COMMITISH" == *..* ]]; then
		while IFS= read -r COMMIT; do
			COMMITS+=("$COMMIT")
		done < <(git rev-list --reverse "$COMMITISH")
	else
		while IFS= read -r COMMIT; do
			COMMITS+=("$COMMIT")
		done < <(git rev-list --no-walk "$COMMITISH")
	fi
done

EDITOR=$(git var GIT_EDITOR)
GIT_DIR=$(git rev-parse --git-dir)
TMP_FILE="$GIT_DIR/META_NOTES_EDITMSG"

for COMMIT in "${COMMITS[@]}"; do
	CHANGE_ID=$(git log -1 --format=%B "$COMMIT" | get_change_id)
	if [ -z "$CHANGE_ID" ]; then
		echo "Skipping $COMMIT: no Change-Id found" >&2
		continue
	fi

	echo "Found Change-Id $CHANGE_ID for commit $COMMIT"

	META_CONTENT=$(get_change_id_meta_content "$CHANGE_ID")
	NOTE_CONTENT=$(get_commit_git_notes "$COMMIT")
	if [ -n "$META_CONTENT" ]; then
		printf '%s\n' "$META_CONTENT" >"$TMP_FILE"
	elif [ -n "$NOTE_CONTENT" ]; then
		printf '%s\n' "$NOTE_CONTENT" >"$TMP_FILE"
	fi

	notes_default_message "$COMMIT" >>"$TMP_FILE"

	echo "Editing note for $CHANGE_ID"
	$EDITOR "$TMP_FILE"

	cleanup_notes "$TMP_FILE"
	set_change_id_meta_content_from_file "$CHANGE_ID" "$TMP_FILE"
done
