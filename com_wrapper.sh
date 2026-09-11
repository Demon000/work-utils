SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
VENV_DIR="$SCRIPT_DIR/venv"

if [ ! -f "$VENV_DIR/bin/activate" ]; then
	python3 -m venv "$VENV_DIR"
	"$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
fi

. "$VENV_DIR/bin/activate"
"$SCRIPT_DIR/com_wrapper/run.py" "$@"
