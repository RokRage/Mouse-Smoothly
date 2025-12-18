#!/bin/bash
# Build, sign, notarize, and package Mouse Smoothly for distribution.
# Requirements:
#   - Xcode command line tools (xcodebuild, notarytool, stapler)
#   - Developer ID Application certificate installed in login keychain
#   - An Apple developer account with notarization credentials
#
# Required environment variables:
#   DEVELOPER_ID   : Exact name of your "Developer ID Application: ..." certificate.
#   (and either)
#     NOTARY_PROFILE : Name of a keychain profile created via `xcrun notarytool store-credentials`
#   (or)
#     APPLE_ID / TEAM_ID / NOTARY_PASSWORD : Credentials for notarytool.
#
# Optional environment variables:
#   CONFIGURATION (default: Release)
#   DERIVED_DATA  (default: <repo>/.derived-data)
#   DIST_DIR      (default: <repo>/dist)
#   DMG_NAME      (default: Mouse-Smoothly.dmg)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Mouse Smoothly"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$PROJECT_DIR/.derived-data}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
DMG_NAME="${DMG_NAME:-Mouse-Smoothly.dmg}"
APP_NAME="Mouse Smoothly.app"
ENTITLEMENTS="$PROJECT_DIR/Mouse Smoothly/Entitlements.plist"

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Missing required command: $1" >&2
        exit 1
    fi
}

echo "🔍 Checking tooling..."
require_cmd xcodebuild
require_cmd codesign
require_cmd xcrun
require_cmd hdiutil

if [[ -z "$DEVELOPER_ID" ]]; then
    echo "❌ Set DEVELOPER_ID to your Developer ID Application certificate name." >&2
    exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$NOTARY_PASSWORD" ]]; then
        echo "❌ Provide either NOTARY_PROFILE or APPLE_ID/TEAM_ID/NOTARY_PASSWORD for notarization." >&2
        exit 1
    fi
fi

BUILD_PRODUCTS="$DERIVED_DATA/Build/Products/$CONFIGURATION"
UNSIGNED_APP="$BUILD_PRODUCTS/$APP_NAME"
SIGNED_APP="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_STAGE="$DIST_DIR/dmg-root"

echo "🧹 Cleaning previous artifacts..."
rm -rf "$DERIVED_DATA" "$SIGNED_APP" "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DIST_DIR"

echo "🏗  Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT_DIR/Mouse Smoothly.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

if [[ ! -d "$UNSIGNED_APP" ]]; then
    echo "❌ Build failed; $UNSIGNED_APP not found." >&2
    exit 1
fi

echo "📦 Copying build to $DIST_DIR..."
cp -R "$UNSIGNED_APP" "$SIGNED_APP"

# Xcode's build can leave an empty nested app bundle in Resources; remove it before signing
find "$SIGNED_APP/Contents/Resources" -maxdepth 1 -name "*.app" -exec rm -rf {} +
rm -f "$SIGNED_APP/Contents/Resources/Entitlements.plist" "$SIGNED_APP/Contents/Resources/Info.plist"

echo "🔏 Signing app with $DEVELOPER_ID ..."
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVELOPER_ID" \
    "$SIGNED_APP"

echo "✅ Verifying code signature..."
codesign --verify --verbose=2 --deep "$SIGNED_APP"
spctl --assess --type execute --verbose "$SIGNED_APP" >/dev/null

echo "💿 Preparing DMG contents..."
mkdir -p "$DMG_STAGE"
cp -R "$SIGNED_APP" "$DMG_STAGE/$APP_NAME"
ln -s /Applications "$DMG_STAGE/Applications"

cat > "$DMG_STAGE/INSTALLATION.txt" <<'EOF'
Mouse Smoothly Installation
===========================

This build is signed and notarized.

1. Drag "Mouse Smoothly.app" to the Applications folder shortcut.
2. Launch it normally from Applications (the menu bar icon will appear).
3. When prompted, grant Accessibility access to Mouse Smoothly so it can intercept scroll events.

If you later update the app, repeat the Accessibility permission step to refresh macOS privacy settings.

Support: https://github.com/YourUsername/Mouse-Smoothly
EOF

echo "📀 Creating $DMG_NAME ..."
hdiutil create -volname "Mouse Smoothly" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGE"

echo "📤 Submitting DMG for notarization..."
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --wait --progress \
        --keychain-profile "$NOTARY_PROFILE"
else
    xcrun notarytool submit "$DMG_PATH" --wait --progress \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$NOTARY_PASSWORD"
fi

echo "📎 Stapling tickets..."
xcrun stapler staple "$DMG_PATH" >/dev/null
xcrun stapler staple "$SIGNED_APP" >/dev/null

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "🎉 Release ready!"
echo "   App : $SIGNED_APP"
echo "   DMG : $DMG_PATH ($DMG_SIZE)"
echo ""
echo "Upload the DMG to GitHub Releases to distribute the signed + notarized build."
