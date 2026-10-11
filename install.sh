#!/usr/bin/env bash
# Cascade One-Line Installer for macOS (Intel & Apple Silicon)
# Usage: curl -fsSL https://raw.githubusercontent.com/brunobrise/cascade/main/install.sh | bash

set -euo pipefail

# 1. OS & Architecture Check
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    echo "❌ Error: Cascade is a native macOS window manager. Unsupported OS: $OS"
    exit 1
fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    arm64|aarch64) ARCH="arm64" ;;
    x86_64|amd64)   ARCH="x86_64" ;;
    *)
        echo "❌ Error: Unsupported architecture: $ARCH_RAW"
        exit 1
        ;;
esac

echo "=================================================="
echo " Cascade Installer (macOS $ARCH)"
echo "=================================================="

# Detect or auto-provision persistent code signing identity (preserves Accessibility permissions)
ensure_signing_certificate() {
    local identity
    identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -n "$identity" ]; then
        echo "$identity"
        return 0
    fi

    echo "🔐 Setting up local persistent code-signing certificate ('Cascade Code Signing')..." >&2
    local keychain="${HOME}/Library/Keychains/login.keychain-db"
    [ ! -f "$keychain" ] && keychain="${HOME}/Library/Keychains/login.keychain"

    if [ -f "$keychain" ] && command -v openssl >/dev/null 2>&1; then
        local tmp_cert_dir
        tmp_cert_dir=$(mktemp -d /tmp/cascade_cert_XXXXXX)
        local key_file="${tmp_cert_dir}/cascade_key.pem"
        local cert_file="${tmp_cert_dir}/cascade_cert.pem"
        local p12_file="${tmp_cert_dir}/cascade_cert.p12"
        local cnf_file="${tmp_cert_dir}/openssl.cnf"
        local pass="cascade-local-signing"

        cat > "${cnf_file}" << 'EOF'
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
        openssl req -x509 -newkey rsa:2048 -nodes -keyout "${key_file}" -out "${cert_file}" -days 3650 -config "${cnf_file}" >/dev/null 2>&1 || true
        openssl pkcs12 -export -inkey "${key_file}" -in "${cert_file}" -out "${p12_file}" -passout "pass:${pass}" -legacy >/dev/null 2>&1 || true
        security import "${p12_file}" -k "${keychain}" -P "${pass}" -T /usr/bin/codesign >/dev/null 2>&1 || true
        security add-trusted-cert -r trustRoot -p codeSign -k "${keychain}" "${cert_file}" >/dev/null 2>&1 || true
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "${keychain}" >/dev/null 2>&1 || true
        rm -rf "${tmp_cert_dir}"

        identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
        if [ -n "$identity" ]; then
            echo "✅ Created persistent signing certificate: '$identity'" >&2
            echo "$identity"
            return 0
        fi
    fi

    echo "⚠️  Could not auto-generate persistent cert. Falling back to ad-hoc signature." >&2
    echo "-"
}

SIGNING_IDENTITY=$(ensure_signing_certificate)

