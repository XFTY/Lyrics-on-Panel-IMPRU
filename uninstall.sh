#!/usr/bin/env bash
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
INSTALL_DIR="$DATA_HOME/lyrics-on-panel"
BACKEND_DIR="$INSTALL_DIR/backend"
SERVICE_NAME="Universal-Mpris-LyricServer.service"
SERVICE_DIR="$CONFIG_HOME/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME"
WIDGET_ID="lyrics-on-panel-plasma6-v3"
PLASMOID_DIR="$DATA_HOME/plasma/plasmoids/$WIDGET_ID"

PURGE=false
case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: $0 [--purge]

Removes the Plasma widget, backend, and systemd user service.
  --purge  Also removes Spotify authentication and lyric cache data.
EOF
        exit 0
        ;;
    --purge)
        PURGE=true
        ;;
    "")
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 2
        ;;
esac

if [ "$(id -u)" -eq 0 ]; then
    printf '[uninstall] error: run this script as your desktop user, not root\n' >&2
    exit 1
fi

log() { printf '[uninstall] %s\n' "$*"; }
warn() { printf '[uninstall] warning: %s\n' "$*" >&2; }

have_user_systemd=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    have_user_systemd=true
fi

if [ "$have_user_systemd" = true ]; then
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
fi
rm -f "$SERVICE_FILE"
if [ "$have_user_systemd" = true ]; then
    systemctl --user daemon-reload || true
fi

log "Removing Plasma widget $WIDGET_ID"
if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -x "$WIDGET_ID" >/dev/null; then
        kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID" \
            || warn "Could not remove $WIDGET_ID with kpackagetool6"
    fi
fi
rm -rf "$PLASMOID_DIR"

log "Removing backend"
rm -rf "$BACKEND_DIR"
rmdir "$INSTALL_DIR" 2>/dev/null || true

rm -rf /tmp/lyrics-on-panel-cache

if "$PURGE"; then
    log "Removing user configuration and cached Spotify authentication"
    rm -rf "$HOME/.config/lyrics-on-panel"
    if [ "$CONFIG_HOME" != "$HOME/.config" ]; then
        rm -rf "$CONFIG_HOME/lyrics-on-panel"
    fi
    rm -rf "$HOME/.cache/lyrics-on-panel"
else
    log "User configuration preserved; use --purge to remove it"
fi

if "$have_user_systemd" && systemctl --user is-active --quiet plasma-plasmashell.service; then
    systemctl --user restart plasma-plasmashell.service \
        || warn "Could not restart plasmashell"
fi

log "Uninstall complete"
