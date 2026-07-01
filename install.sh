#!/usr/bin/env bash
# Build Qurani and install it to /Applications so the Raycast / Launchpad launcher
# runs the fresh binary. Without this step, edits land in Xcode's DerivedData while
# /Applications keeps the stale copy — the app "doesn't change" until you reinstall.
#
# Usage:
#   ./install.sh            # Release build (default)
#   ./install.sh Debug      # Debug build (includes the --snapshot render path)
set -euo pipefail

CONFIG="${1:-Release}"
PROJECT="Qurani.xcodeproj"
SCHEME="Qurani"
APP="Qurani.app"
DERIVED=".build-app"
DEST="/Applications/$APP"
LOG="$DERIVED/last-install-build.log"

cd "$(dirname "$0")"
mkdir -p "$DERIVED"

# Regenerate the project from project.yml when xcodegen is present, so any newly
# added source files are compiled in. No-op if xcodegen isn't installed.
if command -v xcodegen >/dev/null 2>&1; then
  echo "▸ xcodegen generate"
  xcodegen generate --use-cache >/dev/null
fi

echo "▸ building $SCHEME ($CONFIG) — full log: $LOG"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
      -derivedDataPath "$DERIVED" -destination 'platform=macOS' build >"$LOG" 2>&1; then
  echo "✗ build failed:" >&2
  tail -25 "$LOG" >&2
  exit 1
fi

SRC="$DERIVED/Build/Products/$CONFIG/$APP"
[ -d "$SRC" ] || { echo "✗ build product missing: $SRC" >&2; exit 1; }

echo "▸ installing → $DEST"
killall Qurani 2>/dev/null || true   # quit the running copy so the swap takes hold
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "▸ relaunching"
open "$DEST"
echo "✓ $CONFIG build installed → $DEST"
