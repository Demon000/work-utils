#!/bin/bash

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
	case $1 in
	-d|--dtbs)
		DTBS=1
		shift
		;;
	-m|--modules)
		MODULES_PATH="$2"
		shift
		shift
		;;
	-h|--headers)
		HEADERS_PATH="$2"
		shift
		shift
		;;
	-s|--source)
		SOURCE_PATH="$2"
		shift
		shift
		;;
	-o|--out)
		KERNEL_OUT_PATH="$2"
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

print_usage() {
	echo "usage: $0 <rpi|rpi64|nv> [target]"
	exit 1
}

if [[ $# -lt 1 ]]; then
	print_usage
fi

BOARD_TYPE="$1"
TARGET="$2"
TARGETS=()
O_OPT=()

if [[ -z "$TARGET" ]]; then
	if [[ "$BOARD_TYPE" = "rpi" ]]; then
		TARGETS+=("zImage")
	elif [[ "$BOARD_TYPE" = "rpi64" ]]; then
		TARGETS+=("Image")
	elif [[ "$BOARD_TYPE" = "nv" ]]; then
		TARGETS+=("Image")
	fi
fi

if [[ "$BOARD_TYPE" = "rpi" ]]; then
	O_OPT+=(ARCH="arm")
	O_OPT+=(KERNEL="kernel7l")
elif [[ "$BOARD_TYPE" = "rpi64" ]]; then
	O_OPT+=(ARCH="arm64")
	O_OPT+=(KERNEL="kernel8")
elif [[ "$BOARD_TYPE" = "nv" ]]; then
	O_OPT+=(LOCALVERSION="-tegra")
	O_OPT+=(ARCH="arm64")
fi

if [[ -n "$SOURCE_PATH" ]]; then
	O_OPT+=(-C "${source_dir}")
fi

if [[ -n "$KERNEL_OUT_PATH" ]]; then
	O_OPT+=(O="${KERNEL_OUT_PATH}")
fi

if [[ -n "$MODULES_PATH" ]]; then
	TARGETS+=("modules")
	O_OPT+=(INSTALL_MOD_PATH="${MODULES_PATH}")
fi

if [[ -n "$HEADERS_PATH" ]]; then
	TARGETS+=("headers")
	O_OPT+=(INSTALL_HDR_PATH="${HEADERS_PATH}")
fi

if [[ -n "$DTBS" ]]; then
	TARGETS+=("dtbs")
fi

NPROC=$(nproc)

make -j"$NPROC" ${TARGETS[@]}
if [[ $? -ne 0 ]]; then
	exit
fi

if [[ -n "$MODULES_PATH" ]]; then
	rm -rf "$MODULES_PATH"
	mkdir -p "$MODULES_PATH"
	make -j"$NPROC" "${O_OPT[@]}" modules_install
fi

if [[ -n "$HEADERS_PATH" ]]; then
	rm -rf "$HEADERS_PATH"
	mkdir -p "$HEADERS_PATH"
	make -j"$NPROC" "${O_OPT[@]}" headers_install
fi
