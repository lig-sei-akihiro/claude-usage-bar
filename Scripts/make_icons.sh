#!/usr/bin/env bash
# Generate every icon size from the master SVGs.
#
#   ./Scripts/make_icons.sh
#
# Inputs (vector, edited by hand):
#   Assets/icon/AppIcon.svg   full-bleed colour icon (rounded-rect app icon look)
#   Assets/icon/MenuBar.svg   monochrome glyph for the menu-bar template image
#
# Outputs:
#   Assets/icon/AppIcon.iconset/*.png   the 10 macOS-named sizes
#   Assets/icon/AppIcon.icns            packed icns (bundled by package_app.sh)
#   Assets/icon/png/icon_<n>.png        colour PNGs 16..1024 (popover / settings / README)
#   Assets/icon/menubar/MenuBarTemplate.png (+@2x)   status-item template image
#
# Needs: rsvg-convert (brew install librsvg), iconutil, sips (system).
set -euo pipefail
cd "$(dirname "$0")/.."

ICON_DIR="Assets/icon"
APP_SVG="$ICON_DIR/AppIcon.svg"
BAR_SVG="$ICON_DIR/MenuBar.svg"

command -v rsvg-convert >/dev/null || { echo "✗ rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
[ -f "$APP_SVG" ] || { echo "✗ missing $APP_SVG" >&2; exit 1; }

render() { # svg w h out
  rsvg-convert -w "$2" -h "$3" -a "$1" -o "$4"
}

echo "▸ AppIcon.iconset…"
ISET="$ICON_DIR/AppIcon.iconset"
rm -rf "$ISET"; mkdir -p "$ISET"
# name:size pairs required by iconutil
for pair in \
  "icon_16x16:16"      "icon_16x16@2x:32" \
  "icon_32x32:32"      "icon_32x32@2x:64" \
  "icon_128x128:128"   "icon_128x128@2x:256" \
  "icon_256x256:256"   "icon_256x256@2x:512" \
  "icon_512x512:512"   "icon_512x512@2x:1024"; do
  name="${pair%%:*}"; size="${pair##*:}"
  render "$APP_SVG" "$size" "$size" "$ISET/$name.png"
done

echo "▸ AppIcon.icns…"
iconutil -c icns "$ISET" -o "$ICON_DIR/AppIcon.icns"

echo "▸ colour PNGs…"
PNG_DIR="$ICON_DIR/png"
rm -rf "$PNG_DIR"; mkdir -p "$PNG_DIR"
for n in 16 32 64 128 256 512 1024; do
  render "$APP_SVG" "$n" "$n" "$PNG_DIR/icon_$n.png"
done

if [ -f "$BAR_SVG" ]; then
  echo "▸ menu-bar template…"
  BAR_DIR="$ICON_DIR/menubar"
  rm -rf "$BAR_DIR"; mkdir -p "$BAR_DIR"
  render "$BAR_SVG" 18 18 "$BAR_DIR/MenuBarTemplate.png"
  render "$BAR_SVG" 36 36 "$BAR_DIR/MenuBarTemplate@2x.png"
else
  echo "▸ (skip menu-bar template — no $BAR_SVG)"
fi

echo "✓ done → $ICON_DIR"
ls -1 "$ICON_DIR"/AppIcon.icns "$PNG_DIR"/*.png 2>/dev/null | sed 's/^/    /'
