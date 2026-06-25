Mouse Smoothly
==============

<p align="center">
  <img src="Mouse%20Smoothly/AppIcon.png" alt="Mouse Smoothly app icon" width="160">
</p>

Mouse Smoothly is a macOS menu bar utility that makes a standard mouse wheel feel closer to trackpad scrolling. It intercepts traditional mouse-wheel events, smooths them via a display-link loop, and reposts them as pixel/line scrolls.

From the menu bar you can tune speed, friction, acceleration, and the acceleration curve, toggle natural scrolling and launch-at-login, and open a floating debug log window.

It can also remap a mouse's extra (thumb) buttons to Page Up, Page Down, Home, or End — with Page Up/Down flowing through the same smooth-scroll engine instead of jumping.


Project Layout
--------------
- `Mouse Smoothly/` — App sources and assets.
- `Mouse Smoothly.xcodeproj` — Xcode project.
- `build-dmg.sh` — Build, sign, notarize, and package a distributable DMG.
- `build-and-run.sh` — Build and install to /Applications, then launch (for local testing with stable Accessibility permissions).

Identifiers and Permissions
---------------------------
- Bundle identifier: `com.rokrage.Mouse-Smoothly` (set in the Xcode project and `Mouse Smoothly/Info.plist`). If you fork or rename, update it consistently.
- Launch-at-login helper writes `~/Library/LaunchAgents/com.rokrage.mousesmoothly.plist`. If you change the bundle ID domain, update this to match.
- The app requires Accessibility permission. On first launch it will guide the user to System Settings → Privacy & Security → Accessibility to enable the toggle.
- Hold Option while scrolling to temporarily bypass smoothing.
- Per-app toggle: Use the menu item “Disable/Enable Smooth Scroll for <App>” (updates to the frontmost app). This writes to the exclusion list in `UserDefaults`.
- Mouse buttons: Use the “Mouse Buttons” menu to map extra buttons (3–6) to Page Up, Page Down, Home, or End. Press a button to see its number in the menu hint, then pick an action. Page Up/Down smooth-scroll one focused-window height per press; mappings are stored in `UserDefaults` under `MouseSmoothly.buttonMappings`.
- Exclusion list can also be set manually via `MouseSmoothly.excludedBundleIDs`. Example:
  ```
  defaults write com.rokrage.Mouse-Smoothly MouseSmoothly.excludedBundleIDs -array "com.google.Chrome" "org.godotengine.godot"
  ```

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
Use `build-dmg.sh` to produce a signed, notarized DMG. Requirements: Xcode command-line tools, a "Developer ID Application" certificate in your login keychain, and a notarytool keychain profile.

One-time setup — create the notary keychain profile:
```
xcrun notarytool store-credentials "MouseSmoothly-Notary" \
  --apple-id "<your-apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
```

Then build:
```
./build-dmg.sh
```

Overridable via env vars (sensible defaults are baked in): `TEAM_ID`, `SIGN_IDENTITY` (Developer ID Application identity), and `NOTARY_PROFILE` (the keychain profile name).

What the script does:
1. Builds the Xcode project (Release, into a local `build/` directory).
2. Re-signs the app with the Developer ID identity, hardened runtime, a secure timestamp, and your entitlements.
3. Lays out `Mouse-Smoothly.dmg` with an Applications symlink and an installation note.
4. Signs the DMG, submits it for notarization, waits, then staples and validates the ticket.

Troubleshooting
---------------
- Accessibility denied: open System Settings → Privacy & Security → Accessibility, add/enable Mouse Smoothly, then relaunch.
- Notarization failures: run `xcrun notarytool log <ID> --keychain-profile "$NOTARY_PROFILE"` to read the issue. Common causes are wrong certificate name, missing hardened runtime, or unsigned nested bundles.
- Launch at login not working: ensure the LaunchAgent plist matches your bundle domain and that the app path is stable (typically in /Applications). Delete old `~/Library/LaunchAgents/com.*mousesmoothly.plist` files after changing the domain.
