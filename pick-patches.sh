#!/bin/bash

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
	case $1 in
		-n|--no-pick)
		NO_PICK=1
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

ORIGIN_REMOTE="$1"
BASE_BRANCH="$2"
FEATURE_REMOTE="$3"
FEATURE_BASE_BRANCH="$4"
FEATURE_BRANCH="$5"

if [[ -z "$ORIGIN_REMOTE" || \
	  -z "$BASE_BRANCH" || \
	  -z "$FEATURE_REMOTE" || \
	  -z "$FEATURE_BASE_BRANCH" || \
	  -z "$FEATURE_BRANCH" ]]; then
	echo "usage: $0 <origin_remote> <base_branch> <feature_remote> <feature_base_branch> <feature_branch>"
	exit 1
fi

git fetch "$ORIGIN_REMOTE" "$BASE_BRANCH"
git fetch "$FEATURE_REMOTE" "$FEATURE_BASE_BRANCH"
git fetch "$FEATURE_REMOTE" "$FEATURE_BRANCH"

git reset --hard "$ORIGIN_REMOTE/$BASE_BRANCH"

COMMITS="$FEATURE_REMOTE/$FEATURE_BASE_BRANCH...$FEATURE_REMOTE/$FEATURE_BRANCH"

COMMIT_IDS=$(git log --reverse --pretty=format:"%h" "$COMMITS")

while read COMMIT_ID; do
	COMMIT_TITLE=$(git show --no-patch --pretty=format:%s "$COMMIT_ID")

	case "$COMMIT_TITLE" in
		Kconfig.adi*)
			echo "Skip Kconfig.adi commit '$COMMIT_TITLE'"
			;;
		\[COMPAT\]*)
			echo "Skip compat commit '$COMMIT_TITLE'"
			;;
		"arch: arm: dts: overlays"*)
			echo "Skip dts commit '$COMMIT_TITLE'"
			;;
		*)
			echo "Picking commit '$COMMIT_TITLE'"
			if [[ -z "$NO_PICK" ]]; then
				git cherry-pick "$COMMIT_ID"
			fi
			;;
	esac
done <<< "$COMMIT_IDS"
