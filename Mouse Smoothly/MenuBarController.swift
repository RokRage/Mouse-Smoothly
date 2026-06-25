import Cocoa

class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var enabledMenuItem: NSMenuItem!
    private var launchAtStartupMenuItem: NSMenuItem!
    private var debugWindowMenuItem: NSMenuItem!
    private var naturalScrollMenuItem: NSMenuItem!
    private var appToggleMenuItem: NSMenuItem!
    private var mouseButtonsMenu: NSMenu!
    private var speedSlider: NSSlider!
    private var frictionSlider: NSSlider!
    private var accelSlider: NSSlider!
    private var speedLabel: NSTextField!
    private var frictionLabel: NSTextField!
    private var accelLabel: NSTextField!
    
    // Use LaunchAgent (user-level) for app bundles
    private var launchAgentPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/LaunchAgents/com.rokrage.mousesmoothly.plist"
    }
    
    var isEnabled = true {
        didSet {
            updateEnabledState()
        }
    }
    
    override init() {
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "🖱️"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        
        // Enable/Disable toggle
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Speed slider
        let speedItem = NSMenuItem()
        speedItem.view = createSliderView(
            label: "Speed",
            minValue: 20,
            maxValue: 200,
            currentValue: ScrollPoster.shared.speedMulti,
            action: #selector(speedChanged(_:)),
            sliderRef: &speedSlider,
            labelRef: &speedLabel
        )
        menu.addItem(speedItem)
        
        // Friction slider
        let frictionItem = NSMenuItem()
        frictionItem.view = createSliderView(
            label: "Friction",
            minValue: 0.02,
            maxValue: 0.3,
            currentValue: ScrollPoster.shared.friction,
            action: #selector(frictionChanged(_:)),
            sliderRef: &frictionSlider,
            labelRef: &frictionLabel
        )
        menu.addItem(frictionItem)
        
        // Acceleration slider
        let accelItem = NSMenuItem()
        accelItem.view = createSliderView(
            label: "Accel",
            minValue: 0,
            maxValue: 3,
            currentValue: ScrollPoster.shared.accelFactor,
            action: #selector(accelChanged(_:)),
            sliderRef: &accelSlider,
            labelRef: &accelLabel
        )
        menu.addItem(accelItem)
        
        // Acceleration Curve submenu
        let curveMenu = NSMenu()
        for curve in ScrollPoster.AccelCurve.allCases {
            let item = NSMenuItem(title: curve.name, action: #selector(selectCurve(_:)), keyEquivalent: "")
            item.target = self
            item.tag = curve.rawValue
            item.state = ScrollPoster.shared.accelCurve == curve ? .on : .off
            curveMenu.addItem(item)
        }
        let curveMenuItem = NSMenuItem(title: "Accel Curve", action: nil, keyEquivalent: "")
        curveMenuItem.submenu = curveMenu
        menu.addItem(curveMenuItem)
        
        // Mouse Buttons remapping
        let buttonsMenu = NSMenu()
        buttonsMenu.delegate = self
        buildButtonsMenu(buttonsMenu)
        mouseButtonsMenu = buttonsMenu
        let buttonsMenuItem = NSMenuItem(title: "Mouse Buttons", action: nil, keyEquivalent: "")
        buttonsMenuItem.submenu = buttonsMenu
        menu.addItem(buttonsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Natural Scroll (invert direction)
        naturalScrollMenuItem = NSMenuItem(title: "Natural Scroll", action: #selector(toggleNaturalScroll), keyEquivalent: "")
        naturalScrollMenuItem.target = self
        naturalScrollMenuItem.state = ScrollPoster.shared.naturalScroll ? .on : .off
        menu.addItem(naturalScrollMenuItem)
        
        // Per-app toggle
        appToggleMenuItem = NSMenuItem(title: "Disable Smooth Scroll for Current App", action: #selector(toggleAppExclusion), keyEquivalent: "")
        appToggleMenuItem.target = self
        appToggleMenuItem.isEnabled = false
        menu.addItem(appToggleMenuItem)
        
        // Launch at Startup
        launchAtStartupMenuItem = NSMenuItem(title: "Launch at Startup", action: #selector(toggleLaunchAtStartup), keyEquivalent: "")
        launchAtStartupMenuItem.target = self
        launchAtStartupMenuItem.state = FileManager.default.fileExists(atPath: launchAgentPath) ? .on : .off
        menu.addItem(launchAtStartupMenuItem)
        
        // Show Debug Window
        debugWindowMenuItem = NSMenuItem(title: "Show Debug Window", action: #selector(toggleDebugWindow), keyEquivalent: "d")
        debugWindowMenuItem.target = self
        debugWindowMenuItem.state = .off  // Starts hidden
        menu.addItem(debugWindowMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Help
        let helpItem = NSMenuItem(title: "?  Help", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func createSliderView(label: String, minValue: Double, maxValue: Double, currentValue: Double, action: Selector, sliderRef: inout NSSlider!, labelRef: inout NSTextField!) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        // Disable autoresizing to prevent layout conflicts in NSMenuItem
        view.autoresizingMask = []
        
        // Label
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.frame = NSRect(x: 15, y: 20, width: 60, height: 16)
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.autoresizingMask = []
        view.addSubview(titleLabel)
        
        // Value label
        let valueLabel = NSTextField(labelWithString: formatValue(currentValue, isSpeed: label == "Speed"))
        valueLabel.frame = NSRect(x: 170, y: 20, width: 40, height: 16)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.autoresizingMask = []
        view.addSubview(valueLabel)
        labelRef = valueLabel
        
        // Slider
        let slider = NSSlider(value: currentValue, minValue: minValue, maxValue: maxValue, target: self, action: action)
        slider.frame = NSRect(x: 15, y: 2, width: 190, height: 20)
        slider.isContinuous = true
        slider.autoresizingMask = []
        view.addSubview(slider)
        sliderRef = slider
        
        return view
    }
    
    private func formatValue(_ value: Double, isSpeed: Bool) -> String {
        if isSpeed {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func updateEnabledState() {
        enabledMenuItem.state = isEnabled ? .on : .off
        if isEnabled {
            ScrollManager.shared.start()
            statusItem.button?.title = "🖱️"
        } else {
            ScrollManager.shared.stop()
            statusItem.button?.title = "🖱️⏸"
        }
    }
    
    @objc private func toggleEnabled() {
        isEnabled.toggle()
        enabledMenuItem.state = isEnabled ? .on : .off
        
        if isEnabled {
            ScrollManager.shared.start()
            statusItem.button?.title = "🖱️"
        } else {
            ScrollManager.shared.stop()
            statusItem.button?.title = "🖱️⏸"
        }
    }
    
    @objc private func speedChanged(_ sender: NSSlider) {
        ScrollPoster.shared.speedMulti = sender.doubleValue
        speedLabel.stringValue = formatValue(sender.doubleValue, isSpeed: true)
    }
    
    @objc private func frictionChanged(_ sender: NSSlider) {
        ScrollPoster.shared.friction = sender.doubleValue
        frictionLabel.stringValue = formatValue(sender.doubleValue, isSpeed: false)
    }
    
    @objc private func accelChanged(_ sender: NSSlider) {
        ScrollPoster.shared.accelFactor = sender.doubleValue
        accelLabel.stringValue = formatValue(sender.doubleValue, isSpeed: false)
    }
    
    @objc private func selectCurve(_ sender: NSMenuItem) {
        guard let curve = ScrollPoster.AccelCurve(rawValue: sender.tag) else { return }
        ScrollPoster.shared.accelCurve = curve
        
        // Update checkmarks in submenu
        if let menu = sender.menu {
            for item in menu.items {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }
    
    // MARK: - Mouse Buttons submenu

    private func buildButtonsMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Hint showing the most recently pressed button so users can identify
        // which physical button maps to which number.
        let hintTitle: String
        if let last = ButtonManager.shared.lastButtonPressed {
            hintTitle = "Last pressed: Button \(last)"
        } else {
            hintTitle = "Press an extra button to detect it"
        }
        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(NSMenuItem.separator())

        for button in ButtonManager.mappableButtons {
            let current = ButtonManager.shared.action(for: button)
            let buttonItem = NSMenuItem(title: "Button \(button)", action: nil, keyEquivalent: "")

            let actionMenu = NSMenu()
            for action in ButtonAction.allCases {
                let item = NSMenuItem(title: action.name, action: #selector(selectButtonAction(_:)), keyEquivalent: "")
                item.target = self
                // Encode button + action in the tag: button * 100 + action.
                item.tag = Int(button) * 100 + action.rawValue
                item.state = current == action ? .on : .off
                actionMenu.addItem(item)
            }
            buttonItem.submenu = actionMenu

            // Show the current mapping inline next to the button name.
            if current != .none {
                buttonItem.title = "Button \(button)  →  \(current.name)"
            }
            menu.addItem(buttonItem)
        }
    }

    @objc private func selectButtonAction(_ sender: NSMenuItem) {
        let button = Int64(sender.tag / 100)
        guard let action = ButtonAction(rawValue: sender.tag % 100) else { return }
        ButtonManager.shared.setAction(action, for: button)
        if let menu = mouseButtonsMenu {
            buildButtonsMenu(menu)
        }
    }

    @objc private func toggleNaturalScroll() {
        ScrollPoster.shared.naturalScroll.toggle()
        naturalScrollMenuItem.state = ScrollPoster.shared.naturalScroll ? .on : .off
    }
    
    @objc private func toggleAppExclusion() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            return
        }
        let nowExcluded = ScrollManager.shared.toggleExclusion(bundleID: bundleID)
        let name = app.localizedName ?? "App"
        updateAppToggleMenuItem(name: name, bundleID: bundleID, excluded: nowExcluded)
    }
    
    private func updateAppToggleMenuItem(name: String, bundleID: String, excluded: Bool) {
        appToggleMenuItem.isEnabled = true
        appToggleMenuItem.state = excluded ? .on : .off
        appToggleMenuItem.title = excluded ? "Enable Smooth Scroll for \(name)" : "Disable Smooth Scroll for \(name)"
        appToggleMenuItem.toolTip = bundleID
    }
    
    private func refreshAppToggleMenuItem() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            appToggleMenuItem.title = "Current app unavailable"
            appToggleMenuItem.isEnabled = false
            appToggleMenuItem.state = .off
            appToggleMenuItem.toolTip = nil
            return
        }
        let name = app.localizedName ?? "App"
        let excluded = ScrollManager.shared.isExcluded(bundleID: bundleID)
        updateAppToggleMenuItem(name: name, bundleID: bundleID, excluded: excluded)
    }
    
    @objc private func toggleLaunchAtStartup() {
        let fm = FileManager.default
        
        if fm.fileExists(atPath: launchAgentPath) {
            // Remove the plist
            do {
                try fm.removeItem(atPath: launchAgentPath)
                launchAtStartupMenuItem.state = .off
            } catch {
                // Silently fail
            }
        } else {
            // Create the plist
            // Get the path to the app bundle (parent of MacOS folder)
            let execPath = ProcessInfo.processInfo.arguments[0]
            var appPath = (execPath as NSString).deletingLastPathComponent
            appPath = (appPath as NSString).deletingLastPathComponent
            appPath = (appPath as NSString).deletingLastPathComponent  // Go up 3 levels: MacOS -> Contents -> Mouse Smoothly.app
            
            let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rokrage.mousesmoothly</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>\(appPath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
            do {
                try plistContent.write(toFile: launchAgentPath, atomically: true, encoding: String.Encoding.utf8)
                launchAtStartupMenuItem.state = .on
            } catch {
                // Silently fail
            }
        }
    }
    
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Mouse Smoothly Help"
        alert.informativeText = """
        Smooth scrolling for standard mice.
        
        SETTINGS:
        • Speed: How fast the page scrolls
        • Friction: Lower = more glide/inertia
        • Accel: How much faster wheel spins speed up
        • Natural Scroll: Invert scroll direction

        MOUSE BUTTONS:
        • Map extra mouse buttons (thumb buttons) to
          Page Up / Page Down / Home / End.
        • Open "Mouse Buttons", press a button to see its
          number, then pick an action for it.

        ACCEL CURVES:
        • Linear: Constant response, predictable
        • Ease In: Slow start, speeds up (precise)
        • Ease Out: Fast start, slows down (snappy)
        • Ease In-Out: Smooth S-curve (balanced)
        • Exponential: Aggressive acceleration (power)
        
        Requires Accessibility permissions.
        Grant under: System Settings → Privacy & Security → Accessibility
        
        v1.0
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // Bring app to front for the alert
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    
    
    @objc private func toggleDebugWindow() {
        DebugWindow.instance?.toggle()
        debugWindowMenuItem.state = DebugWindow.instance?.isVisible == true ? .on : .off
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension MenuBarController {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === mouseButtonsMenu {
            buildButtonsMenu(menu)
        } else {
            refreshAppToggleMenuItem()
        }
    }
}
