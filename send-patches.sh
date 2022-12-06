#!/bin/bash

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
  --rfc)
		RFC=1
		shift
		;;
	-c|--cover-letter)
		COVER_LETTER=1
		shift
		;;
	-v|--version)
		VERSION="$2"
		shift
		shift
		;;
	-*|--*)
		echo "Unknown option $1"
		exit 1
		;;
	*)
		POSITIONAL_ARGS+=("$1")
		shift
		;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

COMMITS="$1"

if [[ -z "$COMMITS" ]]; then
	echo "usage: $0 [options] <commits>"
	echo "options:"
	echo "-c|--cover-letter: generate cover letter"
	echo "-v|--version: use specified version when gerating patches"
	exit 1
fi

FILES=$(git diff --name-only $COMMITS)

while read FILE; do
	case "$FILE" in
	*.yaml)
		RELATIVE_YAML=${FILE#Documentation/devicetree/bindings/}
		if [[ "$RELATIVE_YAML" = "$FILE" ]]; then
			echo "$FILE not a devicetree binding, skip check..."
		else
			echo "Testing devicetree binding $FILE"
			make dt_binding_check DT_SCHEMA_FILES="$RELATIVE_YAML"
		fi
		;;
	esac
done <<< "$FILES"

FORMAT_PATCH_CMD="git format-patch"

if [[ -n "$VERSION" ]]; then
	FORMAT_PATCH_CMD+=" -v$VERSION"
fi

if [[ -n "$COVER_LETTER" ]]; then
	FORMAT_PATCH_CMD+=" --cover-letter"
fi

if [[ -n "$RFC" ]]; then
	FORMAT_PATCH_CMD+=" --rfc"
fi

ALL_PATCHES=$($FORMAT_PATCH_CMD "$COMMITS")
if [[ -n "$COVER_LETTER" ]]; then
	COVER_PATCH=$(echo "$ALL_PATCHES" | head -n 1)
	CODE_PATCHES=$(echo "$ALL_PATCHES" | tail -n +2)
else
	CODE_PATCHES="$ALL_PATCHES"
fi

if [[ -n "$COVER_PATCH" ]]; then
	echo "Cover: $COVER_PATCH"
fi
echo "Patches:"
echo "$CODE_PATCHES"

./scripts/checkpatch.pl --strict $CODE_PATCHES

MAINTAINERS=$(./scripts/get_maintainer.pl --norolestats $CODE_PATCHES)
MAINTAINERS_ROLES=$(./scripts/get_maintainer.pl $CODE_PATCHES)
echo 'Maintainers:'
echo "$MAINTAINERS_ROLES"

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

SEND_ARGS=()
while read MAINTAINER; do
	MAINTAINER=$(echo "$MAINTAINER" | tr -d '"')
	SEND_ARGS+=("--cc=$MAINTAINER")
done <<< "$MAINTAINERS"

git send-email "${SEND_ARGS[@]}" $ALL_PATCHES
