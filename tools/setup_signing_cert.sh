#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="Cascade Code Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if [ ! -f "$KEYCHAIN" ]; then
    KEYCHAIN="${HOME}/Library/Keychains/login.keychain"
fi

if [ ! -f "$KEYCHAIN" ]; then
    echo "Error: Login keychain not found at ${KEYCHAIN}" >&2
    exit 1
fi

# 1. Check if identity already exists and is trusted
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "${CERT_NAME}"; then
    echo "Certificate '${CERT_NAME}' is already installed, trusted, and ready for codesign."
    exit 0
fi

echo "Setting up local persistent code-signing certificate: '${CERT_NAME}'..."

TMP_DIR=$(mktemp -d /tmp/cascade_cert_XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

KEY_FILE="${TMP_DIR}/cascade_key.pem"
CERT_FILE="${TMP_DIR}/cascade_cert.pem"
P12_FILE="${TMP_DIR}/cascade_cert.p12"
CNF_FILE="${TMP_DIR}/openssl.cnf"
PASS="cascade-local-signing"

cat > "${CNF_FILE}" << 'EOF'
[req]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_ca

[req_dn]
CN = Cascade Code Signing
O = Bruno BriSe Local Development
C = FR

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyCertSign, cRLSign
extendedKeyUsage = critical, codeSigning
EOF

# 2. Generate private key and self-signed certificate (valid for 10 years / 3650 days)
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -days 3650 \
    -config "${CNF_FILE}" >/dev/null 2>&1

# 3. Export to PKCS12 format (with -legacy for OpenSSL 3 / macOS Security framework compatibility)
openssl pkcs12 -export \
    -inkey "${KEY_FILE}" \
    -in "${CERT_FILE}" \
    -out "${P12_FILE}" \
    -passout "pass:${PASS}" \
    -legacy >/dev/null 2>&1

# 4. Import PKCS12 identity into the login keychain
security import "${P12_FILE}" \
    -k "${KEYCHAIN}" \
    -P "${PASS}" \
    -T /usr/bin/codesign >/dev/null

# 5. Add user trust settings for the codeSign policy
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "${KEYCHAIN}" \
    "${CERT_FILE}" >/dev/null

# 6. Authorize codesign tool to access the private key without interactive prompts
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" \
    "${KEYCHAIN}" >/dev/null 2>&1 || true

# 7. Verification
if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "${CERT_NAME}"; then
    echo "Successfully generated and trusted '${CERT_NAME}'."
    echo "Designated requirements will now remain permanent across all updates and rebuilds."
else
    echo "Warning: Certificate imported, but verify with: security find-identity -v -p codesigning"
fi
