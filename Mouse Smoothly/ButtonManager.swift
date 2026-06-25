import Cocoa

// Actions that an extra mouse button can be mapped to.
enum ButtonAction: Int, CaseIterable {
    case none = 0
    case pageUp = 1
    case pageDown = 2
    case home = 3
    case end = 4

    var name: String {
        switch self {
        case .none:     return "Default (no remap)"
        case .pageUp:   return "Page Up"
        case .pageDown: return "Page Down"
        case .home:     return "Home"
        case .end:      return "End"
        }
    }

    // macOS virtual key codes (see Carbon HIToolbox Events.h).
    var keyCode: CGKeyCode? {
        switch self {
        case .none:     return nil
        case .pageUp:   return 0x74  // kVK_PageUp
        case .pageDown: return 0x79  // kVK_PageDown
        case .home:     return 0x73  // kVK_Home
        case .end:      return 0x77  // kVK_End
        }
    }
}

// Intercepts "other" mouse buttons (button numbers 3+) and lets the user remap
// them to keyboard actions like Page Up / Page Down.
class ButtonManager {
    static let shared = ButtonManager()

    // Buttons we expose in the UI. Button numbers 0/1/2 are left/right/middle and
    // are intentionally left alone; the thumb/extra buttons are usually 3 and up.
    static let mappableButtons: [Int64] = [3, 4, 5, 6]

    private var interceptor: Interceptor?
    private let defaultsKey = "MouseSmoothly.buttonMappings"

    // buttonNumber -> ButtonAction
    private var mappings: [Int64: ButtonAction] = [:]

    // Last button number we saw, so the UI can help the user identify which
    // physical button is which.
    private(set) var lastButtonPressed: Int64?

    private init() {
        loadMappings()
    }

    // MARK: - Persistence

    private func loadMappings() {
        guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] else { return }
        for (key, raw) in stored {
            if let button = Int64(key), let action = ButtonAction(rawValue: raw) {
                mappings[button] = action
            }
        }
    }

    private func persistMappings() {
        var out: [String: Int] = [:]
        for (button, action) in mappings where action != .none {
            out[String(button)] = action.rawValue
        }
        UserDefaults.standard.set(out, forKey: defaultsKey)
    }

    // MARK: - Public API

    func action(for button: Int64) -> ButtonAction {
        mappings[button] ?? .none
    }

    func setAction(_ action: ButtonAction, for button: Int64) {
        if action == .none {
            mappings.removeValue(forKey: button)
        } else {
            mappings[button] = action
        }
        persistMappings()
    }

    private func mappedAction(for button: Int64) -> ButtonAction? {
        guard let action = mappings[button], action != .none else { return nil }
        return action
    }

    // MARK: - Event tap

    func start() {
        if interceptor != nil { return }
        guard AccessibilityPermission.ensureAuthorized() else {
            DebugWindow.instance?.log("ButtonManager: accessibility permission missing")
            return
        }

        let callback: CGEventTapCallBack = { (_, type, event, _) in
            let button = event.getIntegerValueField(.mouseEventButtonNumber)

            if type == .otherMouseDown {
                ButtonManager.shared.lastButtonPressed = button
                DebugWindow.instance?.log("🖱️ Mouse button \(button) pressed")
            }

            // Only remap the buttons the user has configured; everything else
            // passes through untouched.
            guard let action = ButtonManager.shared.mappedAction(for: button) else {
                return Unmanaged.passUnretained(event)
            }

            // Fire on button-down; suppress both down and up so the app never
            // sees the raw button event.
            if type == .otherMouseDown {
                ButtonManager.shared.perform(action)
            }
            return nil
        }

        let mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue)
        do {
            interceptor = try Interceptor(event: CGEventMask(mask),
                                          listenOn: .cgSessionEventTap,
                                          callback: callback)
            DebugWindow.instance?.log("✅ ButtonManager interceptor created")
        } catch {
            DebugWindow.instance?.log("❌ ButtonManager failed to create interceptor: \(error)")
        }
    }

    func stop() {
        interceptor?.stop()
        interceptor = nil
    }

    private func perform(_ action: ButtonAction) {
        switch action {
        case .pageUp:
            ScrollPoster.shared.scrollBy(x: 0, y: pageScrollAmount())
        case .pageDown:
            ScrollPoster.shared.scrollBy(x: 0, y: -pageScrollAmount())
        case .home, .end:
            // Absolute jumps can't be expressed as a relative glide, so send the key.
            postKey(for: action)
        case .none:
            break
        }
    }

    // One "page" worth of scroll, in pixels. The scrollable viewport is smaller
    // than the screen (menu bar, title bar, toolbars), so we base the page on the
    // focused window's height and overlap slightly to keep context between pages.
    // Falls back to a reduced screen height if the window size isn't available.
    private func pageScrollAmount() -> Double {
        let overlap = 0.9  // keep ~10% of the previous view visible
        if let windowHeight = focusedWindowHeight() {
            return windowHeight * overlap
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return Double(screen?.frame.height ?? 800) * 0.8
    }

    // Height of the frontmost app's focused window, via the Accessibility API.
    private func focusedWindowHeight() -> Double? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }

        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return size.height > 0 ? Double(size.height) : nil
    }

    private func postKey(for action: ButtonAction) {
        guard let keyCode = action.keyCode else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }
}
