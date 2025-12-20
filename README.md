Mouse Smoothly
==============

<p align="center">
  <img src="Mouse%20Smoothly/AppIcon.png" alt="Mouse Smoothly app icon" width="160">
</p>

Mouse Smoothly is a macOS menu bar utility that intercepts traditional mouse-wheel events, smooths them via a display-link loop, and reposts them as pixel/line scrolls so apps feel closer to trackpad scrolling. It exposes menu sliders for speed, friction, acceleration, acceleration curves, natural scrolling, launch-at-login, and a floating debug log window.


Project Layout
--------------
- `Mouse Smoothly/` — App sources and assets.
- `Mouse Smoothly.xcodeproj` — Xcode project.
- `build_scripts/build_release.sh` — Build, sign, notarize, and package script.

Identifiers and Permissions
---------------------------
- Bundle identifier: `com.rokrage.Mouse-Smoothly` (set in the Xcode project and `Mouse Smoothly/Info.plist`). If you fork or rename, update it consistently.
- Launch-at-login helper writes `~/Library/LaunchAgents/com.rokrage.mousesmoothly.plist`. If you change the bundle ID domain, update this to match.
- The app requires Accessibility permission. On first launch it will guide the user to System Settings → Privacy & Security → Accessibility to enable the toggle.

Developing and Running
----------------------
- Open `Mouse Smoothly.xcodeproj` in Xcode and build/run the “Mouse Smoothly” scheme (Debug or Release).
- Alternatively, from the repo root you can build with:
  ```
  xcodebuild -project "Mouse Smoothly.xcodeproj" -scheme "Mouse Smoothly" -configuration Debug -derivedDataPath .derived-data
  ```
- Settings are stored in `UserDefaults` under the bundle identifier; changing the bundle ID will reset saved slider values unless you migrate them.
- Hold the Option key while scrolling to temporarily bypass smoothing and send the raw wheel events through unchanged.

Signed and Notarized Release
----------------------------
Use `build_scripts/build_release.sh` to produce a signed, notarized app and DMG. Requirements: Xcode command-line tools, a Developer ID Application certificate, and notarization credentials.

Example workflow:
```
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="MouseSmoothlyProfile"   # created via `xcrun notarytool store-credentials`
./build_scripts/build_release.sh
```

What the script does:
1. Builds the Xcode project (Release, using a local derived data path).
2. Cleans stray nested bundles, signs the app with hardened runtime and your entitlements.
3. Creates `dist/Mouse-Smoothly.dmg` with an Applications symlink and install note.
4. Submits the DMG for notarization, waits, and staples tickets to the DMG and app.

If you prefer not to use a keychain profile, set `APPLE_ID`, `TEAM_ID`, and `NOTARY_PASSWORD` instead of `NOTARY_PROFILE`. Additional overrides: `CONFIGURATION`, `DERIVED_DATA`, `DIST_DIR`, `DMG_NAME`.

Troubleshooting
---------------
- Accessibility denied: open System Settings → Privacy & Security → Accessibility, add/enable Mouse Smoothly, then relaunch.
- Notarization failures: run `xcrun notarytool log <ID> --keychain-profile "$NOTARY_PROFILE"` to read the issue. Common causes are wrong certificate name, missing hardened runtime, or unsigned nested bundles.
- Launch at login not working: ensure the LaunchAgent plist matches your bundle domain and that the app path is stable (typically in /Applications). Delete old `~/Library/LaunchAgents/com.*mousesmoothly.plist` files after changing the domain.
