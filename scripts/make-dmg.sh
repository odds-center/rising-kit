#!/bin/bash
# 배포용 디스크 이미지를 만든다: 열면 Rising Kit 을 Applications 폴더로 끌어다 놓는 창이 나온다.
#   사용: scripts/make-dmg.sh        → build/Rising-Kit-<버전>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=1 scripts/build-app.sh

APP="build/Rising Kit.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Rising-Kit-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Rising Kit" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

# 이미지 자체에도 서명해 둔다 (인증서가 있을 때)
IDENTITY="Rising Kit Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$DMG"
fi

echo "만들어짐: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
