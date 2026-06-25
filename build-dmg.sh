#!/bin/bash
# Build a signed + notarized DMG of Mouse Smoothly for distribution.
#
# Pipeline:
#   1. xcodebuild Release  ->  the .app
#   2. re-sign the .app with Developer ID Application + Hardened Runtime
#   3. lay out the DMG (app + /Applications symlink + instructions)
#   4. create and sign the DMG
#   5. submit to Apple notary service and wait
#   6. staple the notarization ticket and verify
#
# Requires (one-time setup):
#   - A "Developer ID Application" certificate in the login keychain.
#   - A notarytool keychain profile (see NOTARY_PROFILE below), created with:
#       xcrun notarytool store-credentials "MouseSmoothly-Notary" \
#         --apple-id "<id>" --team-id 82PQ4FMW6T --password "<app-specific-pw>"

set -euo pipefail

# ---- Configuration (override via env vars if needed) -------------------------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mouse Smoothly"
SCHEME="$APP_NAME"
TEAM_ID="${TEAM_ID:-82PQ4FMW6T}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Ian Jolly ($TEAM_ID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MouseSmoothly-Notary}"
ENTITLEMENTS="$PROJECT_DIR/Mouse Smoothly/Entitlements.plist"

BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$BUILD_DIR/Release"
APP_PATH="$RELEASE_DIR/$APP_NAME.app"
DMG_NAME="Mouse-Smoothly.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
STAGE_DIR="$PROJECT_DIR/dmg-temp"

echo "🚀 Building signed + notarized DMG for $APP_NAME"
echo "   Identity: $SIGN_IDENTITY"

# ---- 1. Build the Release app -----------------------------------------------
echo "🔨 Building Release..."
rm -rf "$BUILD_DIR" "$STAGE_DIR" "$DMG_PATH"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CONFIGURATION_BUILD_DIR="$RELEASE_DIR" \
    build | tail -1

[ -d "$APP_PATH" ] || { echo "❌ Build product not found at $APP_PATH"; exit 1; }

# ---- 2. Re-sign with Developer ID + Hardened Runtime ------------------------
# The Automatic signing above uses the Apple Development cert; for distribution
# the app must be signed with Developer ID Application and a secure timestamp.
echo "✍️  Signing with Developer ID..."
codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"

echo "🔎 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# Gatekeeper assessment (will say "rejected" until notarization is stapled; that's fine here).
spctl -a -t exec -vv "$APP_PATH" 2>&1 || true

# ---- 3. Lay out the DMG contents -------------------------------------------
echo "📦 Preparing DMG contents..."
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

cat > "$STAGE_DIR/INSTALLATION.txt" << 'EOF'
Mouse Smoothly — Installation
=============================

1. Drag "Mouse Smoothly.app" onto the Applications folder.
2. Launch it from Applications (it lives in the menu bar).
3. When prompted, open System Settings -> Privacy & Security -> Accessibility
   and enable "Mouse Smoothly".

This build is signed with a Developer ID and notarized by Apple, so it should
open without Gatekeeper warnings.
EOF

# ---- 4. Create and sign the DMG --------------------------------------------
echo "💿 Creating DMG..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

echo "✍️  Signing DMG..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

# ---- 5. Notarize ------------------------------------------------------------
echo "☁️  Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# ---- 6. Staple + verify -----------------------------------------------------
echo "📎 Stapling ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" 2>&1 || true

# ---- Done -------------------------------------------------------------------
rm -rf "$STAGE_DIR"
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "✅ Done!  Notarized DMG ready:"
echo "   📍 $DMG_PATH  ($DMG_SIZE)"
