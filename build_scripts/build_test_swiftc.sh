#!/bin/bash
# Build an unsigned test copy using swiftc directly (no asset catalogs, no notarization).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/Mouse Smoothly"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
APP_NAME="Mouse Smoothly.app"
OUT_APP="$DIST_DIR/$APP_NAME"
MODULE_CACHE="$PROJECT_DIR/.module-cache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ZIP_NAME="${ZIP_NAME:-Mouse-Smoothly-unsigned-swiftc.zip}"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

mkdir -p "$OUT_APP/Contents/MacOS" "$OUT_APP/Contents/Resources" "$MODULE_CACHE"

echo "Compiling with swiftc..."
swiftc -O -o "$OUT_APP/Contents/MacOS/Mouse Smoothly" \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx10.15 \
  -module-cache-path "$MODULE_CACHE" \
  "$SRC_DIR/main.swift" \
  "$SRC_DIR/Utils.swift" \
  "$SRC_DIR/ScrollEvent.swift" \
  "$SRC_DIR/ScrollPoster.swift" \
  "$SRC_DIR/ScrollManager.swift" \
  "$SRC_DIR/MenuBarController.swift" \
  "$SRC_DIR/DebugWindow.swift"

echo "Copying Info.plist and icon..."
cp "$SRC_DIR/Info.plist" "$OUT_APP/Contents/Info.plist"
cp "$SRC_DIR/AppIcon.png" "$OUT_APP/Contents/Resources/AppIcon.png"

echo "Zipping unsigned build..."
cd "$DIST_DIR"
rm -f "$ZIP_PATH"
zip -qry "$ZIP_NAME" "$APP_NAME" >/dev/null
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo ""
echo "Swiftc test build ready:"
echo "  App: $OUT_APP"
echo "  Zip: $ZIP_PATH ($ZIP_SIZE)"
