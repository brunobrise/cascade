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

# 2. Determine Version
VERSION="${CASCADE_VERSION:-}"
if [ -z "$VERSION" ]; then
    echo "🔍 Fetching latest release from GitHub..."
    LATEST_JSON=$(curl -sSL "https://api.github.com/repos/brunobrise/cascade/releases/latest" 2>/dev/null || true)
    VERSION=$(echo "$LATEST_JSON" | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')
    if [ -z "$VERSION" ]; then
        VERSION="0.22.2"
    fi
fi

TAG="v$VERSION"
echo "📦 Target Version: $TAG ($ARCH)"

TMP_DIR=$(mktemp -d /tmp/cascade-install-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# 3. Download and Install CLI
CLI_TARBALL="cascade-v$VERSION-darwin-$ARCH.tar.gz"
DOWNLOAD_URL="https://github.com/brunobrise/cascade/releases/download/$TAG/$CLI_TARBALL"
echo "⬇️  Downloading CLI binary: $CLI_TARBALL..."
if curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/$CLI_TARBALL"; then
    tar -xzf "$TMP_DIR/$CLI_TARBALL" -C "$TMP_DIR"
    INSTALL_BIN="$HOME/.local/bin"
    mkdir -p "$INSTALL_BIN"
    cp "$TMP_DIR/cascade" "$INSTALL_BIN/cascade"
    chmod +x "$INSTALL_BIN/cascade"
    codesign --force -s - "$INSTALL_BIN/cascade" 2>/dev/null || true
    echo "✅ Installed 'cascade' CLI to $INSTALL_BIN/cascade"
else
    echo "⚠️  Could not download pre-built CLI tarball. Continuing with App installer..."
fi

# 4. Download and Install App Bundle (DMG)
DMG_NAME="Cascade-v$VERSION-Universal.dmg"
DMG_URL="https://github.com/brunobrise/cascade/releases/download/$TAG/$DMG_NAME"
echo "⬇️  Downloading App installer: $DMG_NAME..."
if curl -fL --progress-bar "$DMG_URL" -o "$TMP_DIR/$DMG_NAME"; then
    MOUNT_DIR="$TMP_DIR/mount"
    mkdir -p "$MOUNT_DIR"
    echo "📂 Mounting disk image..."
    hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$TMP_DIR/$DMG_NAME" >/dev/null

    TARGET_APP_DIR="/Applications"
    if [ ! -w "$TARGET_APP_DIR" ]; then
        TARGET_APP_DIR="$HOME/Applications"
        mkdir -p "$TARGET_APP_DIR"
    fi

    echo "🚀 Installing Cascade.app to $TARGET_APP_DIR..."
    pkill -x Cascade 2>/dev/null || true
    rm -rf "$TARGET_APP_DIR/Cascade.app"
    cp -R "$MOUNT_DIR/Cascade.app" "$TARGET_APP_DIR/Cascade.app"
    hdiutil detach "$MOUNT_DIR" >/dev/null || true

    codesign --force --deep -s - "$TARGET_APP_DIR/Cascade.app" 2>/dev/null || true
    echo "✅ Installed Cascade.app to $TARGET_APP_DIR/Cascade.app"
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
