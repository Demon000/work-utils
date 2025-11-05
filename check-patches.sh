#!/bin/bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

print_help() {
	echo "usage: $0 [options] <board> <commits>"
	echo "board: passed to build.sh"
	echo "commits: commit range to check"
}


BOARD="$1"
shift

if [[ -z "$BOARD" ]]; then
	print_help
	exit 1
fi

COMMITS="$1"
shift

if [[ -z "$COMMITS" ]]; then
	print_help
	exit 1
fi

FILES=$(git diff --name-only "$COMMITS")

if [[ ! -d "$SCRIPT_DIR/venv" ]]; then
	python3 -m venv "$SCRIPT_DIR/venv"
fi

./scripts/checkpatch.pl --strict -g "$COMMITS"

. "$SCRIPT_DIR/venv/bin/activate"
pip install --upgrade dtschema > /dev/null 2>&1

DT_SCHEMA_FILES=()
while read FILE; do
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
done <<< "$FILES"

DT_SCHEMA_FILES_STR=$(IFS=: ; echo "${DT_SCHEMA_FILES[*]}")

if [ -n "$DT_SCHEMA_FILES_STR" ]; then
	echo "Testing devicetree bindings ${DT_SCHEMA_FILES[*]}"
	"$SCRIPT_DIR"/build.sh "$BOARD" dt_binding_check DT_SCHEMA_FILES="$DT_SCHEMA_FILES_STR"
	"$SCRIPT_DIR"/build.sh "$BOARD" dtbs_check DT_SCHEMA_FILES="$DT_SCHEMA_FILES_STR"
fi
