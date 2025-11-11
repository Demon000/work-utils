#!/bin/bash

set -euo pipefail

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

for COMMIT in "${COMMITS[@]}"; do
	CHANGE_ID=$(git log -1 --format=%B "$COMMIT" | awk '/^Change-Id:/ {print $2; exit}')

	if [ -z "$CHANGE_ID" ]; then
		echo "Skipping $COMMIT: no Change-Id found" >&2
		continue
	fi

	echo "Found Change-Id $CHANGE_ID for commit $COMMIT"

	REF="refs/meta/$CHANGE_ID"

	TMP_FILE=$(mktemp)

	META_CONTENT=$(git show "$REF" 2>/dev/null || true)
	NOTE_CONTENT=$(git notes show "$COMMIT" 2>/dev/null || true)
	if [ -n "$META_CONTENT" ]; then
		printf '%s\n' "$META_CONTENT" >"$TMP_FILE"
	elif [ -n "$NOTE_CONTENT" ]; then
		printf '%s\n' "$NOTE_CONTENT" >"$TMP_FILE"
	fi

	{
		echo
		echo "#"
		echo "# Write/edit the notes for the following object:"
		echo "#"
		git show --stat "$COMMIT" | sed 's/^/# /'
		echo "#"
	} >>"$TMP_FILE"

	echo "Editing note for $CHANGE_ID"
	$EDITOR "$TMP_FILE"

	# Remove commented lines
	sed -i '/^#/d' "$TMP_FILE"

	# Remove first line if it's empty
	sed -i '1{/^[[:space:]]*$/d;}' "$TMP_FILE"

	# Remove trailing empty lines
	sed -i ':a;/^[[:space:]]*$/{$d;N;ba}' "$TMP_FILE"

	# Add back a single newline
	sed -i -e '$a\' "$TMP_FILE"

	if [ ! -s "$TMP_FILE" ]; then
		git update-ref -d "$REF"
		echo "Deleted note for $CHANGE_ID"
	else
		BLOB=$(git hash-object -w "$TMP_FILE")
		git update-ref "$REF" "$BLOB"
		echo "Updated note for $CHANGE_ID"
	fi

	rm "$TMP_FILE"
done
