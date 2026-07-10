#!/usr/bin/env bash
# Tag a release and push it, driving the tag-driven Release workflow that builds
# ClaudeUsageBar-<version>.zip and publishes a GitHub Release.
#
#   ./Scripts/release.sh <version> [--dry-run]
#     version     e.g. 0.2.1 or v0.2.1
#     --dry-run    print the target commit + tag, but don't tag or push
#
# The tag is what sets the app version — CI passes v<X.Y.Z> to package_app.sh as
# $VERSION → the bundle's CFBundleShortVersionString — so nothing in the tree needs
# bumping. The tag is always placed on the tip of origin/main (releases ship from
# main) after a fetch, and the script aborts if the tag already exists locally or
# on the remote (which is what made an earlier release run fail). With gh present it
# then follows the Release run to completion and prints the published assets.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -ge 1 ] || { echo "usage: ./Scripts/release.sh <version> [--dry-run]" >&2; exit 2; }

RAW="$1"; shift
DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    *) echo "✗ unknown option: $a" >&2; exit 2 ;;
  esac
done

# Normalise to a v-prefixed tag and validate X.Y.Z.
VER="${RAW#v}"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ version must be X.Y.Z (got '$RAW')" >&2; exit 2; }
TAG="v$VER"

echo "▸ Fetching origin/main + tags…"
git fetch --quiet origin main --tags

# Refuse to reuse an existing tag (local or remote).
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "✗ tag $TAG already exists locally" >&2; exit 1; }
git ls-remote --tags origin "$TAG" | grep -q . && { echo "✗ tag $TAG already exists on origin" >&2; exit 1; }

TARGET="$(git rev-parse origin/main)"
echo "▸ Target: $(git rev-parse --short origin/main) — $(git log -1 --format=%s origin/main)"
echo "▸ Tag:    $TAG"

if [ "$DRY" -eq 1 ]; then
  echo "✓ dry run — nothing tagged or pushed"
  exit 0
fi

git tag -a "$TAG" "$TARGET" -m "$TAG"
git push origin "$TAG"
echo "✓ pushed $TAG → $(git rev-parse --short "$TARGET") (Release workflow triggered)"

# Best-effort: follow the Release run and report the published release.
if command -v gh >/dev/null; then
  echo "▸ Waiting for the Release workflow…"
  sleep 5
  RUN_ID="$(gh run list --workflow=Release --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  if [ -n "${RUN_ID:-}" ]; then
    gh run watch "$RUN_ID" --exit-status --interval 10 \
      || { echo "✗ Release workflow failed — gh run view $RUN_ID --log-failed" >&2; exit 1; }
    gh release view "$TAG" --json url,assets \
      --jq '"✓ Release " + .url + "\n    assets: " + ([.assets[].name] | join(", "))' 2>/dev/null || true
  fi
else
  echo "⚠ gh not found — skipped watching the Release workflow"
fi
