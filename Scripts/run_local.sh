#!/usr/bin/env bash
# Build, package, and (re)launch the local ClaudeUsageBar.app in the menu bar.
#
#   ./Scripts/run_local.sh [debug|release]      # default: debug
#   VERSION=0.2.1 ./Scripts/run_local.sh        # set the bundle version
#
# Wraps package_app.sh, then swaps the running menu-bar instance for the freshly
# built one: any running ClaudeUsageBar — the installed /Applications copy *or* a
# previous dist/ build — is quit first. Otherwise you end up with two status items,
# or LaunchServices re-focuses the old copy because both bundles share the same
# bundle id. Debug is the default (fast iteration; colours/layout are identical to
# release). VERSION is passed straight through to package_app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
case "$CONFIG" in debug|release) ;; *) echo "✗ config must be debug or release (got '$CONFIG')" >&2; exit 2 ;; esac

APP_NAME="ClaudeUsageBar"
APP="dist/$APP_NAME.app"
BIN_REL="$APP/Contents/MacOS/$APP_NAME"

# 1) Build + package (package_app.sh honours $VERSION, keeping its default if unset).
#    Local runs only need the host arch — skip the cross-arch slice package_app.sh
#    would otherwise build for its universal (Apple Silicon + Intel) release binary.
ARCHS="${ARCHS:-$(uname -m)}" ./Scripts/package_app.sh "$CONFIG"

# 2) Quit any running instance so only the new build owns a status item. The pattern
#    matches both the /Applications and dist/ copies (same executable path suffix).
if pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null; then
  echo "▸ Quit the running $APP_NAME instance"
  sleep 1   # let the old status item clear before relaunching
fi

# 3) Launch the freshly built bundle.
echo "▸ Launching ${APP}…"
open "$APP"
sleep 2

# 4) Confirm exactly the dist/ build is up.
if PID="$(pgrep -f "$PWD/$BIN_REL")"; then
  VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
  echo "✓ $APP_NAME v$VER running (pid $PID) from $APP"
else
  echo "✗ $APP_NAME did not come up — check Console.app for crash logs" >&2
  exit 1
fi
