#!/bin/zsh
# Builds build/Strong Brew.dmg for distribution.
#
# Optional, for a DMG that opens without Gatekeeper warnings on other Macs:
#   SIGN_ID="Developer ID Application: Name (TEAMID)"  signing identity
#   NOTARY_PROFILE=strongbrew                          from `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP="build/Strong Brew.app"
DMG="build/Strong Brew.dmg"
STAGE=build/dmg

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Strong Brew" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
