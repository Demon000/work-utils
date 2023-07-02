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
	-l|--localversion)
		KERNEL_LOCALVERSION="$2"
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
shift

TARGETS=("$@")
O_OPT=()

if [[ -z "$TARGETS" ]]; then
	AUTO_TARGETS="1"
fi

if [[ -n "$AUTO_TARGETS" ]]; then
	if [[ "$BOARD_TYPE" = "rpi" ]]; then
		TARGETS+=("zImage")
	elif [[ "$BOARD_TYPE" = "rpi64" ]]; then
		TARGETS+=("Image")
	elif [[ "$BOARD_TYPE" = "nv" ]]; then
		TARGETS+=("Image")
		BUILD_NV_DISPLAY=1
	elif [[ "$BOARD_TYPE" = "arm64" ]]; then
		TARGETS+=("Image")
	fi

	if [[ -n "$MODULES_PATH" ]]; then
		TARGETS+=("modules")
		MODULES_PATH_ABS=$(realpath "$MODULES_PATH")
		O_OPT+=(INSTALL_MOD_PATH="${MODULES_PATH_ABS}")
		O_OPT+=(INSTALL_MOD_STRIP=1)
	fi

	if [[ -n "$HEADERS_PATH" ]]; then
		TARGETS+=("headers")
		HEADERS_PATH_ABS=$(realpath "$HEADERS_PATH")
		O_OPT+=(INSTALL_HDR_PATH="${HEADERS_PATH_ABS}")
	fi

	if [[ -n "$DTBS" ]]; then
		TARGETS+=("dtbs")
	fi
fi

if [[ "$BOARD_TYPE" = "rpi" ]]; then
	O_OPT+=(ARCH="arm")
	O_OPT+=(KERNEL="kernel7l")
elif [[ "$BOARD_TYPE" = "rpi64" ]]; then
	O_OPT+=(ARCH="arm64")
	O_OPT+=(KERNEL="kernel8")
elif [[ "$BOARD_TYPE" = "nv" ]]; then
	if [[ -z "$KERNEL_LOCALVERSION" ]]; then
		KERNEL_LOCALVERSION="-tegra"
	fi
	O_OPT+=(ARCH="arm64")
elif [[ "$BOARD_TYPE" = "arm64" ]]; then
	O_OPT+=(ARCH="arm64")
fi

if [[ -n "$KERNEL_LOCALVERSION" ]]; then
	O_OPT+=(LOCALVERSION="$KERNEL_LOCALVERSION")
fi

if [[ -n "$SOURCE_PATH" ]]; then
	O_OPT+=(-C "${SOURCE_PATH}")
fi

if [[ -n "$KERNEL_OUT_PATH" ]]; then
	O_OPT+=(O="${KERNEL_OUT_PATH}")
fi

if [[ -n "$CROSS_COMPILE" ]]; then
	O_OPT+=(CROSS_COMPILE="$CROSS_COMPILE")
fi

O_OPT+=(-j$(nproc))

echo "Targets: ${TARGETS[@]}"
echo "Options: ${O_OPT[@]}"

make "${O_OPT[@]}" "${TARGETS[@]}"
if [[ $? -ne 0 ]]; then
	exit
fi

NV_DISPLAY_PATH="../../tegra/kernel-src/nv-kernel-display-driver/NVIDIA-kernel-module-source-TempVersion"

if [[ -z KERNEL_OUT_PATH ]]; then
	KERNEL_OUT_PATH="."
fi

KERNEL_SRC_PATH_ABS=$(realpath .)
KERNEL_OUT_PATH_ABS=$(realpath "$KERNEL_OUT_PATH")

NV_DISPLAY_O_OPT=(
	"SYSSRC=$KERNEL_SRC_PATH_ABS"
	"SYSOUT=$KERNEL_OUT_PATH_ABS"
	"CC=${CROSS_COMPILE}gcc"
	"LD=${CROSS_COMPILE}ld"
	"AR=${CROSS_COMPILE}ar"
	"CXX=${CROSS_COMPILE}g++"
	"OBJCOPY=${CROSS_COMPILE}objcopy"
	"TARGET_ARCH=aarch64"
)

if [[ -n "BUILD_NV_DISPLAY" ]]; then
	pushd "$NV_DISPLAY_PATH"

	echo "Nvidia options: ${NV_DISPLAY_O_OPT[@]}"

	make "${O_OPT[@]}" "${NV_DISPLAY_O_OPT[@]}" modules
	if [[ $? -ne 0 ]]; then
		exit 1
	fi

	popd
fi

if [[ -n "$AUTO_TARGETS" ]]; then
	if [[ -n "$MODULES_PATH" ]]; then
		rm -rf "$MODULES_PATH"
		mkdir -p "$MODULES_PATH"
		make "${O_OPT[@]}" modules_install
	fi

	if [[ -n "BUILD_NV_DISPLAY" ]]; then
		pushd "$NV_DISPLAY_PATH"

		# To get the same output as Nvidia does when installing the display
		# module, set INSTALL_MOD_DIR line in kernel-open/Makefile to
		# KBUILD_PARAMS += INSTALL_MOD_DIR=extra/opensrc-disp
		make "${O_OPT[@]}" "${NV_DISPLAY_O_OPT[@]}" modules_install

		popd
	fi

	if [[ -n "$HEADERS_PATH" ]]; then
		rm -rf "$HEADERS_PATH"
		mkdir -p "$HEADERS_PATH"
		make "${O_OPT[@]}" headers_install
	fi
fi
