#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
INSTALL_DIR="$DATA_HOME/lyrics-on-panel"
BACKEND_DIR="$INSTALL_DIR/backend"
SERVICE_NAME="Universal-Mpris-LyricServer.service"
SERVICE_DIR="$CONFIG_HOME/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME"
WIDGET_ID="lyrics-on-panel-plasma6-v3"
PLASMOID_DIR="$DATA_HOME/plasma/plasmoids/$WIDGET_ID"
VENV_DIR="$BACKEND_DIR/.venv"
VENV_PY="$VENV_DIR/bin/python"
PYTHON_PACKAGES=("dbus:dbus-python" "websockets:websockets")
ASSUME_YES=false

usage() {
    cat <<EOF
Usage: $0 [--yes] [--help]

Installs the Plasma widget, backend, and systemd user service.
Python dependencies are always installed into a local virtual environment
at $VENV_DIR.

Options:
  -y, --yes  Install missing Python packages without asking for confirmation
  -h, --help Show this help

Environment variables:
  XDG_DATA_HOME   defaults to \$HOME/.local/share
  XDG_CONFIG_HOME defaults to \$HOME/.config
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -y|--yes)
            ASSUME_YES=true
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$(id -u)" -eq 0 ]; then
    printf '[install] error: run this script as your desktop user, not root\n' >&2
    exit 1
fi

log() { printf '[install] %s\n' "$*"; }
warn() { printf '[install] warning: %s\n' "$*" >&2; }
fail() { printf '[install] error: %s\n' "$*" >&2; exit 1; }

