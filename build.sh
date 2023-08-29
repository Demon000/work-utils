#!/bin/bash

POSITIONAL_ARGS=()

print_usage() {
	echo "usage: $0 <board> [options] [target]"
	echo "board:"
	echo "	rpi3: Raspberry Pi 3 32bit"
	echo "	rpi4: Raspberry Pi 4 32bit"
	echo "	rpi4-64: Raspberry Pi 4 64bit"
	echo "	nv: Nvidia"
	echo "	arm64: Basic ARM64 build"
	echo "options:"
	echo "	-d|--dtbs: build dtbs"
	echo "	-m|--modules <modules_path>: build dtbs and install them at the given path"
	echo "	-h|--headers <headers_path>: build headers and install them at the given path"
	echo "	-s|--source <source_path>: kernel source path, use current directory if not given"
	echo "	-o|--out <out_path>: kernel output path, use source path if not given"
	echo "	-l|--localversion <localversion>: kernel local version"

	exit 1
}

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
		print_usage
		exit 1
		;;
	*)
		POSITIONAL_ARGS+=("$1")
		shift
		;;
	esac
done

set -- "${POSITIONAL_ARGS[@]}"

if [[ $# -lt 1 ]]; then
	print_usage
fi

BOARD_TYPE="$1"
shift

IMAGE_TARGET="Image"
ZIMAGE_TARGET="Image"
NV_DISPLAY_TARGET="nv_display"
MODULES_TARGET="modules"
HEADERS_TARGET="modules"
MODULES_INSTALL_TARGET="modules_install"
HEADERS_INSTALL_TARGET="headers_install"

TARGETS=("$@")

if [[ -z "$TARGETS" ]]; then
	AUTO_TARGETS="1"
fi

if [[ -n "$AUTO_TARGETS" ]]; then
	if [[ "$BOARD_TYPE" = "rpi3" ]]; then
		TARGETS+=("$ZIMAGE_TARGET")
	elif [[ "$BOARD_TYPE" = "rpi4" ]]; then
		TARGETS+=("$ZIMAGE_TARGET")
	elif [[ "$BOARD_TYPE" = "rpi4-64" ]]; then
		TARGETS+=("$IMAGE_TARGET")
	elif [[ "$BOARD_TYPE" = "nv" ]]; then
		TARGETS+=("$IMAGE_TARGET")
		TARGETS+=("$NV_DISPLAY_TARGET")

		if [[ -z "$KERNEL_LOCALVERSION" ]]; then
			KERNEL_LOCALVERSION="-tegra"
		fi
	elif [[ "$BOARD_TYPE" = "arm64" ]]; then
		TARGETS+=("$IMAGE_TARGET")
	fi

	if [[ -n "$MODULES_PATH" ]]; then
		TARGETS+=("$MODULES_TARGET")
		TARGETS+=("$MODULES_INSTALL_TARGET")
	fi

	if [[ -n "$HEADERS_PATH" ]]; then
		TARGETS+=("$HEADERS_TARGET")
		TARGETS+=("$HEADERS_INSTALL_TARGET")
	fi

	if [[ -n "$DTBS" ]]; then
		TARGETS+=("dtbs")
	fi
fi

O_OPT=()

if [[ "$BOARD_TYPE" = "rpi3" ]]; then
	O_OPT+=(ARCH="arm")
	O_OPT+=(KERNEL="kernel7")
elif [[ "$BOARD_TYPE" = "rpi4" ]]; then
	O_OPT+=(ARCH="arm")
	O_OPT+=(KERNEL="kernel7l")
elif [[ "$BOARD_TYPE" = "rpi4-64" ]]; then
	O_OPT+=(ARCH="arm64")
	O_OPT+=(KERNEL="kernel8")
elif [[ "$BOARD_TYPE" = "nv" ]]; then
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

if [[ -z "$SOURCE_PATH" ]]; then
	SOURCE_PATH="."
fi

if [[ -n "$KERNEL_OUT_PATH" ]]; then
	O_OPT+=(O="${KERNEL_OUT_PATH}")
fi

if [[ -z "$KERNEL_OUT_PATH" ]]; then
	KERNEL_OUT_PATH="$SOURCE_PATH"
fi

if [[ -n "$CROSS_COMPILE" ]]; then
	O_OPT+=(CROSS_COMPILE="$CROSS_COMPILE")
fi

O_OPT+=(-j$(nproc))

echo "Targets: ${TARGETS[@]}"
echo "Options: ${O_OPT[@]}"

INITIAL_TARGETS=()

for TARGET in "${TARGETS[@]}"
do
	case "$TARGET" in
	"$MODULES_TARGET")
		BUILD_MODULES=1
		;;
	"$HEADERS_TARGET")
		BUILD_HEADERS=1
		;;
	"$NV_DISPLAY_TARGET")
		BUILD_NV_DISPLAY=1
		;;
	"$MODULES_INSTALL_TARGET")
		INSTALL_MODULES=1
		;;
	"$HEADERS_INSTALL_TARGET")
		INSTALL_HEADERS=1
		;;
	*)
		INITIAL_TARGETS+=("$TARGET")
		;;
	esac
