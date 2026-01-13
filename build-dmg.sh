#!/bin/bash
# Build Mouse Smoothly DMG for distribution
# This creates an unsigned .dmg since code-signed versions break event tap functionality

set -e  # Exit on error

echo "🚀 Building Mouse Smoothly DMG..."

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCODE_BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/Mouse_Smoothly-bolhwtlczxeyrpddmuhzycsjqexa/Build/Products/Debug"
ICON_PATH="$PROJECT_DIR/macos_icons/AppIcon.icns"
DMG_NAME="Mouse-Smoothly.dmg"

# Clean up old builds
echo "🧹 Cleaning up old builds..."
rm -rf "$PROJECT_DIR/dmg-temp"
rm -f "$PROJECT_DIR/$DMG_NAME"

# Find the Xcode build (try multiple locations)
BUILT_APP=$(mdfind -name "Mouse Smoothly.app" | grep -i deriveddata | head -1)
if [ -z "$BUILT_APP" ]; then
    echo "❌ Error: Could not find Xcode build of Mouse Smoothly.app"
    echo "   Please build the project in Xcode first (Cmd+B)"
    exit 1
fi

echo "✅ Found Xcode build at: $BUILT_APP"

# Create temporary directory for DMG contents
echo "📦 Preparing DMG contents..."
mkdir -p dmg-temp

# Copy app
cp -R "$BUILT_APP" "dmg-temp/Mouse Smoothly.app"

# Add icon to app bundle
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "dmg-temp/Mouse Smoothly.app/Contents/Resources/AppIcon.icns"
    echo "✅ Added app icon"
else
    echo "⚠️  Warning: Icon not found at $ICON_PATH"
fi

# Create Applications symlink
ln -s /Applications "dmg-temp/Applications"

# Create installation instructions
cat > "dmg-temp/INSTALLATION.txt" << 'EOF'
Mouse Smoothly Installation Instructions
=========================================

IMPORTANT: This app uses system-level event monitoring which requires
special installation steps on macOS.

Installation Steps:
-------------------

1. Drag "Mouse Smoothly.app" to the Applications folder

2. Open System Settings → Privacy & Security → Accessibility

3. Click the lock icon and authenticate

4. Click the "+" button and navigate to /Applications

5. Select "Mouse Smoothly" and click "Open"

6. Make sure the toggle next to "Mouse Smoothly" is ON

7. Right-click on "Mouse Smoothly" in Applications and choose "Open"
   (Do NOT double-click - you must right-click → Open the first time)

8. Click "Open" when warned about an unidentified developer

9. The app will appear in your menu bar

Note: This app cannot be code-signed due to macOS restrictions on
event monitoring APIs. It is safe to use but requires the right-click
→ Open method on first launch to bypass Gatekeeper.

After the first launch with right-click → Open, you can launch it
normally by double-clicking.

For support, visit: https://github.com/YourUsername/Mouse-Smoothly
EOF

echo "✅ Created installation instructions"

# Create DMG
echo "💿 Creating DMG..."
hdiutil create -volname "Mouse Smoothly" \
    -srcfolder dmg-temp \
    -ov \
    -format UDZO \
    "$PROJECT_DIR/$DMG_NAME"

# Clean up
rm -rf dmg-temp

# Get file size
DMG_SIZE=$(du -h "$PROJECT_DIR/$DMG_NAME" | cut -f1)

echo ""
echo "✅ Success! DMG created:"
echo "   📍 Location: $PROJECT_DIR/$DMG_NAME"
echo "   📊 Size: $DMG_SIZE"
echo ""
echo "The DMG contains:"
echo "  - Mouse Smoothly.app (unsigned, working version)"
echo "  - Applications symlink"
echo "  - INSTALLATION.txt with user instructions"
echo ""
echo "Ready for distribution! 🎉"
