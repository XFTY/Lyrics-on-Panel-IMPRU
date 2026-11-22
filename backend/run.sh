#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

VENV_PY=".venv/bin/python"
if [ ! -x "$VENV_PY" ]; then
    printf 'lyrics-on-panel: Python virtual environment missing at %s; rerun install.sh\n' "$PWD/.venv" >&2
    exit 1
fi

if ! "$VENV_PY" -c 'import dbus, websockets' >/dev/null 2>&1; then
    printf 'lyrics-on-panel: Python packages are missing from %s; rerun install.sh\n' "$PWD/.venv" >&2
    exit 1
fi

exec "$VENV_PY" src/server.py
