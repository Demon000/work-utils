SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

install_dtschema() {
	if [[ ! -d "$SCRIPT_DIR/venv" ]]; then
		python3 -m venv "$SCRIPT_DIR/venv"
	fi

	. "$SCRIPT_DIR/venv/bin/activate"
	pip install --upgrade dtschema > /dev/null 2>&1
}