ask_yes_no() {
    local prompt="$1"
    if [ "$ASSUME_YES" = true ]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        warn "Cannot prompt because stdin is not a terminal; rerun with --yes to install automatically"
        return 1
    fi
    local reply
    read -r -p "[install] $prompt [Y/n] " reply || return 1
    case "$reply" in
        ""|y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

collect_missing_python_packages() {
    missing_python_packages=()
    local entry module package
    for entry in "${PYTHON_PACKAGES[@]}"; do
        module="${entry%%:*}"
        package="${entry##*:}"
        if ! "$VENV_PY" -c "import $module" >/dev/null 2>&1; then
            missing_python_packages+=("$package")
        fi
    done
}

find_qml_import_bases() {
    local candidate
    if command -v qmake6 >/dev/null 2>&1; then
        candidate="$(qmake6 -query QT_INSTALL_QML 2>/dev/null || true)"
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
        fi
    fi
    for candidate in /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml /usr/lib64/qt6/qml; do
        if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
        fi
    done
}

check_frontend_dependencies() {
    local -a missing=()
    local -a qml_bases=()
    local base module found
    local -a modules=(
        "QtQuick"
        "QtQuick/Controls"
        "QtQuick/Layouts"
        "QtWebSockets"
        "org/kde/kirigami"
        "org/kde/kquickcontrols"
        "org/kde/plasma/core"
        "org/kde/plasma/components"
        "org/kde/plasma/plasmoid"
        "org/kde/plasma/configuration"
    )

    if ! command -v plasmashell >/dev/null 2>&1; then
        missing+=("plasmashell (Plasma 6)")
    fi

    while IFS= read -r base; do
        qml_bases+=("$base")
    done < <(find_qml_import_bases)

    if [ ${#qml_bases[@]} -eq 0 ]; then
        warn "Could not locate the Qt QML import directory; skipping QML module check"
    else
        for module in "${modules[@]}"; do
            found=false
            for base in "${qml_bases[@]}"; do
                if [ -f "$base/$module/qmldir" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                missing+=("$module")
            fi
        done
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        fail "Missing frontend dependencies: ${missing[*]}. Install the Plasma 6 / KDE Frameworks 6 components provided by your distribution, then rerun."
    fi
    log "Frontend dependencies OK"
}

[ -f "$SCRIPT_DIR/kde/v3/metadata.json" ] || fail "Missing kde/v3 package"
[ -f "$SCRIPT_DIR/backend/src/server.py" ] || fail "Missing backend source"
[ -f "$SCRIPT_DIR/requirements.txt" ] || fail "Missing requirements.txt"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

check_frontend_dependencies

log "Installing backend to $BACKEND_DIR"
mkdir -p "$BACKEND_DIR"
rm -rf "$BACKEND_DIR/src"
cp -a "$SCRIPT_DIR/backend/src" "$BACKEND_DIR/src"
install -m 0755 "$SCRIPT_DIR/backend/run.sh" "$BACKEND_DIR/run.sh"
install -m 0644 "$SCRIPT_DIR/requirements.txt" "$BACKEND_DIR/requirements.txt"

if [ -d "$VENV_DIR" ] && [ ! -x "$VENV_PY" ]; then
    warn "Existing virtual environment is incomplete; recreating $VENV_DIR"
    rm -rf "$VENV_DIR"
fi

if [ ! -x "$VENV_PY" ]; then
    log "Creating Python virtual environment at $VENV_DIR"
    if ! python3 -m venv "$VENV_DIR"; then
        fail "Could not create a Python virtual environment. Install the venv module for python3 from your distribution and rerun."
    fi
else
    log "Using existing Python virtual environment at $VENV_DIR"
fi

if ! "$VENV_PY" -m pip --version >/dev/null 2>&1; then
    log "Bootstrapping pip in the virtual environment"
    if ! "$VENV_PY" -m ensurepip --upgrade >/dev/null 2>&1; then
        fail "pip is missing in $VENV_DIR and ensurepip failed. Recreate the virtual environment after installing python3 venv support."
    fi
fi

collect_missing_python_packages
if [ ${#missing_python_packages[@]} -gt 0 ]; then
    warn "Missing Python packages in $VENV_DIR: ${missing_python_packages[*]}"
    if ask_yes_no "Install these Python packages into the virtual environment now?"; then
        log "Installing Python packages into $VENV_DIR"
        "$VENV_PY" -m pip install --disable-pip-version-check --upgrade pip \
            || warn "Could not upgrade pip; continuing with the existing pip"
        if ! "$VENV_PY" -m pip install --disable-pip-version-check -r "$BACKEND_DIR/requirements.txt"; then
            fail "Python package installation failed. Review the error above and rerun."
        fi
    else
        fail "Python packages are required. Install them with: $VENV_PY -m pip install -r $BACKEND_DIR/requirements.txt"
    fi
fi

collect_missing_python_packages
if [ ${#missing_python_packages[@]} -gt 0 ]; then
    fail "Python packages are still missing: ${missing_python_packages[*]}. Run: $VENV_PY -m pip install -r $BACKEND_DIR/requirements.txt"
fi
log "Python virtual environment ready: $VENV_DIR"

if command -v ldconfig >/dev/null 2>&1; then
    if ! ldconfig -p 2>/dev/null | grep 'libopencc' >/dev/null; then
        warn "libopencc not found; traditional-to-simplified conversion will be disabled"
    fi
else
    warn "ldconfig not found; cannot check whether libopencc is installed"
fi

log "Installing Plasma widget $WIDGET_ID"
if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -x "$WIDGET_ID" >/dev/null; then
        if ! kpackagetool6 --type Plasma/Applet --upgrade "$SCRIPT_DIR/kde/v3"; then
            warn "Upgrade failed; trying fresh install"
            kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR/kde/v3"
        fi
    else
        kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR/kde/v3"
    fi
else
    warn "kpackagetool6 not found; copying widget files directly"
    rm -rf "$PLASMOID_DIR"
    mkdir -p "$PLASMOID_DIR"
    cp -a "$SCRIPT_DIR/kde/v3/." "$PLASMOID_DIR/"
fi

log "Installing systemd user service"
mkdir -p "$SERVICE_DIR"
"$VENV_PY" - "$SCRIPT_DIR/packaging/Universal-Mpris-LyricServer.service" "$SERVICE_FILE" "$BACKEND_DIR" <<'PY'
import sys

template, target, backend = sys.argv[1], sys.argv[2], sys.argv[3]
with open(template, encoding="utf-8") as handle:
    text = handle.read()
with open(target, "w", encoding="utf-8") as handle:
    handle.write(text.replace("@BACKEND_DIR@", backend))
PY
chmod 0644 "$SERVICE_FILE"

have_user_systemd=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    have_user_systemd=true
fi

if [ "$have_user_systemd" = true ]; then
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1 \
        || warn "Could not enable $SERVICE_NAME"
    if systemctl --user restart "$SERVICE_NAME"; then
        log "Backend service started"
    else
        warn "Could not start $SERVICE_NAME; check: systemctl --user status $SERVICE_NAME"
    fi

    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service \
            || warn "Could not restart plasmashell"
    fi
else
    warn "systemctl --user is unavailable; start the backend manually: $BACKEND_DIR/run.sh"
fi

log "Installation complete"
log "Widget:  $WIDGET_ID"
log "Backend: $BACKEND_DIR"
log "Service: $SERVICE_NAME"
