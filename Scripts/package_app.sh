#!/usr/bin/env bash
# Package the executable into a double-clickable ClaudeUsageBar.app (menu-bar agent).
#
#   ./Scripts/package_app.sh [release|debug]   # default: release
#
# Produces dist/ClaudeUsageBar.app, ad-hoc signed. Not Developer-ID signed or
# notarized, so on first launch use right-click → Open to get past Gatekeeper.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageBar"
CONFIG="${1:-release}"
BUNDLE_ID="com.lig-sei-akihiro.claude-usage-bar"
VERSION="0.1.0"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -x "$BIN" ] || { echo "✗ executable not found at $BIN" >&2; exit 1; }

APP="dist/$APP_NAME.app"
echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Claude Usage Bar</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing…"
codesign --force --sign - "$APP"

echo "✓ Built $APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /' || true
echo
echo "Install:   cp -R \"$APP\" /Applications/    then right-click → Open (first launch)"
echo "Run once:  open \"$APP\""
