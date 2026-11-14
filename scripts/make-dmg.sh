#!/usr/bin/env bash
# Builds KeyMapper.app and packages it as build/KeyMapper-<version>.dmg: open it and drag
# KeyMapper onto the Applications shortcut. Usage: scripts/make-dmg.sh [--install]
# (--install also copies the app from the finished disk image into /Applications.)
#
# Distribution build (signed, notarized, stapled):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=KeyMapper-notary scripts/make-dmg.sh
# NOTARY_PROFILE is a notarytool keychain profile, created once with
#   xcrun notarytool store-credentials KeyMapper-notary --apple-id <Apple ID> --team-id <TEAMID>
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

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --strict "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY (Developer ID)." >&2; exit 1; }
    echo "Notarizing (usually a few minutes)…"
    RESULT="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
    if ! grep -Eq '"status" *: *"Accepted"' <<<"$RESULT"; then
        echo "$RESULT" >&2
        ID="$(sed -nE 's/.*"id" *: *"([^"]+)".*/\1/p' <<<"$RESULT" | head -1)"
        [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
    xcrun stapler staple -q "$DMG"
    xcrun stapler validate -q "$DMG"
    spctl --assess --type open --context context:primary-signature "$DMG"
    echo "Notarized and stapled."
fi
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
