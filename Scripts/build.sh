#!/bin/zsh
set -euo pipefail
TASK_ROOT=${0:A:h:h}
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
APP="$TASK_ROOT/build/灵提醒.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" /private/tmp/lingminder-swift-cache
if [[ ! -f "$TASK_ROOT/Resources/Audio/ticking.m4a" ]]; then
  xcrun swift -sdk "$SDK" -module-cache-path /private/tmp/lingminder-swift-cache "$TASK_ROOT/Scripts/extract-audio.swift" "$TASK_ROOT/Resources/Audio"
fi
if [[ ! -f "$TASK_ROOT/Resources/StatusIcon.png" || "$TASK_ROOT/Resources/IconArtwork.png" -nt "$TASK_ROOT/Resources/LingMinder.icns" || "$TASK_ROOT/Resources/StatusArtwork.png" -nt "$TASK_ROOT/Resources/StatusIcon.png" || "$TASK_ROOT/Scripts/icon.swift" -nt "$TASK_ROOT/Resources/LingMinder.icns" ]]; then
  TASK_ICON_ROOT=$(mktemp -d /private/tmp/LingMinder-icon.XXXXXX)
  trap 'rm -rf "$TASK_ICON_ROOT"' EXIT
  xcrun swift -sdk "$SDK" -module-cache-path /private/tmp/lingminder-swift-cache "$TASK_ROOT/Scripts/icon.swift" "$TASK_ICON_ROOT/LingMinder.iconset" "$TASK_ROOT/Resources/IconArtwork.png" "$TASK_ROOT/Resources/StatusIcon.png" "$TASK_ROOT/Resources/StatusArtwork.png"
  iconutil -c icns "$TASK_ICON_ROOT/LingMinder.iconset" -o "$TASK_ROOT/Resources/LingMinder.icns"
fi
xcrun swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 -module-cache-path /private/tmp/lingminder-swift-cache -O "$TASK_ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/LingMinder" -lsqlite3
cp -R "$TASK_ROOT/Resources/" "$APP/Contents/Resources/"
if [[ ! -f "$TASK_ROOT/Resources/notification.caf" ]]; then
  /usr/bin/afconvert -f caff -d LEI16 "$TASK_ROOT/Resources/Audio/notification.mp3" "$TASK_ROOT/Resources/notification.caf"
fi
cp "$TASK_ROOT/Resources/notification.caf" "$APP/Contents/Resources/notification.caf"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.ling99.LingMinder</string>
<key>CFBundleName</key><string>灵提醒</string>
<key>CFBundleDisplayName</key><string>灵提醒</string>
<key>CFBundleExecutable</key><string>LingMinder</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>LingMinder</string>
<key>NSRemindersUsageDescription</key><string>仅同步你在灵提醒中创建的提醒与任务。</string>
<key>NSRemindersFullAccessUsageDescription</key><string>创建、更新并完成灵提醒绑定的 Apple 提醒事项，不导入其他项目。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
