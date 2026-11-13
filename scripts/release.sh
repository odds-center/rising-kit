#!/bin/bash
# 디스크 이미지를 만들어 GitHub 릴리스로 올린다.   사용: scripts/release.sh
# 버전은 Resources/Info.plist 의 CFBundleShortVersionString 을 쓴다.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
  echo "커밋하지 않은 변경이 있습니다. 먼저 커밋하세요." >&2
  exit 1
fi

scripts/make-dmg.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Rising-Kit-$VERSION.dmg"

git push -q origin HEAD
gh release create "v$VERSION" "$DMG" --title "Rising Kit $VERSION" --generate-notes
