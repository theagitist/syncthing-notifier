#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$PROJECT_DIR/config.env"

if [ ! -f "$CONFIG" ]; then
    echo "error: $CONFIG not found; can't determine bundle id to uninstall." >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$CONFIG"
: "${BUNDLE_ID:?BUNDLE_ID not set in $CONFIG}"

APP="$HOME/Applications/Syncthing Notifier.app"
RUNTIME_DIR="$HOME/Library/Application Support/syncthing-notifier"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

echo "Stopping and removing launchd agent ($BUNDLE_ID)"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
rm -f "$LAUNCH_AGENT"

echo "Removing notifier.py"
rm -rf "$RUNTIME_DIR"

echo "Removing app bundle"
rm -rf "$APP"

echo
echo "Uninstalled. To also clear notification permission:"
echo "  tccutil reset All $BUNDLE_ID"
