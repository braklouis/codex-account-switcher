#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --disable-sandbox
APP="$PWD/dist/Codex Accounts.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CodexAccounts "$APP/Contents/MacOS/CodexAccounts"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexaccounts.app</string>
<key>CFBundleExecutable</key><string>CodexAccounts</string>
<key>CFBundleName</key><string>Codex Accounts</string>
<key>CFBundleDisplayName</key><string>Codex Accounts</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
</dict></plist>
PLIST
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" Assets/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$(( SIZE * 2 ))
    sips -z "$DOUBLE" "$DOUBLE" Assets/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
print "Built: $APP"
