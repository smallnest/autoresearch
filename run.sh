#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"
VENV_PYTHON="$SCRIPT_DIR/.venv/bin/python"

if [ -x "$VENV_PYTHON" ]; then
    PYTHON_BIN="$VENV_PYTHON"
else
    PYTHON_BIN="${PYTHON:-python3}"
fi

exec "$PYTHON_BIN" -m autoresearch.cli "$@"
