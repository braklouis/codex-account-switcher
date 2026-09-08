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
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
print "Built: $APP"
