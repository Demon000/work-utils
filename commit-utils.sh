get_change_id() {
	awk '/^Change-Id:/ {print $2; exit}'
}

get_git_change_id() {
	COMMIT="$1"
	git log -1 --format=%B "$COMMIT" | get_change_id
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

has_patches() {
	local ARG
	for ARG in "$@"; do
		if [[ "$ARG" == *.patch ]]; then
			return 0
		fi
	done
	return 1
}

extract_patches_modified_files() {
	local ARG
	for ARG in "$@"; do
		git apply --numstat "$ARG" 2>/dev/null | awk '{print $3}'
	done
}

extract_commits_modified_files() {
	git diff --name-only "$@"
}
