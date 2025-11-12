#!/bin/bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

. "$SCRIPT_DIR/commit-utils.sh"

print_help() {
	echo "usage: $0 [options] <board> <commits|patches>"
	echo "board: passed to build.sh"
	echo "commits: commit range to check"
	echo "patches: patches to check"
}


BOARD="$1"
shift

if [[ -z "$BOARD" ]]; then
	print_help
	exit 1
fi

if [[ ! -d "$SCRIPT_DIR/venv" ]]; then
	python3 -m venv "$SCRIPT_DIR/venv"
fi

if has_patches "$@"; then
	mapfile -t FILES < <(extract_patches_modified_files "$@")
	FILES=$(extract_patches_modified_files "$@")
	./scripts/checkpatch.pl --strict --ignore "GERRIT_CHANGE_ID" "${FILES[@]}"
else
	mapfile -t FILES < <(extract_commits_modified_files "$@")
	./scripts/checkpatch.pl --strict --ignore "GERRIT_CHANGE_ID" -g "$@"
fi

. "$SCRIPT_DIR/venv/bin/activate"
pip install --upgrade dtschema > /dev/null 2>&1

DT_SCHEMA_FILES=()
for FILE in "${FILES[@]}"; do
	case "$FILE" in
	*.yaml)
		RELATIVE_YAML="${FILE#Documentation/devicetree/bindings/}"
		if [[ "$RELATIVE_YAML" = "$FILE" ]]; then
			echo "$FILE not under Documentation/devicetree/bindings/, skip check..."
		else
			DT_SCHEMA_FILES+=("$RELATIVE_YAML")
		fi
		;;
	esac
done

DT_SCHEMA_FILES_STR=$(IFS=: ; echo "${DT_SCHEMA_FILES[*]}")

if [ -n "$DT_SCHEMA_FILES_STR" ]; then
	echo "Testing devicetree bindings ${DT_SCHEMA_FILES[*]}"
	"$SCRIPT_DIR"/build.sh "$BOARD" dt_binding_check DT_SCHEMA_FILES="$DT_SCHEMA_FILES_STR"
	"$SCRIPT_DIR"/build.sh "$BOARD" dtbs_check DT_SCHEMA_FILES="$DT_SCHEMA_FILES_STR"
fi
