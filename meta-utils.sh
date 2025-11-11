get_change_id_meta_content_ref() {
	local CHANGE_ID="$1"
	echo "refs/meta/$CHANGE_ID"
}

get_change_id_meta_content() {
	local CHANGE_ID="$1"
	local REF=$(get_change_id_meta_content_ref "$CHANGE_ID")
	git show "$REF" 2>/dev/null || true
}

get_commit_git_notes() {
	local COMMIT="$1"
	git notes show "$COMMIT" 2>/dev/null || true
}

notes_default_message() {
	local COMMIT="$1"
	echo
	echo "#"
	echo "# Write/edit the notes for the following object:"
	echo "#"
	git show --stat "$COMMIT" | sed 's/^/# /'
	echo "#"
}

set_change_id_meta_content_from_file() {
	local CHANGE_ID="$1"
	local FILE="$2"
	local REF=$(get_change_id_meta_content_ref "$CHANGE_ID")

	if [ ! -s "$FILE" ]; then
		git update-ref -d "$REF"
		echo "Deleted note for $CHANGE_ID"
	else
		local BLOB=$(git hash-object -w "$FILE")
		git update-ref "$REF" "$BLOB"
		echo "Updated note for $CHANGE_ID"
	fi
}

cleanup_notes() {
	local FILE="$1"

	# Remove commented lines
	sed -i '/^#/d' "$FILE"

	# Remove first line if it's empty
	sed -i '1{/^[[:space:]]*$/d;}' "$FILE"

	# Remove trailing empty lines
	sed -i ':a;/^[[:space:]]*$/{$d;N;ba}' "$FILE"

	# Add back a single newline
	sed -i -e '$a\' "$FILE"
}
