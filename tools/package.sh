#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "0.22.2")}"
DIST_DIR="$ROOT_DIR/build/dist"
STAGING_DIR="$ROOT_DIR/build/dist_staging"

if [ -z "${CI:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ]; then
    SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)}"
    if [ -z "$SIGNING_IDENTITY" ] || [ "$SIGNING_IDENTITY" = "-" ]; then
        "$ROOT_DIR/tools/setup_signing_cert.sh" >/dev/null 2>&1 || true
        SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "-")"
    fi
fi
[ -z "${SIGNING_IDENTITY:-}" ] && SIGNING_IDENTITY="-"

echo "=================================================="
echo " Packaging Cascade v$VERSION"
echo " Code Signing Identity: $SIGNING_IDENTITY"
echo " Output Directory: $DIST_DIR"
echo "=================================================="

rm -rf "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$STAGING_DIR/bin/arm64" "$STAGING_DIR/bin/x86_64" "$STAGING_DIR/bin/universal"
mkdir -p "$STAGING_DIR/app/arm64" "$STAGING_DIR/app/x86_64" "$STAGING_DIR/app/universal"

FRAMEWORKS="-framework Cocoa -framework ApplicationServices -framework Carbon -framework ServiceManagement"
CORE_SOURCES="$ROOT_DIR/src/WindowLayoutGeometry.m $ROOT_DIR/src/WindowEngine.m $ROOT_DIR/src/ScreenManager.m $ROOT_DIR/src/LoginItemManager.m $ROOT_DIR/src/WindowWatcher.m $ROOT_DIR/src/UpdateChecker.m"
BAR_SOURCES="$CORE_SOURCES $ROOT_DIR/src/AppOrderWindowController.m $ROOT_DIR/src/IgnoreListWindowController.m $ROOT_DIR/src/SettingsWindowController.m $ROOT_DIR/src/main_bar.m"
CLI_SOURCES="$CORE_SOURCES $ROOT_DIR/src/main_cli.m"

echo "==> 1. Compiling CLI binaries (arm64, x86_64, Universal)..."
clang -O2 -Wall -Wextra -fobjc-arc -arch arm64 -DCASCADE_VERSION=\"$VERSION\" $FRAMEWORKS $CLI_SOURCES -o "$STAGING_DIR/bin/arm64/cascade"
clang -O2 -Wall -Wextra -fobjc-arc -arch x86_64 -DCASCADE_VERSION=\"$VERSION\" $FRAMEWORKS $CLI_SOURCES -o "$STAGING_DIR/bin/x86_64/cascade"
lipo -create -output "$STAGING_DIR/bin/universal/cascade" "$STAGING_DIR/bin/arm64/cascade" "$STAGING_DIR/bin/x86_64/cascade"

codesign --force -s "$SIGNING_IDENTITY" "$STAGING_DIR/bin/arm64/cascade"
codesign --force -s "$SIGNING_IDENTITY" "$STAGING_DIR/bin/x86_64/cascade"
codesign --force -s "$SIGNING_IDENTITY" "$STAGING_DIR/bin/universal/cascade"

echo "==> 2. Building App Bundles (arm64, x86_64, Universal)..."
build_app_bundle() {
    local arch="$1"
    local dest_dir="$STAGING_DIR/app/$arch/Cascade.app"
    mkdir -p "$dest_dir/Contents/MacOS"
    mkdir -p "$dest_dir/Contents/Resources"

    if [ "$arch" = "universal" ]; then
        clang -O2 -Wall -Wextra -fobjc-arc -arch arm64 -arch x86_64 -DCASCADE_VERSION=\"$VERSION\" $FRAMEWORKS $BAR_SOURCES -o "$dest_dir/Contents/MacOS/Cascade"
    else
        clang -O2 -Wall -Wextra -fobjc-arc -arch "$arch" -DCASCADE_VERSION=\"$VERSION\" $FRAMEWORKS $BAR_SOURCES -o "$dest_dir/Contents/MacOS/Cascade"
    fi

    cp "$ROOT_DIR/resources/Info.plist" "$dest_dir/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$dest_dir/Contents/Info.plist" 2>/dev/null || true
    if [ -f "$ROOT_DIR/resources/AppIcon.icns" ]; then
        cp "$ROOT_DIR/resources/AppIcon.icns" "$dest_dir/Contents/Resources/AppIcon.icns"
    fi

    codesign --force --deep -s "$SIGNING_IDENTITY" "$dest_dir"
}

build_app_bundle "arm64"
build_app_bundle "x86_64"
build_app_bundle "universal"

echo "==> 3. Creating Drag-and-Drop .dmg Installers..."
build_dmg() {
    local arch="$1"
    local app_src="$STAGING_DIR/app/$arch/Cascade.app"
    local dmg_name="Cascade-v$VERSION-$arch.dmg"
    [ "$arch" = "universal" ] && dmg_name="Cascade-v$VERSION-Universal.dmg"

    local dmg_staging
    dmg_staging=$(mktemp -d /tmp/cascade-dmg-XXXXXX)
    cp -R "$app_src" "$dmg_staging/Cascade.app"
    ln -s /Applications "$dmg_staging/Applications"

    hdiutil create -volname "Cascade" -srcfolder "$dmg_staging" -ov -format UDZO "$DIST_DIR/$dmg_name" >/dev/null
    rm -rf "$dmg_staging"
    echo "    Created $dmg_name"
}

build_dmg "universal"
build_dmg "arm64"
build_dmg "x86_64"

echo "==> 4. Packaging Tarballs and Zip Archives..."
tar -czf "$DIST_DIR/cascade-v$VERSION-darwin-arm64.tar.gz" -C "$STAGING_DIR/bin/arm64" cascade
tar -czf "$DIST_DIR/cascade-v$VERSION-darwin-x86_64.tar.gz" -C "$STAGING_DIR/bin/x86_64" cascade
tar -czf "$DIST_DIR/cascade-v$VERSION-darwin-universal.tar.gz" -C "$STAGING_DIR/bin/universal" cascade

(cd "$STAGING_DIR/app/universal" && zip -q -r "$DIST_DIR/Cascade-v$VERSION-Universal.zip" Cascade.app)

echo "==> 5. Computing SHA-256 Checksums..."
(cd "$DIST_DIR" && shasum -a 256 *.dmg *.tar.gz *.zip > checksums.txt)

rm -rf "$STAGING_DIR"

echo "==> Distribution packaging complete:"
ls -lh "$DIST_DIR"
echo ""
cat "$DIST_DIR/checksums.txt"
