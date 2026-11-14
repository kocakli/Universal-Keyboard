#!/usr/bin/env bash
# Builds KeyMapper.app (menu bar app) into ./build. Usage: scripts/build-app.sh [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/KeyMapper.app"
VERSION="0.1.0"

swift build -c release --product KeyMapper
swift build -c release --product kmctl
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/KeyMapper" "$APP/Contents/MacOS/KeyMapper"
cp "$BIN/kmctl" "$APP/Contents/MacOS/kmctl"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>KeyMapper</string>
    <key>CFBundleDisplayName</key><string>KeyMapper</string>
    <key>CFBundleIdentifier</key><string>dev.keymapper.KeyMapper</string>
    <key>CFBundleExecutable</key><string>KeyMapper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Hazır: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/KeyMapper.app"
    cp -R "$APP" /Applications/
    echo "Kuruldu: /Applications/KeyMapper.app"
fi
