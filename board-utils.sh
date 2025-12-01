get_board_arch() {
    BOARD_TYPE="$1"

    if [[ "$BOARD_TYPE" = "rpi3" ]]; then
        ARCH="arm"
    elif [[ "$BOARD_TYPE" = "rpi4" ]]; then
        ARCH="arm"
    elif [[ "$BOARD_TYPE" = "rpi4-64" ]]; then
        ARCH="arm64"
    elif [[ "$BOARD_TYPE" = "rpi5" ]]; then
        ARCH="arm64"
    elif [[ "$BOARD_TYPE" = "arm64" ]]; then
        ARCH="arm64"
    else
        ARCH=""
    fi

    echo "$ARCH"
}
