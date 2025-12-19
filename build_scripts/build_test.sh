#!/bin/bash
# Build an unsigned test copy of Mouse Smoothly (no notarization).
# Produces:
#   dist/Mouse Smoothly.app
#   dist/Mouse-Smoothly-unsigned.dmg (unsigned DMG for quick sharing)
#
# Environment overrides:
#   CONFIGURATION (default: Release)
#   DERIVED_DATA  (default: <repo>/.derived-data)
#   DIST_DIR      (default: <repo>/dist)
#   DMG_NAME      (default: Mouse-Smoothly-unsigned.dmg)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Mouse Smoothly"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$PROJECT_DIR/.derived-data}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
DMG_NAME="${DMG_NAME:-Mouse-Smoothly-unsigned.dmg}"
APP_NAME="Mouse Smoothly.app"
UNSIGNED_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
OUT_APP="$DIST_DIR/$APP_NAME"
DMG_STAGE="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$DMG_NAME"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

echo "Checking tooling..."
require_cmd xcodebuild
require_cmd hdiutil

echo "Cleaning old artifacts..."
rm -rf "$DERIVED_DATA" "$OUT_APP" "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DIST_DIR"

echo "Building $SCHEME ($CONFIGURATION) unsigned..."
xcodebuild \
  -project "$PROJECT_DIR/Mouse Smoothly.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

if [[ ! -d "$UNSIGNED_APP" ]]; then
    echo "Build failed: $UNSIGNED_APP not found" >&2
    exit 1
fi

echo "Preparing app bundle..."
cp -R "$UNSIGNED_APP" "$OUT_APP"

# Remove any stray nested bundles or plist copies left in Resources
find "$OUT_APP/Contents/Resources" -maxdepth 1 -name "*.app" -exec rm -rf {} +
rm -f "$OUT_APP/Contents/Resources/Entitlements.plist" "$OUT_APP/Contents/Resources/Info.plist"

echo "Creating unsigned DMG..."
mkdir -p "$DMG_STAGE"
cp -R "$OUT_APP" "$DMG_STAGE/$APP_NAME"
ln -s /Applications "$DMG_STAGE/Applications"

cat > "$DMG_STAGE/INSTALLATION.txt" <<'EOF'
Mouse Smoothly (unsigned test build)
------------------------------------

1. Drag "Mouse Smoothly.app" to Applications.
2. Launch it; grant Accessibility permission when prompted.
3. Hold Option while scrolling to temporarily bypass smoothing.

This DMG is unsigned/not notarized—macOS will warn about the developer. For public distribution, use the signed/notarized build process.
EOF

hdiutil create -volname "Mouse Smoothly" \
  -srcfolder "$DMG_STAGE" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGE"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "Test build ready:"
echo "  App: $OUT_APP"
echo "  DMG: $DMG_PATH ($DMG_SIZE)"
echo ""
echo "This build is UNSIGNED and UN-NOTARIZED; expect Gatekeeper prompts."
