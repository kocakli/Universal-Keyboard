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

# App icon: the Icon Composer document compiles to Assets.car (Liquid Glass, macOS 26+)
# and AppIcon.icns (earlier macOS). The transparent glyph is used inside the app.
xcrun actool --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 15.0 \
    --app-icon AppIcon --output-partial-info-plist build/icon-partial.plist Resources/AppIcon.icon > /dev/null
cp Resources/Glyph.png "$APP/Contents/Resources/Glyph.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>KeyMapper</string>
    <key>CFBundleDisplayName</key><string>KeyMapper</string>
    <key>CFBundleIdentifier</key><string>dev.keymapper.KeyMapper</string>
    <key>CFBundleExecutable</key><string>KeyMapper</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>CFBundleLocalizations</key>
    <array><string>tr</string><string>en</string><string>es</string><string>ja</string><string>zh-Hans</string></array>
    <key>CFBundleAllowMixedLocalizations</key><true/>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Oğuzhan Koçaklı</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key><string>KeyMapper, Bluetooth klavyelerinizin pil seviyesini göstermek için Bluetooth kullanır.</string>
</dict>
</plist>
PLIST

# Localized text for the Bluetooth permission prompt.
write_infoplist_strings() {
    mkdir -p "$APP/Contents/Resources/$1.lproj"
    printf '"NSBluetoothAlwaysUsageDescription" = "%s";\n' "$2" > "$APP/Contents/Resources/$1.lproj/InfoPlist.strings"
}
write_infoplist_strings tr "KeyMapper, Bluetooth klavyelerinizin pil seviyesini göstermek için Bluetooth kullanır."
write_infoplist_strings en "KeyMapper uses Bluetooth to show the battery level of your Bluetooth keyboards."
write_infoplist_strings es "KeyMapper usa Bluetooth para mostrar el nivel de batería de tus teclados Bluetooth."
write_infoplist_strings ja "KeyMapper は Bluetooth キーボードのバッテリー残量を表示するために Bluetooth を使用します。"
write_infoplist_strings zh-Hans "KeyMapper 使用蓝牙来显示蓝牙键盘的电池电量。"

codesign --force --deep --sign - "$APP"
# Let Finder and the Dock pick up a changed icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "Hazır: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/KeyMapper.app"
    cp -R "$APP" /Applications/
    echo "Kuruldu: /Applications/KeyMapper.app"
fi
