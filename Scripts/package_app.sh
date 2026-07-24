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
# Version comes from the environment (the release workflow passes it from the git
# tag, e.g. v0.2.0 → 0.2.0). The fallback is only for local packaging.
VERSION="${VERSION:-0.1.0}"

# Ship a universal binary so a single .app runs natively on both Apple Silicon
# and Intel Macs. We build each slice with a single `--arch` (SwiftPM's native
# build system, works with just Command Line Tools) and `lipo` them together —
# passing multiple `--arch` at once would switch SwiftPM to xcbuild, which needs
# a full Xcode install. Override with ARCHS="arm64" for a faster local build.
ARCHS="${ARCHS:-arm64 x86_64}"

SLICES=()
for ARCH in $ARCHS; do
    echo "▸ Building ($CONFIG, $ARCH)…"
    swift build -c "$CONFIG" --product "$APP_NAME" --arch "$ARCH"
    SLICE="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)/$APP_NAME"
    [ -x "$SLICE" ] || { echo "✗ executable not found at $SLICE" >&2; exit 1; }
    SLICES+=("$SLICE")
done

APP="dist/$APP_NAME.app"
echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "▸ Combining ${#SLICES[@]} arch slice(s) into a universal binary…"
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"

ICNS="Assets/icon/AppIcon.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "⚠ $ICNS missing — run ./Scripts/make_icons.sh first (bundling without an icon)" >&2
fi

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing…"
codesign --force --sign - "$APP"

echo "✓ Built $APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null | sed 's/^/    archs: /' || true
codesign -dv "$APP" 2>&1 | sed 's/^/    /' || true

# Zip for Homebrew Cask distribution (ditto keeps the .app bundle intact).
ZIP="dist/$APP_NAME-$VERSION.zip"
echo "▸ Zipping ${ZIP}…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "✓ Built $ZIP"
echo "    version: $VERSION"
echo "    sha256:  $SHA"

echo
echo "Install (local): cp -R \"$APP\" /Applications/    then right-click → Open (first launch)"
echo "Run once:        open \"$APP\""
echo "Release (cask):  gh release create v$VERSION \"$ZIP\" --repo lig-sei-akihiro/claude-usage-bar"
echo "                 then bump version=$VERSION / sha256=$SHA in the TAP repo (lig-sei-akihiro/homebrew-tap) Casks/claude-usage-bar.rb — static public URL, no auth machinery"
