#!/usr/bin/env bash
#
# Creates a stable, self-signed code-signing identity named "MicFlip Dev" in
# your login keychain. Signing MicFlip with a fixed identity gives it a stable
# "designated requirement", so macOS privacy permissions (Input Monitoring,
# Microphone) granted to it persist across rebuilds — instead of breaking every
# time the binary's ad-hoc hash changes.
#
# Run this once. build.sh will then pick the identity up automatically.
#
set -euo pipefail

IDENTITY_NAME="MicFlip Dev"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "Identity '$IDENTITY_NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating self-signed code-signing certificate…"
openssl req -new -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -x509 -days 3650 \
    -out "$TMP/cert.pem" -subj "/CN=$IDENTITY_NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=critical,digitalSignature"

# -legacy keeps the PKCS12 MAC/PBE algorithms compatible with Apple's `security`
# tool (OpenSSL 3 defaults are not readable by it).
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/ident.p12" -passout pass:micflip -name "$IDENTITY_NAME"

echo "==> Importing into login keychain…"
security import "$TMP/ident.p12" -k ~/Library/Keychains/login.keychain-db \
    -P micflip -T /usr/bin/codesign -A

echo "==> Done. codesign identity:"
security find-identity -p codesigning | grep "$IDENTITY_NAME" || true
echo
echo "The certificate is self-signed and untrusted (CSSMERR_TP_NOT_TRUSTED) —"
echo "that's expected and fine for local signing. Now run: ./build.sh --run"
