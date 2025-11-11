get_change_id() {
    awk '/^Change-Id:/ {print $2; exit}'
}

remove_change_id_from_file() {
    local FILE="$1"
    sed -i '/^Change-Id:/d' "$FILE"
}

insert_after_separator() {
	local FILE="$1"
    local CONTENT="$2"

	UPDATED=$(awk -v CONTENT="$CONTENT" '
		/^---$/ && !done {
			print $0
			print ""
			print CONTENT
			print ""
			done=1
			next
		}
		{ print }
	' "$FILE")

	printf '%s' "$UPDATED" >"$FILE"
}
