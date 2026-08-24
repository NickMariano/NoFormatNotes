#!/bin/bash
#
# Builds the distributable disk image.
#
# A disk image rather than an installer package: NoFormatNotes writes nothing outside /Applications, so
# an installer would ask for an administrator password purely to copy an app, and would run its
# pre and post install scripts as root for an app that never needs root. Dragging asks for nothing.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/NoFormatNotes.app"
VERSION="$(defaults read "$PWD/Resources/App-Info.plist" CFBundleShortVersionString)"
DMG="build/NoFormatNotes-$VERSION.dmg"
STAGE="build/dmg-stage"

[ -d "$APP" ] || { echo "error: $APP not found. Run 'make app' first." >&2; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "NoFormatNotes" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# The image itself is signed too, so Gatekeeper can vouch for it before it is even mounted.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
if [ -n "$SIGN_ID" ]; then
    codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
    echo "signed disk image with: $SIGN_ID"
fi

echo "built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
