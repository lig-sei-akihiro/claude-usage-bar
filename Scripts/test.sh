#!/usr/bin/env bash
# Run the Core unit tests (Swift Testing).
#
# With full Xcode installed, `swift test` works as-is. On a Command Line Tools-only
# setup, SwiftPM can't locate the bundled swift-testing runtime on its own, so we
# point it at the CLT Testing framework and its interop dylib explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV" == *CommandLineTools* ]]; then
  FWK="$DEV/Library/Developer/Frameworks"
  LIB="$DEV/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F -Xswiftc "$FWK" \
    -Xlinker -F -Xlinker "$FWK" \
    -Xlinker -rpath -Xlinker "$FWK" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test "$@"
fi
