#!/bin/bash

POSITIONAL_ARGS=()
DTBS=()
OVERLAYS=()

while [[ $# -gt 0 ]]; do
	case $1 in
	-d|--dtb)
		DTBS+=("$2")
		shift
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
	echo "usage: $0 <xil|rpi3|rpi4|rpi4-64|nv> [-d <dtb>] [-o <overlay>] [-m <modules_path>] <scp <ip>>"
	exit 1
}

if [[ $# -lt 2 ]]; then
	print_usage
fi

BOARD_TYPE="$1"
TRANSFER_MODE="$2"

if [[ "$BOARD_TYPE" = "xil" ]]; then
	KERNEL_SRC="arch/arm/boot/uImage"
	KERNEL_TARGET="/boot/uImage"

	DTB_SINGLE=1
	DTB_SRC="arch/arm/boot/dts"
	DTB_TARGET="/boot"
	DTB_TARGET_NAME="devicetree.dtb"
elif [[ "$BOARD_TYPE" = "rpi3" ]]; then
	KERNEL_SRC="arch/arm/boot/zImage"
	KERNEL_TARGET="/boot/kernel7.img"

	DTB_SRC="arch/arm/boot/dts/"
	DTB_TARGET="/boot"

	OVERLAYS_SRC="arch/arm/boot/dts/overlays"
	OVERLAYS_TARGET="/boot/overlays"
elif [[ "$BOARD_TYPE" = "rpi4" ]]; then
	KERNEL_SRC="arch/arm/boot/zImage"
	KERNEL_TARGET="/boot/kernel7l.img"

	DTB_SRC="arch/arm/boot/dts/"
	DTB_TARGET="/boot"

	OVERLAYS_SRC="arch/arm/boot/dts/overlays"
	OVERLAYS_TARGET="/boot/overlays"
elif [[ "$BOARD_TYPE" = "rpi4-64" ]]; then
	KERNEL_SRC="arch/arm/boot/Image"
	KERNEL_TARGET="/boot/kernel8.img"

	DTB_SRC="arch/arm64/boot/dts/"
	DTB_TARGET="/boot"

	OVERLAYS_SRC="arch/arm64/boot/dts/overlays"
	OVERLAYS_TARGET="/boot/overlays"
elif [[ "$BOARD_TYPE" = "nv" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/Image"

	DTB_PREFIX=kernel_
	DTB_SRC="arch/arm64/boot/dts/nvidia"
	DTB_TARGET="/boot/dtb"

	OVERLAYS_SRC="$DTB_SRC"
	OVERLAYS_TARGET="/boot"
elif [[ "$BOARD_TYPE" = "tb-rk3399-vendor-u-boot" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/extlinux/Image"

	DTB_SINGLE=1
	DTB_SRC="arch/arm64/boot/dts/rockchip"
	DTB_TARGET="/boot/extlinux"
	DTB_TARGET_NAME="toybrick.dtb"
else
	print_usage
fi

if [[ "$DTB_SINGLE" -eq "1" ]] && [[ "${#DTBS[@]}" -ne "1" ]]; then
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
		echo "$@"
		ssh "root@$IP" $@
	}
else
	echo "invalid transfer mode"
	exit 1
fi

KERNEL_VERSION_PATH=include/config/kernel.release

if [[ -n "$KERNEL_OUT_PATH" ]]; then
	KERNEL_VERSION_PATH="$KERNEL_OUT_PATH/$KERNEL_VERSION_PATH"
	KERNEL_SRC="$KERNEL_OUT_PATH/$KERNEL_SRC"
	OVERLAYS_SRC="$KERNEL_OUT_PATH/$OVERLAYS_SRC"
	DTB_SRC="$KERNEL_OUT_PATH/$DTB_SRC"
fi

cp_transfer "$KERNEL_SRC" "$KERNEL_TARGET"

for OVERLAY in "${OVERLAYS[@]}"; do
	cp_transfer "$OVERLAYS_SRC"/"$OVERLAY" "$OVERLAYS_TARGET"
done

for DTB in "${DTBS[@]}"; do
	if [[ -n "$DTB_PREFIX" ]]; then
		cp_transfer "$DTB_SRC"/"$DTB" "$DTB_TARGET"/"$DTB_PREFIX""$DTB"
	else
		cp_transfer "$DTB_SRC"/"$DTB" "$DTB_TARGET"/"$DTB_TARGET_NAME"
	fi
done

if [[ -n "$IS_SCP" ]] && [[ -n "$MODULES_PATH" ]]; then
	KERNEL_VERSION=$(cat "$KERNEL_VERSION_PATH")
	rsync -av --checksum --omit-dir-times --delete "$MODULES_PATH/lib/modules/$KERNEL_VERSION" "root@$IP":"/lib/modules/"
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
