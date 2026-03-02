SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

. "$SCRIPT_DIR/venv/bin/activate"
"$SCRIPT_DIR/com_wrapper/run.py" "$@"
