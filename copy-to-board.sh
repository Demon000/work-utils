#!/bin/bash

POSITIONAL_ARGS=()
DTBS=()
OVERLAYS=()
OVERLAY_REL_PATHS=()

while [[ $# -gt 0 ]]; do
	case $1 in
	-d|--dtb)
		DTBS+=("$2")
		shift
		shift
		;;
	--dtbs)
		ALL_DTBS=1
		shift
		;;
	-v|--overlay)
		OVERLAYS+=("$2")
		shift
		shift
		;;
	-m|--modules)
		MODULES_PATH="$2"
		shift
		shift
		;;
	-o|--out)
		KERNEL_OUT_PATH="$2"
		shift
		shift
		;;
	--all-overlays)
		ALL_OVERLAYS=1
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

usage="usage: $0 <board> [options] <disk <path>|scp <ip>>
board:
	xil: Xilinx board
	rpi3: Raspberry Pi 3 (32-bit)
	rpi4: Raspberry Pi 4 (32-bit)
	rpi4-64: Raspberry Pi 4 (64-bit)
	rpi5: Raspberry Pi 5 (64-bit)
	imx8mp-hummingboard-pulse: IMX8MP Hummingboard Pulse
	tb-rk3399-vendor-u-boot: Toybrick RK3399 ProX
options:
	-d|--dtb <dtb>: copy the specified dtb
	--all-dtbs: copy all dtbs
	-v|--overlay <overlay>: copy the specified overlay
	--all-overlays: copy all overlays
	-o|--out <kernel_out_path>: specify kernel out path
	-m|--modules <modules_path>: specify modules out path
"

print_usage() {
	echo "$usage"
	exit 1
}


rsync_transfer_common() {
	SRC="$1"
	TARGET="$2"
	rsync -av --checksum --omit-dir-times --delete "$SRC" "$TARGET"
	if [[ $? -ne 0 ]]; then
		exit 1
	fi
}

rsync_transfer_file_arr_common() {
	SRC="$1"
	shift
	TARGET="$1"
	shift
	PATHS=("$@")

	RSYNC_TMP_FILE=$(mktemp)
	printf "%s\n" "${PATHS[@]}" > "$RSYNC_TMP_FILE"
	rsync -av --checksum --omit-dir-times --files-from="$RSYNC_TMP_FILE" --no-relative --no-owner --no-group "$SRC" "$TARGET"
	rm "$RSYNC_TMP_FILE"
}

