#!/bin/bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

print_help() {
	echo "usage: $0 [options] <commits>"
}

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
pip install --upgrade dtschema

while read FILE; do
	case "$FILE" in
	*.yaml)
		RELATIVE_YAML="${FILE#Documentation/devicetree/bindings/}"
		if [[ "$RELATIVE_YAML" = "$FILE" ]]; then
			echo "$FILE not under Documentation/devicetree/bindings/, skip check..."
		else
			echo "Testing devicetree binding $FILE"
			make dt_binding_check DT_SCHEMA_FILES="$RELATIVE_YAML"
			make dtbs_check DT_SCHEMA_FILES="$RELATIVE_YAML"
		fi
		;;
	*.dts|*.dtso)
		RELATIVE_DTS="${FILE#arch/arm64/boot/dts/}"
		if [[ "$RELATIVE_DTS" = "$FILE" ]]; then
			echo "$FILE not under arch/arm64/boot/dts/, skip check..."
		else
			echo "Testing devicetree source $FILE"
			make CHECK_DTBS=1 "$RELATIVE_DTS"
		fi
		;;
	esac
done <<< "$FILES"
