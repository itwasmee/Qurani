#!/bin/bash
# Qurani installer — downloads the latest release, installs it to /Applications,
# clears the download quarantine (so macOS doesn't block it), and launches.
#
#   curl -fsSL https://itwasmee.github.io/Qurani/get.sh | bash
#
set -euo pipefail

URL="https://github.com/itwasmee/Qurani/releases/latest/download/Qurani.zip"
DEST="/Applications/Qurani.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Downloading Qurani…"
curl -fL --progress-bar "$URL" -o "$TMP/Qurani.zip"

echo "▸ Installing to /Applications…"
mkdir -p "$TMP/unpack"
ditto -x -k "$TMP/Qurani.zip" "$TMP/unpack"
APP="$(/usr/bin/find "$TMP/unpack" -maxdepth 2 -name 'Qurani.app' -print -quit)"
[ -n "$APP" ] || { echo "✗ Qurani.app not found in the download." >&2; exit 1; }

osascript -e 'quit app "Qurani"' 2>/dev/null || true   # close a running copy
if ! rm -rf "$DEST" 2>/dev/null || ! mv "$APP" "$DEST" 2>/dev/null; then
  echo "  (need admin rights to write to /Applications)"
  sudo rm -rf "$DEST"
  sudo mv "$APP" "$DEST"
fi

echo "▸ Clearing the download quarantine…"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "✓ Installed. Launching Qurani…"
open "$DEST"
echo "  Look for the equalizer icon in your menubar."