if [[ $# -lt 2 ]]; then
	print_usage
fi

BOARD_TYPE="$1"
TRANSFER_MODE="$2"

KERNEL_VERSION_PATH=include/config/kernel.release

if [[ "$BOARD_TYPE" = "xil" ]]; then
	KERNEL_SRC="arch/arm/boot/uImage"
	KERNEL_TARGET="/boot/uImage"

	DTB_SRC="arch/arm/boot/dts"
	DTB_TARGET="/boot"
	DTB_TARGET_NAME="devicetree.dtb"
elif [[ "$BOARD_TYPE" = "rpi3" ]]; then
	KERNEL_SRC="arch/arm/boot/zImage"
	KERNEL_TARGET="/boot/kernel7.img"

	DTB_SRC="arch/arm/boot/dts/"
	DTB_TARGET="/boot"

	OVERLAYS_SRC="arch/arm/boot/dts"
	OVERLAYS_TARGET="/boot/overlays"
elif [[ "$BOARD_TYPE" = "rpi4" ]]; then
	KERNEL_SRC="arch/arm/boot/zImage"
	KERNEL_TARGET="/boot/firmware/kernel7l.img"

	DTB_SRC="arch/arm/boot/dts/broadcom"
	DTB_TARGET="/boot/firmware"

	OVERLAYS_SRC="arch/arm/boot/dts"
	OVERLAYS_TARGET="/boot/firmware/overlays"
elif [[ "$BOARD_TYPE" = "rpi4-64" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/firmware/kernel8.img"

	DTB_SRC="arch/arm64/boot/dts/broadcom"
	DTB_TARGET="/boot/firmware"

	OVERLAYS_SRC="arch/arm64/boot/dts"
	OVERLAYS_TARGET="/boot/firmware/overlays"
elif [[ "$BOARD_TYPE" = "rpi5" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/firmware/kernel_2712.img"

	DTB_SRC="arch/arm64/boot/dts/broadcom"
	DTB_TARGET="/boot/firmware"

	OVERLAYS_SRC="arch/arm64/boot/dts"
	OVERLAYS_TARGET="/boot/firmware/overlays"
elif [[ "$BOARD_TYPE" = "imx8mp-hummingboard-pulse" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/Image"

	DTB_SRC="arch/arm64/boot/dts/freescale"
	DTB_TARGET="/boot"
	DTB_TARGET_NAME="imx8mp-hummingboard-pulse.dtb"
elif [[ "$BOARD_TYPE" = "tb-rk3399-vendor-u-boot" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/extlinux/Image"

	DTB_SRC="arch/arm64/boot/dts/rockchip"
	DTB_TARGET="/boot/extlinux"
	DTB_TARGET_NAME="toybrick.dtb"
elif [[ "$BOARD_TYPE" = "arm64" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/Image"

	DTB_SRC="arch/arm64/boot/dts"
	DTB_TARGET="/boot/dtbs"
else
	print_usage
fi

if [[ -n "$DTB_TARGET_NAME" ]] && [[ "${#DTBS[@]}" -ne "1" ]]; then
	echo "Board does not support multiple DTBs"
	exit 1
fi

if [[ "$TRANSFER_MODE" = "scp" ]]; then
	if [[ $# -lt 3 ]]; then
		print_usage
		exit 1
	fi

	IS_SCP=1

	IP="$3"

	cp_transfer() {
		SRC="$1"
		TARGET="$2"
		echo "Copy $SRC to $TARGET"
		scp "$SRC" "root@$IP:$TARGET"
		if [[ $? -ne 0 ]]; then
			exit 1
		fi
	}

	cmd() {
		ssh "root@$IP" "$1"
	}

	rsync_transfer() {
		SRC="$1"
		TARGET="$2"
		rsync_transfer_common "$SRC" "root@$IP":"$TARGET"
	}

	rsync_transfer_file_arr() {
		SRC="$1"
		shift
		TARGET="$1"
		shift
		PATHS=("$@")
		rsync_transfer_file_arr_common "$SRC" "root@$IP":"$TARGET" "${PATHS[@]}"
	}
elif [[ "$TRANSFER_MODE" = "disk" ]]; then
	if [[ $# -lt 3 ]]; then
		print_usage
		exit 1
	fi

	IS_DISK=1

	DEST_PATH="$3"

	cp_transfer() {
		SRC="$1"
		TARGET="$2"
		echo "Copy $SRC to $TARGET"
		cp "$SRC" "$TARGET"
		if [[ $? -ne 0 ]]; then
			exit 1
		fi
	}

	rsync_transfer() {
		SRC="$1"
		TARGET="$2"
		rsync_transfer_common "$SRC" "$DEST_PATH$TARGET"
	}

	rsync_transfer_file_arr() {
		SRC="$1"
		shift
		TARGET="$1"
		shift
		PATHS=("$@")
		rsync_transfer_file_arr_common "$SRC" "$DEST_PATH$TARGET" "${PATHS[@]}"
	}
else
	echo "invalid transfer mode"
	exit 1
fi

if [[ -z "$SOURCE_PATH" ]]; then
	SOURCE_PATH="."
fi

SOURCE_PATH_ABS=$(realpath "$SOURCE_PATH")
SOURCE_PATH_NAME=$(basename "$SOURCE_PATH_ABS")
if ! [[ -v KERNEL_OUT_PATH ]]; then
	KERNEL_OUT_PATH="$SOURCE_PATH/../kernel_out-$SOURCE_PATH_NAME"
fi
if ! [[ -v MODULES_PATH ]]; then
	MODULES_PATH="$SOURCE_PATH/../modules_out-$SOURCE_PATH_NAME"
fi

KERNEL_VERSION_PATH="$KERNEL_OUT_PATH/$KERNEL_VERSION_PATH"
KERNEL_SRC="$KERNEL_OUT_PATH/$KERNEL_SRC"
OVERLAYS_SRC="$KERNEL_OUT_PATH/$OVERLAYS_SRC"
DTB_SRC="$KERNEL_OUT_PATH/$DTB_SRC"

cp_transfer "$KERNEL_SRC" "$KERNEL_TARGET"

pushd "$OVERLAYS_SRC" > /dev/null
if [[ ${#OVERLAYS[@]} -ne 0 ]]; then
	echo "Copy ${OVERLAYS[@]} from $OVERLAYS_SRC"

	for OVERLAY in "${OVERLAYS[@]}"; do
		OVERLAY_REL_PATH=$(find -name "$OVERLAY")
		if [[ -z "$OVERLAY_REL_PATH" ]]; then
			echo "Failed to find $OVERLAY in $OVERLAYS_SRC"
			continue
		fi

		OVERLAY_REL_PATHS+=("$OVERLAY_REL_PATH")
	done
fi

if [[ -n "$ALL_OVERLAYS" ]]; then
	echo "Copy all overlays from $OVERLAYS_SRC"

	while IFS= read -d $'\0' -r OVERLAY; do
		OVERLAY_REL_PATHS+=("$OVERLAY")
	done < <(find -name "*.dtbo" -print0)
fi
popd > /dev/null

if [[ ${#OVERLAY_REL_PATHS[@]} -ne 0 ]]; then
	rsync_transfer_file_arr "$OVERLAYS_SRC" "$OVERLAYS_TARGET" "${OVERLAY_REL_PATHS[@]}"
fi

pushd "$DTB_SRC" > /dev/null
if [[ ${#DTBS[@]} -ne 0 ]]; then
	echo "Copy ${DTBS[@]} from $DTB_SRC"

	for DTB in "${DTBS[@]}"; do
		DTB_REL_PATH=$(find -name "$DTB")
		if [[ -z "$DTB_REL_PATH" ]]; then
			echo "Failed to find $DTB in $DTB_SRC"
			continue
		fi

		DTB_REL_PATHS+=("$DTB_REL_PATH")
	done
fi

if [[ -n "$ALL_DTBS" ]]; then
	echo "Copy all dtbs from $DTB_SRC"

	while IFS= read -d $'\0' -r DTB; do
		DTB_REL_PATHS+=("$DTB")
	done < <(find -name "*.dtb" -print0)
fi
popd > /dev/null

if [[ ${#DTB_REL_PATHS[@]} -ne 0 ]]; then
	echo "Copy ${DTB_REL_PATHS[@]} from $DTB_SRC"
	rsync_transfer_file_arr "$DTB_SRC" "$DTB_TARGET" "${DTB_REL_PATHS[@]}"
fi

if [[ -n "$MODULES_PATH" ]]; then
	KERNEL_VERSION=$(cat "$KERNEL_VERSION_PATH")
	rsync_transfer "$MODULES_PATH/lib/modules/$KERNEL_VERSION" "/lib/modules/"
fi

if [[ -n "$IS_SCP" ]]; then
	echo "Syncing..."
	cmd sync

	echo "Reboot?"
	select yn in "Yes" "No"; do
		case $yn in
			Yes)
				echo "Rebooting..."
				cmd reboot
				exit
				;;
			No)
				exit
				;;
		esac
	done
fi
