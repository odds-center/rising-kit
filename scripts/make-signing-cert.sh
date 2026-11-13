#!/bin/bash
# 로그인 키체인에 "Rising Kit Local Signing" 자체 서명 코드 서명 인증서를 만든다 (맥마다 한 번).
# 이 인증서로 서명하면 다시 빌드해도 손쉬운 사용 권한이 유지된다.
set -euo pipefail

NAME="Rising Kit Local Signing"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "이미 있습니다: $NAME"
  exit 0
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

cat > "$DIR/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# 시스템 기본 openssl(LibreSSL)을 써야 키체인이 읽을 수 있는 형식의 p12 가 나온다
PASS="$(/usr/bin/openssl rand -hex 12)"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
  -days 3650 -config "$DIR/cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
  -out "$DIR/id.p12" -passout "pass:$PASS"
security import "$DIR/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign

echo "만들어짐: $NAME"
