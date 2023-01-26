#!/bin/bash

#set -o xtrace

SDCARD="$HOME/work/rpi-sdcard"
SDCARD_BOOT="$SDCARD/boot"
BLKDEV="/dev/mmcblk0p1"

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
	-o|--overlay)
		OVERLAYS+=("$2")
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
	echo "usage: $0 <xil|rpi|nv> -d <dtb> -o <overlay> <scp <ip>>|sdcard>"
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
elif [[ "$BOARD_TYPE" = "rpi" ]]; then
	KERNEL_SRC="arch/arm/boot/zImage"
	KERNEL_TARGET="/boot/kernel7l.img"

	DTB_SRC="arch/arm/boot/dts/"
	DTB_TARGET="/boot"

	OVERLAYS_SRC="arch/arm/boot/dts/overlays"
	OVERLAYS_TARGET="/boot/overlays"
elif [[ "$BOARD_TYPE" = "nv" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/Image"

	DTB_PREFIX=kernel_
	DTB_SRC="arch/arm64/boot/dts/nvidia"
	DTB_TARGET="/boot/dtb/"

	OVERLAYS_SRC="$DTB_SRC"
	OVERLAYS_TARGET="/boot"
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
	fi

	IP="$3"

	cp_transfer() {
		SRC="$1"
		TARGET="$2"
		scp "$SRC" "root@$IP:$TARGET"
		if [[ $? -ne 0 ]]; then
			exit 1
		fi
	}
elif [[ "$TRANSFER_MODE" = "sdcard" ]]; then
	cp_transfer() {
		SRC="$1"
		TARGET="$2"
		sudo cp "$SRC" "$SDCARD$TARGET"
		if [[ $? -ne 0 ]]; then
			exit 1
		fi
	}
else
	echo "invalid transfer mode"
	exit 1
fi

if [[ "$TRANSFER_MODE" = "sdcard" ]]; then
	mkdir -p "$SDCARD"
	mkdir -p "$SDCARD_BOOT"

	sudo mount "$BLKDEV" "$SDCARD_BOOT"
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

if [[ "$TRANSFER_MODE" = "sdcard" ]]; then
	sudo umount "$SDCARD_BOOT"
fi

if [[ "$TRANSFER_MODE" = "scp" ]]; then
	ssh "root@$IP" reboot
fi
