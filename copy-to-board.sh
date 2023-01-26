#!/bin/bash

#set -o xtrace

SDCARD="$HOME/work/rpi-sdcard"
SDCARD_BOOT="$SDCARD/boot"
BLKDEV="/dev/mmcblk0p1"

print_usage() {
	echo "usage: $0 <xil|rpi> <dtb> <scp <ip>>|sdcard>"
	echo "example: $0 rpi rpi-adxl367.dtbo scp 10.20.30.100"
	echo "example: $0 xil zynq-zc702-adv7511.dtb scp 10.20.30.100"
	echo "example: $0 nv tegra194-p3668-0000-p3509-0000.dtb scp 10.20.30.100"
	exit 1
}

if [[ $# -lt 2 ]]; then
	print_usage
fi

BOARD_TYPE="$1"
DTB="$2"
TRANSFER_MODE="$3"

if [[ "$BOARD_TYPE" = "xil" ]]; then
	KERNEL_SRC="arch/arm/boot/uImage"
	KERNEL_TARGET="/boot/uImage"

	DTB_SRC="arch/arm/boot/dts"
	DTB_TARGET="/boot/devicetree.dtb"
elif [[ "$BOARD_TYPE" = "rpi" ]]; then
	KERNEL_SRC="arch/arm/boot/zImage"
	KERNEL_TARGET="/boot/kernel7l.img"

	OVERLAYS_SRC="arch/arm/boot/dts/overlays"
	OVERLAYS_TARGET="/boot/overlays"
	OVERLAYS="$DTB"
elif [[ "$BOARD_TYPE" = "nv" ]]; then
	KERNEL_SRC="arch/arm64/boot/Image"
	KERNEL_TARGET="/boot/Image"

	DTB_SRC="arch/arm64/boot/dts/nvidia"
	DTB_TARGET="/boot/dtb/kernel_$DTB"
else
	print_usage
fi

if [[ "$TRANSFER_MODE" = "scp" ]]; then
	if [[ $# -lt 3 ]]; then
		print_usage
	fi

	IP="$4"

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

for OVERLAY in $OVERLAYS; do
	cp_transfer "$OVERLAYS_SRC"/"$OVERLAY" "$OVERLAYS_TARGET"
done

if [[ -n "$DTB" ]]; then
	cp_transfer "$DTB_SRC"/"$DTB" "$DTB_TARGET"
fi

if [[ "$TRANSFER_MODE" = "sdcard" ]]; then
	sudo umount "$SDCARD_BOOT"
fi

if [[ "$TRANSFER_MODE" = "scp" ]]; then
	ssh "root@$IP" reboot
fi
