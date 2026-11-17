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

# 릴리스는 늘 같은 인증서로 서명해야 한다. macOS 는 손쉬운 사용 권한을 서명 인증서에 묶어 기억하므로,
# 이름만 같은 다른 맥의 인증서로 서명해 올리면 자동 업데이트를 받은 모든 사용자가 권한을 다시 허용해야 한다
# (설정에는 켜진 것으로 보이는데 앱은 계속 물어본다). 다른 맥에서 올리려면 README 의 "릴리스 인증서" 참고.
RELEASE_CERT="bc9570ec7e7727f25191be6279fbcf6ebaca531e"
LEAF="$(codesign -d -r- "build/Rising Kit.app" 2>&1 | sed -n 's/.*certificate leaf = H"\([0-9a-f]*\)".*/\1/p')"
if [ "$LEAF" != "$RELEASE_CERT" ]; then
  echo "릴리스 인증서로 서명되지 않았습니다 (서명: ${LEAF:-임시 서명}, 필요: $RELEASE_CERT)." >&2
  echo "이대로 올리면 사용자들의 손쉬운 사용 권한이 풀립니다. README 의 \"릴리스 인증서\"를 보세요." >&2
  exit 1
fi

git push -q origin HEAD
gh release create "v$VERSION" "$DMG" --title "Rising Kit $VERSION" --generate-notes

# 릴리스는 최신 $KEEP 개만 남긴다 (태그는 그대로 둔다).
KEEP=3
gh release list --limit 100 --json tagName,createdAt \
  --jq "sort_by(.createdAt) | reverse | .[$KEEP:][].tagName" |
while read -r OLD; do
  echo "오래된 릴리스 삭제: $OLD"
  gh release delete "$OLD" --yes
done
