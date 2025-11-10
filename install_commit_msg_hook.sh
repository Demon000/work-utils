#!/bin/bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

cp "$SCRIPT_DIR/commit-msg" .git/hooks/commit-msg
chmod u+x .git/hooks/commit-msg
