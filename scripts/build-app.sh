#!/bin/bash
# Rising Kit.app 을 만든다.   사용: [UNIVERSAL=1] scripts/build-app.sh [--install]
#   --install  /Applications 에 복사하고 실행한다.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Rising Kit.app"

# UNIVERSAL=1 이면 Apple Silicon 과 Intel 맥 모두에서 도는 유니버설 바이너리로 만든다 (배포용).
ARCH_FLAGS=()
if [ "${UNIVERSAL:-}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

# (macOS 기본 bash 3.2 는 빈 배열을 그대로 펼치면 "unbound variable" 로 멈춘다)
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/RisingKit"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RisingKit"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make-icon.swift Resources
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 키체인에 "Rising Kit Local Signing" 인증서가 있으면 그것으로 서명한다. 서명이 빌드마다 같아서
# 손쉬운 사용 권한이 다시 빌드해도 유지된다. 없으면 임시(ad-hoc) 서명으로 대신하는데,
# 이 경우 빌드할 때마다 권한을 다시 허용해야 한다. (인증서는 scripts/make-signing-cert.sh 로 만든다)
IDENTITY="Rising Kit Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier com.oddscenter.risingkit "$APP"
else
  echo "경고: '$IDENTITY' 인증서가 없어 임시 서명합니다."
  codesign --force --sign - --identifier com.oddscenter.risingkit "$APP"
fi

echo "만들어짐: $APP"

if [ "${1:-}" = "--install" ]; then
  # 이전 프로세스가 완전히 끝난 뒤에 열어야 실행이 실패하지 않는다 (LaunchServices 오류 -600)
  pkill -x RisingKit 2>/dev/null || true
  while pgrep -x RisingKit >/dev/null; do sleep 0.2; done
  rm -rf "/Applications/Rising Kit.app"
  cp -R "$APP" /Applications/
  open "/Applications/Rising Kit.app"
  echo "설치 및 실행: /Applications/Rising Kit.app"
fi
