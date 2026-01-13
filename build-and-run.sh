#!/bin/bash
# Build and Run Mouse Smoothly from /Applications
# This ensures accessibility permissions stay stable

set -e  # Exit on error

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mouse Smoothly"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Build the app with Xcode
cd "$PROJECT_DIR"
xcodebuild -scheme "$APP_NAME" -configuration Debug build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" || true

# Check if build succeeded
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build succeeded"

# Find the built app
BUILT_APP=$(mdfind -name "$APP_NAME.app" | grep -i deriveddata | grep Debug | head -1)

if [ -z "$BUILT_APP" ]; then
    echo "❌ Could not find built app"
    echo "   Try building in Xcode first (Cmd+B)"
    exit 1
fi

echo "📦 Found build at: $BUILT_APP"

# Kill any running instances
echo "🛑 Stopping any running instances..."
pkill -9 "$APP_NAME" 2>/dev/null || true
sleep 1

# Install to /Applications (overwrite existing)
echo "📥 Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "✅ Installed to $INSTALL_PATH"

# Launch from /Applications
echo "🚀 Launching from /Applications..."
open "$INSTALL_PATH"

echo ""
echo "✨ Done!"
echo ""
echo "IMPORTANT: If you see accessibility permission dialogs:"
echo "  1. Remove any old 'Mouse Smoothly' entries from Accessibility settings"
echo "  2. Add only the /Applications version"
echo "  3. Quit and run this script again"
echo ""
