#!/bin/bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

. "$SCRIPT_DIR/commit-utils.sh"
. "$SCRIPT_DIR/meta-utils.sh"
. "$SCRIPT_DIR/dtb-utils.sh"
. "$SCRIPT_DIR/print-utils.sh"

print_help() {
	echo "usage: $0 [options] <board> <commits>"
	echo "board: passed to check-patches.sh"
	echo "commits: commit range to generate patches from"
	echo "options:"
	echo "-c|--cover-letter: generate cover letter"
	echo "-v|--version: use specified version when gerating patches"
	echo "-o|--output <output_path>: save patches to the specified output path"
	echo "--prefix <subject_prefix>: add the specified prefix to the subject"
	echo "--rfc: generate patches in rfc mode"
	echo "--resend: generate patches in resend mode"
}

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
	case $1 in
	--rfc)
		RFC=1
		shift
		;;
	--resend)
		RESEND=1
		shift
		;;
	-c | --cover-letter)
		COVER_LETTER=1
		shift
		;;
	-v | --version)
		VERSION="$2"
		shift
		shift
		;;
	-v*)
		VERSION="${1#-v}"
		shift
		;;
	-o | --output)
		OUTPUT_PATH="$2"
		shift
		shift
		;;
	-p | --prefix)
		SUBJECT_PREFIX="$2"
		shift
		shift
		;;
	-h | --help)
		print_help
		exit 0
		;;
	*)
		POSITIONAL_ARGS+=("$1")
		shift
		;;
	esac
done

set -- "${POSITIONAL_ARGS[@]}"

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

"$SCRIPT_DIR"/check-patches.sh "$BOARD" "$COMMITS"

for COMMIT in $(git rev-list "$COMMITS"); do
	TITLE=$(git log -1 --pretty=format:%s "$COMMIT")
	MESSAGE=$(git log -1 --pretty=format:%b "$COMMIT")
	if [[ "$MESSAGE" != *"Signed-off-by:"* ]]; then
		red "Commit $COMMIT ($TITLE) is missing Signed-off-by line."
		exit 1
	fi
	if [[ "$MESSAGE" == *"Reviewed-by:"* && -z "$VERSION" ]]; then
		red "Commit $COMMIT ($TITLE) has Reviewed-by line on V0."
		exit 1
	fi

	CHANGE_ID=$(get_git_change_id "$COMMIT")
	if [[ -z "$CHANGE_ID" ]]; then
		continue
	fi

	META_CONTENT=$(get_change_id_meta_content "$CHANGE_ID")
	if [ -n "$META_CONTENT" ]; then
		insert_after_separator "$CODE_PATCH" "$META_CONTENT"
	fi

	if [[ -z "$VERSION" && "$META_CONTENT" =~ ^V[0-9]+: ]]; then
		red "Commit $COMMIT ($TITLE) has version notes on V0."
		exit 1
	fi
	if [[ -n "$VERSION" && ! ( "$META_CONTENT" =~ ^V$VERSION: ) ]]; then
		red "Commit $COMMIT ($TITLE) has no version notes for V$VERSION."
	fi
done

FORMAT_PATCH_ARGS=()

if [[ -z "$COVER_LETTER" ]]; then
	COUNT=$(git rev-list --count "$COMMITS")
	if [[ "$COUNT" -gt 1 ]]; then
		COVER_LETTER=1
	fi
fi

if [[ -n "$VERSION" ]]; then
	FORMAT_PATCH_ARGS+=("-v" "$VERSION")
fi
if [[ -n "$COVER_LETTER" ]]; then
	FORMAT_PATCH_ARGS+=("--cover-letter")
fi
if [[ -n "$RFC" ]]; then
	FORMAT_PATCH_ARGS+=("--rfc")
fi
if [[ -n "$RESEND" ]]; then
	FORMAT_PATCH_ARGS+=("--resend")
fi
if [[ -n "$SUBJECT_PREFIX" ]]; then
	FORMAT_PATCH_ARGS+=("--subject-prefix" "$SUBJECT_PREFIX")
fi
if [[ -n "$OUTPUT_PATH" ]]; then
	FORMAT_PATCH_ARGS+=("-o" "$OUTPUT_PATH")
fi

ALL_PATCHES=$(git format-patch "${FORMAT_PATCH_ARGS[@]}" "$COMMITS")
if [[ -n "$COVER_LETTER" ]]; then
	COVER_PATCH=$(echo "$ALL_PATCHES" | head -n 1)
	CODE_PATCHES=$(echo "$ALL_PATCHES" | tail -n +2)
else
	CODE_PATCHES="$ALL_PATCHES"
fi

while IFS= read -r CODE_PATCH; do
	CHANGE_ID=$(cat "$CODE_PATCH" | get_change_id)
	if [[ -z "$CHANGE_ID" ]]; then
		continue
	fi

	remove_change_id_from_file "$CODE_PATCH"

	META_CONTENT=$(get_change_id_meta_content "$CHANGE_ID")
	if [ -n "$META_CONTENT" ]; then
		insert_after_separator "$CODE_PATCH" "$META_CONTENT"
	fi
done <<<"$CODE_PATCHES"

if [[ -n "$COVER_PATCH" ]]; then
	echo "Cover: $COVER_PATCH"
fi
echo "Patches:"
echo "$CODE_PATCHES"

echo "Select who to send the patches to."
TOS=$(./scripts/get_maintainer.pl --interactive --norolestats -nol $CODE_PATCHES)

echo "Select who to cc the patches to."
CCS=$(./scripts/get_maintainer.pl --interactive --norolestats -nom $CODE_PATCHES)
echo 'To:'
echo "$TOS"
echo 'Cc:'
echo "$CCS"

SEND_ARGS=()
while read TO; do
	TO=$(echo "$TO" | tr -d '"')
	SEND_ARGS+=("--to=$TO")
done <<<"$TOS"
while read CC; do
	CC=$(echo "$CC" | tr -d '"')
	SEND_ARGS+=("--cc=$CC")
done <<<"$CCS"

echo "Do you wish to send the patches?"
select yn in "Yes" "No"; do
	case $yn in
	Yes)
		break
		;;
	No)
		exit
		;;
	esac
done

git send-email "$@" "${SEND_ARGS[@]}" $ALL_PATCHES
