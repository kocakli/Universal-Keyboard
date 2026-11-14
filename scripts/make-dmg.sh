#!/usr/bin/env bash
# Builds KeyMapper.app and packages it as build/KeyMapper-<version>.dmg: open it and drag
# KeyMapper onto the Applications shortcut. Usage: scripts/make-dmg.sh [--install]
# (--install also copies the app from the finished disk image into /Applications.)
set -euo pipefail

cd "$(dirname "$0")/.."
scripts/build-app.sh

APP="build/KeyMapper.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/KeyMapper-$VERSION.dmg"

STAGE="$(mktemp -d)"
MOUNT=""
cleanup() {
    if [[ -n "$MOUNT" ]]; then
        hdiutil detach "$MOUNT" -quiet || true
        rmdir "$MOUNT" 2>/dev/null || true
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT

ditto "$APP" "$STAGE/KeyMapper.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "KeyMapper $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet
echo "Paket: $DMG"

if [[ "${1:-}" == "--install" ]]; then
    # Install what the disk image contains, so the package itself is what gets tested.
    MOUNT="$(mktemp -d)"
    hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
    # Quit a running copy first (asking politely; telling a closed app to quit would launch it).
    if pgrep -xq KeyMapper; then
        osascript -e 'quit app id "dev.keymapper.KeyMapper"' 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq KeyMapper || break; sleep 0.5; done
    fi
    rm -rf "/Applications/KeyMapper.app"
    ditto "$MOUNT/KeyMapper.app" "/Applications/KeyMapper.app"
    codesign --verify --deep --strict "/Applications/KeyMapper.app"
    echo "Kuruldu: /Applications/KeyMapper.app"
fi
