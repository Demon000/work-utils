#!/bin/bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

. "$SCRIPT_DIR/commit-utils.sh"
. "$SCRIPT_DIR/dtb-utils.sh"
. "$SCRIPT_DIR/board-utils.sh"

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

if has_patches "$@"; then
	mapfile -t FILES < <(extract_patches_modified_files "$@")
	FILES=$(extract_patches_modified_files "$@")
	./scripts/checkpatch.pl --strict --ignore "GERRIT_CHANGE_ID" "${FILES[@]}"
else
	mapfile -t FILES < <(extract_commits_modified_files "$@")
	./scripts/checkpatch.pl --strict --ignore "GERRIT_CHANGE_ID" -g "$@"
fi

echo

install_dtschema

DT_SCHEMA_FILES=()
DT_COMPATIBLES=()
for FILE in "${FILES[@]}"; do
	case "$FILE" in
	*.yaml)
		RELATIVE_YAML="${FILE#Documentation/devicetree/bindings/}"
		if [[ "$RELATIVE_YAML" = "$FILE" ]]; then
			echo "$FILE not under Documentation/devicetree/bindings/, skip check..."
		else
			DT_SCHEMA_FILES+=("$RELATIVE_YAML")

			while IFS= read -r COMPATIBLE; do
				DT_COMPATIBLES+=( "$COMPATIBLE" )
			done < <( "$SCRIPT_DIR/extract_compatibles.py" "$FILE" )
		fi
		;;
	esac
done

DT_SCHEMA_FILES_STR=$(IFS=: ; echo "${DT_SCHEMA_FILES[*]}")

if [ -n "$DT_SCHEMA_FILES_STR" ]; then
	echo "Testing devicetree bindings ${DT_SCHEMA_FILES[*]}"
	"$SCRIPT_DIR/build.sh" "$BOARD" dt_binding_check DT_SCHEMA_FILES="$DT_SCHEMA_FILES_STR"
fi

BOARD_ARCH=$(get_board_arch "$BOARD")

while IFS= read -r DTS; do
	echo "$DTS"
	case "$DTS" in
		*/arch/$BOARD_ARCH/boot/dts/*)
			PREFIX="${DTS%%/boot/dts/*}/boot/dts/"
			REL="${DTS#$PREFIX}"
			;;
		*)
			continue
			;;
	esac

	case "$REL" in
		*.dts)
			TARGET="${REL%.dts}.dtb"
			;;
		*.dtso)
			TARGET="${REL%.dtso}.dtbo"
			;;
		*)
			continue
			;;
	esac

	echo "Checking $DTS"
	"$SCRIPT_DIR/build.sh" "$BOARD" CHECK_DTBS=1 "$TARGET" DT_SCHEMA_FILES="$DT_SCHEMA_FILES_STR"
done < <( "$SCRIPT_DIR/find_compatible_dts.py" "." "${DT_COMPATIBLES[@]}" )
