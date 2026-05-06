#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$PROJECT_DIR/config.env"
FOLDERS="$PROJECT_DIR/folders.json"

if [ ! -f "$CONFIG" ]; then
    echo "error: $CONFIG not found." >&2
    echo "       cp config.env.example config.env  # then edit if you want" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$CONFIG"
: "${BUNDLE_ID:?BUNDLE_ID not set in $CONFIG}"

if [ ! -f "$FOLDERS" ]; then
    echo "error: $FOLDERS not found." >&2
    echo "       cp folders.json.example folders.json  # then edit with real folder IDs" >&2
    exit 1
fi
if grep -q 'REPLACE_FOLDER_ID' "$FOLDERS"; then
    echo "warning: $FOLDERS still contains REPLACE_FOLDER_ID placeholders." >&2
    echo "         the daemon will install but won't notify on anything until you edit it." >&2
fi

APP="$HOME/Applications/Syncthing Notifier.app"
RUNTIME_DIR="$HOME/Library/Application Support/syncthing-notifier"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TMP"' EXIT

echo "[1/5] Building Syncthing Notifier.app (bundle id: $BUNDLE_ID)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/notifier" "$PROJECT_DIR/notifier_app.swift"
sed "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    "$PROJECT_DIR/Info.plist.template" \
    > "$APP/Contents/Info.plist"

echo "[2/5] Generating app icon"
swiftc -O -o "$BUILD_TMP/make_icon" "$PROJECT_DIR/make_icon.swift"
mkdir -p "$BUILD_TMP/AppIcon.iconset"
"$BUILD_TMP/make_icon" "$BUILD_TMP/AppIcon.iconset"
iconutil -c icns "$BUILD_TMP/AppIcon.iconset" \
    -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime "$APP"
"$LSREG" -f "$APP"

echo "[3/5] Installing notifier.py and folders.json"
mkdir -p "$RUNTIME_DIR"
cp "$PROJECT_DIR/notifier.py" "$RUNTIME_DIR/notifier.py"
cp "$FOLDERS" "$RUNTIME_DIR/folders.json"
chmod +x "$RUNTIME_DIR/notifier.py"

echo "[4/5] Installing launchd agent"
sed -e "s|__HOME__|$HOME|g" -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    "$PROJECT_DIR/launchd.plist.template" \
    > "$LAUNCH_AGENT"

echo "[5/5] Reloading launchd agent"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"

# Fire a test notification through the .app — triggers the macOS permission
# prompt on first install, and visually confirms the bundle is registered.
"$APP/Contents/MacOS/notifier" "Syncthing Notifier" "Installed and ready" || true

echo
echo "Done."
echo "  Logs:   ~/Library/Logs/syncthing-notifier.log"
echo "  Status: launchctl list | grep $BUNDLE_ID"
echo
echo "If macOS just asked about notifications, click Allow. Then add"
echo "Syncthing Notifier to your Focus filters in System Settings > Focus."
