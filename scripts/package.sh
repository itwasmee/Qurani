#!/usr/bin/env bash
# Build a Release Qurani.app and package it into dist/Qurani.zip and dist/Qurani.dmg.
# Used by the release GitHub Action and runnable locally. Does NOT install or upload.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
# Marketing version override — the release workflow passes the tag (v1.1 → VERSION=1.1) so the
# built CFBundleShortVersionString matches the release. The in-app update check compares this
# against the latest tag; a build that still said "1.0" would nag about its own release forever.
VERSION="${VERSION:-}"
APP=".build-app/Build/Products/$CONFIG/Qurani.app"

# The .xcodeproj is git-ignored (generated from project.yml), so regenerate it when possible.
if command -v xcodegen >/dev/null 2>&1; then
  echo "▸ xcodegen generate"
  xcodegen generate --use-cache >/dev/null
fi

echo "▸ building $CONFIG${VERSION:+ (version $VERSION)}"
xcodebuild -project Qurani.xcodeproj -scheme Qurani -configuration "$CONFIG" \
  -derivedDataPath .build-app -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  ${VERSION:+MARKETING_VERSION="$VERSION"} build

[ -d "$APP" ] || { echo "✗ build product missing: $APP" >&2; exit 1; }

echo "▸ packaging"
rm -rf dist && mkdir -p dist
ditto -c -k --keepParent "$APP" dist/Qurani.zip

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Qurani" -srcfolder "$STAGE" -ov -format UDZO dist/Qurani.dmg >/dev/null
rm -rf "$STAGE"

echo "✓ dist/Qurani.zip  ($(du -h dist/Qurani.zip | cut -f1))"
echo "✓ dist/Qurani.dmg  ($(du -h dist/Qurani.dmg | cut -f1))"
