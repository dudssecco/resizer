#!/bin/bash
# Run once. Creates a local self-signed code-signing certificate in your login
# keychain. build.sh signs with it, so every build has the same signature and
# macOS keeps the Accessibility permission between builds (with ad-hoc signing
# each build looks like a new app and the permission is lost).
set -euo pipefail

NAME="Resizer Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "✅ \"$NAME\" already exists in your keychain."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
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

# The system's openssl (LibreSSL) writes a .p12 that `security import` can read.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout pass:resizer

# -T lets codesign use the key without a keychain prompt on every build.
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P resizer -T /usr/bin/codesign

echo "✅ Created \"$NAME\". Now run ./build.sh --install"
