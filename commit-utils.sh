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

parse_commitish() {
	local -n _COMMITS=$1
	shift

	_COMMITS=()

	local COMMITISH
	for COMMITISH in "$@"; do
		if [[ "$COMMITISH" == *..* ]]; then
			while IFS= read -r COMMIT; do
				_COMMITS+=("$COMMIT")
			done < <(git rev-list --reverse "$COMMITISH")
		else
			while IFS= read -r COMMIT; do
				_COMMITS+=("$COMMIT")
			done < <(git rev-list --no-walk "$COMMITISH")
		fi
	done
}
