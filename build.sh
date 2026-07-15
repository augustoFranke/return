#!/bin/bash
set -euo pipefail

PRODUCT="Return"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/$PRODUCT.app"
DMG_PATH="$ROOT/$PRODUCT.dmg"
DMG_STAGING="$ROOT/.dmg-staging"
APPLICATIONS_DIR="/Applications/$PRODUCT.app"
MODE="${1:-install}"

if [[ "$MODE" != "install" && "$MODE" != "package" ]]; then
  echo "Usage: $0 [install|package]"
  echo "  install  Build app + DMG and copy to /Applications (default)"
  echo "  package  Build app + DMG only (no install)"
  exit 1
fi

echo "Building $PRODUCT..."
cd "$ROOT"
swift build -c release

echo "Generating app icon..."
chmod +x "$ROOT/scripts/generate_icon.swift"
swift "$ROOT/scripts/generate_icon.swift"

echo "Packaging $PRODUCT.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$PRODUCT" "$APP_DIR/Contents/MacOS/$PRODUCT"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
chmod +x "$APP_DIR/Contents/MacOS/$PRODUCT"
xattr -cr "$APP_DIR"

echo "Signing $PRODUCT.app..."
codesign --force --deep --sign - "$APP_DIR"

echo "Setting app icon..."
chmod +x "$ROOT/scripts/set_icon.swift"
swift "$ROOT/scripts/set_icon.swift" --icon "$ROOT/AppIcon.icns" --target "$APP_DIR"

echo "Creating $PRODUCT.dmg..."
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$PRODUCT" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"

echo "Setting DMG icon..."
swift "$ROOT/scripts/set_icon.swift" --icon "$ROOT/AppIcon.icns" --target "$DMG_PATH"

if [[ "$MODE" == "install" ]]; then
  echo "Installing to $APPLICATIONS_DIR..."
  pkill -x Return 2>/dev/null || true
  rm -rf "$APPLICATIONS_DIR"
  ditto "$APP_DIR" "$APPLICATIONS_DIR"
  swift "$ROOT/scripts/set_icon.swift" --icon "$ROOT/AppIcon.icns" --target "$APPLICATIONS_DIR"
  xattr -cr "$APPLICATIONS_DIR"
  touch "$APPLICATIONS_DIR"
  /usr/bin/qlmanage -r cache 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true
fi

echo ""
echo "Done."
echo "  App:  $APP_DIR"
echo "  DMG:  $DMG_PATH"
if [[ "$MODE" == "install" ]]; then
  echo "  Installed: $APPLICATIONS_DIR"
  echo "  Run:  open -a Return"
else
  echo "  Package-only build (not installed to /Applications)"
fi