done

TARGETS=("${INITIAL_TARGETS[@]}")

START_TIME=$(date +%s.%N)

if [ ${#TARGETS[@]} -ne 0 ]; then
	make "${O_OPT[@]}" "${TARGETS[@]}"
	if [[ $? -ne 0 ]]; then
		exit
	fi
fi

NV_DISPLAY_PATH="../../tegra/kernel-src/nv-kernel-display-driver/NVIDIA-kernel-module-source-TempVersion"

KERNEL_SRC_PATH_ABS=$(realpath "$SOURCE_PATH")
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

build_modules() {
	local dir_path="$1"
	shift

	local opts=("$@")

	if [[ -n "$dir_path" ]]; then
		pushd "$dir_path"
	fi

	make "${O_OPT[@]}" "${opts[@]}" "$MODULES_TARGET"

	if [[ -n "$dir_path" ]]; then
		popd
	fi
}

build_nv_display_modules() {
	build_modules "$NV_DISPLAY_PATH" "${NV_DISPLAY_O_OPT[@]}"
}

build_headers() {
	make "${O_OPT[@]}" "$HEADERS_TARGET"
}

install_modules() {
	local modules_path="$1"
	shift

	local dir_path="$1"
	shift

	local opts=("$@")

	local mod_path_arg
	local mod_strip_arg

	if [[ -n "$modules_path" ]]; then
		rm -rf "$modules_path"
		mkdir -p "$modules_path"
		modules_path_abs=$(realpath "$modules_path")
		mod_path_arg="INSTALL_MOD_PATH=${modules_path_abs}"
		mod_strip_arg="INSTALL_MOD_STRIP=1"
	fi

	if [[ -n "$dir_path" ]]; then
		pushd "$dir_path"
	fi

	make "${O_OPT[@]}" "${opts[@]}" "$mod_path_arg" "$mod_strip_arg" "$MODULES_INSTALL_TARGET"

	if [[ -n "$dir_path" ]]; then
		popd
	fi
}

install_nv_display_modules() {
	local modules_path="$1"
	shift

	# To get the same output as Nvidia does when installing the display
	# module, set INSTALL_MOD_DIR line in kernel-open/Makefile to
	# KBUILD_PARAMS += INSTALL_MOD_DIR=extra/opensrc-disp
	install_modules "$modules_path" "$NV_DISPLAY_PATH" "${NV_DISPLAY_O_OPT[@]}"
}

install_headers() {
	local headers_path="$1"
	shift

	local hdr_path_arg

	if [[ -n "$headers_path" ]]; then
		rm -rf "$headers_path"
		mkdir -p "$headers_path"
		headers_path_abs=$(realpath "$headers_path")
		hdr_path_arg="INSTALL_HDR_PATH=${headers_path_abs}"
	fi

	make "${O_OPT[@]}" "$hdr_path_arg" "$HEADERS_INSTALL_TARGET"
}

if [[ -n "$BUILD_MODULES" ]]; then
	build_modules

	if [[ -n "$BUILD_NV_DISPLAY" ]]; then
		build_nv_display_modules
	fi
fi

if [[ -n "$BUILD_HEADERS" ]]; then
	build_headers
fi

if [[ -n "$INSTALL_MODULES" ]]; then
	install_modules "$MODULES_PATH"

	if [[ -n "$BUILD_NV_DISPLAY" ]]; then
		# To get the same output as Nvidia does when installing the display
		# module, set INSTALL_MOD_DIR line in kernel-open/Makefile to
		# KBUILD_PARAMS += INSTALL_MOD_DIR=extra/opensrc-disp
		install_nv_display_modules "$MODULES_PATH"
	fi
fi

if [[ -n "$INSTALL_HEADERS" ]]; then
	install_headers "$HEADERS_PATH"
fi

END_TIME=$(date +%s.%N)
RUN_TIME=$(echo "$END_TIME - $START_TIME" | bc -l)

echo "Run time: $RUN_TIME"