# 2. Determine Version
VERSION="${CASCADE_VERSION:-}"
if [ -z "$VERSION" ]; then
    echo "🔍 Determining latest release..."
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        VERSION=$(gh release view -R brunobrise/cascade --json tagName -q .tagName 2>/dev/null | sed 's/^v//' || true)
    fi
    if [ -z "$VERSION" ]; then
        AUTH_HEADER=()
        [ -n "${GITHUB_TOKEN:-}" ] && AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")
        LATEST_JSON=$(curl -sSL "${AUTH_HEADER[@]}" "https://api.github.com/repos/brunobrise/cascade/releases/latest" 2>/dev/null || true)
        VERSION=$(echo "$LATEST_JSON" | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//' || true)
    fi
    if [ -z "$VERSION" ]; then
        VERSION="0.23.0"
    fi
fi

TAG="v$VERSION"
echo "📦 Target Version: $TAG ($ARCH)"

TMP_DIR=$(mktemp -d /tmp/cascade-install-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

download_asset() {
    local asset_name="$1"
    local dest_path="$TMP_DIR/$asset_name"
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh release download "$TAG" -R brunobrise/cascade -p "$asset_name" -D "$TMP_DIR" >/dev/null 2>&1 && return 0
    fi
    local auth_header=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")
    local url="https://github.com/brunobrise/cascade/releases/download/$TAG/$asset_name"
    curl -fL "${auth_header[@]}" --progress-bar "$url" -o "$dest_path" 2>/dev/null && return 0
    return 1
}

# 3. Download and Install CLI
CLI_TARBALL="cascade-v$VERSION-darwin-$ARCH.tar.gz"
echo "⬇️  Downloading CLI binary: $CLI_TARBALL..."
if download_asset "$CLI_TARBALL"; then
    tar -xzf "$TMP_DIR/$CLI_TARBALL" -C "$TMP_DIR"
    INSTALL_BIN="$HOME/.local/bin"
    mkdir -p "$INSTALL_BIN"
    cp "$TMP_DIR/cascade" "$INSTALL_BIN/cascade"
    chmod +x "$INSTALL_BIN/cascade"
    codesign --force -s "$SIGNING_IDENTITY" "$INSTALL_BIN/cascade" 2>/dev/null || true
    xattr -cr "$INSTALL_BIN/cascade" 2>/dev/null || true
    echo "✅ Installed 'cascade' CLI to $INSTALL_BIN/cascade"
else
    echo "⚠️  Could not download pre-built CLI tarball. Continuing with App installer..."
fi

# 4. Download and Install App Bundle (DMG)
DMG_NAME="Cascade-v$VERSION-Universal.dmg"
echo "⬇️  Downloading App installer: $DMG_NAME..."
if download_asset "$DMG_NAME"; then
    MOUNT_DIR="$TMP_DIR/mount"
    mkdir -p "$MOUNT_DIR"
    echo "📂 Mounting disk image..."
    hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$TMP_DIR/$DMG_NAME" >/dev/null

    TARGET_APP_DIR="/Applications"
    if [ ! -w "$TARGET_APP_DIR" ]; then
        TARGET_APP_DIR="$HOME/Applications"
        mkdir -p "$TARGET_APP_DIR"
        rm -rf "/Applications/Cascade.app" 2>/dev/null || true
    else
        # Remove legacy duplicate in user Applications to prevent TCC conflict
        rm -rf "$HOME/Applications/Cascade.app" 2>/dev/null || true
    fi

    echo "🚀 Installing Cascade.app to $TARGET_APP_DIR..."
    pkill -x Cascade 2>/dev/null || true
    rm -rf "$TARGET_APP_DIR/Cascade.app"
    cp -R "$MOUNT_DIR/Cascade.app" "$TARGET_APP_DIR/Cascade.app"
    hdiutil detach "$MOUNT_DIR" >/dev/null || true

    codesign --force --deep -s "$SIGNING_IDENTITY" "$TARGET_APP_DIR/Cascade.app" 2>/dev/null || true
    xattr -cr "$TARGET_APP_DIR/Cascade.app" 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r "$TARGET_APP_DIR/Cascade.app" 2>/dev/null || true
    echo "✅ Installed Cascade.app to $TARGET_APP_DIR/Cascade.app"
    echo "🔏 Signed with identity: $SIGNING_IDENTITY"
else
    echo "⚠️  Could not download DMG directly from GitHub."
fi

# 5. Accessibility & Launch
echo ""
echo "=================================================="
echo "🎉 Installation Complete!"
echo "=================================================="
echo ""
echo "Quick Start:"
echo "  1. Launch Cascade:  open -a ~/Applications/Cascade.app (or /Applications/Cascade.app)"
echo "  2. Grant Accessibility permissions in System Settings when prompted."
echo "  3. Cascade shortcut: Option + Command + C (⌥⌘C) to arrange active windows."
echo ""
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "💡 Note: Add ~/.local/bin to your PATH to use the 'cascade' command line tool:"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo ""
