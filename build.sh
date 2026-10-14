#!/bin/bash
# Builds Monte.app, packages it into Monte-<VERSION>.dmg, and installs to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Monte"
VERSION="${1:-${VERSION:-$(cat VERSION 2>/dev/null || echo "2.0.0")}}"
VERSION="$(echo "$VERSION" | tr -d '[:space:]')"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
PACKAGES_DIR="Packages"

echo "==> [1/5] Building release binary with SwiftPM"
swift build -c release

echo "==> [2/5] Assembling macOS app bundle"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> [3/5] Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> [4/5] Creating DMG installer package"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
RW_DMG="$DIST_DIR/$APP_NAME-rw.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDRW "$RW_DMG"

MOUNT_DIR=$(mktemp -d)
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
    SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR"

hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -ov -quiet
rm -f "$RW_DMG"

# Export to Packages directory
mkdir -p "$PACKAGES_DIR"
cp "$DMG_PATH" "$PACKAGES_DIR/$APP_NAME-$VERSION.dmg"
echo "==> Exported DMG to $PACKAGES_DIR/$APP_NAME-$VERSION.dmg"

echo "==> [5/5] Installing to /Applications"
# Terminate running instance if any before replacing
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
echo "==> Successfully installed $APP_NAME.app to /Applications/$APP_NAME.app"

echo "==> Done! 🎉"
