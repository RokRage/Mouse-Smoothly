import Cocoa
import ApplicationServices

// MARK: - Interpolation
class Interpolator {
    // Linear Interpolation
    static func lerp(src: Double, dest: Double, trans: Double) -> Double {
        return src + (dest - src) * trans
    }
}

// MARK: - Event Tap Interceptor
class Interceptor {
    private var eventTapRef: CFMachPort?
    private var runLoopSourceRef: CFRunLoopSource?
    
    enum InterceptorError: Error {
        case eventTapCreationFailed
        case eventTapEnableFailed
    }
    
    init(event mask: CGEventMask,
         listenOn location: CGEventTapLocation = .cgAnnotatedSessionEventTap,
         placeAt placement: CGEventTapPlacement = .tailAppendEventTap,
         options: CGEventTapOptions = .defaultTap,
         callback: @escaping CGEventTapCallBack) throws {
        
        guard let tap = CGEvent.tapCreate(tap: location,
                                          place: placement,
                                          options: options,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: nil) else {
            throw InterceptorError.eventTapCreationFailed
        }
        
        self.eventTapRef = tap
        self.runLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        try start()
    }
    
    deinit {
        stop()
    }
    
    func start() throws {
        guard let tap = eventTapRef, let source = runLoopSourceRef else {
            throw InterceptorError.eventTapEnableFailed
        }
        
        if !CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    func stop() {
        if let tap = eventTapRef {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSourceRef {
            if CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
    
    func isEnabled() -> Bool {
        guard let tap = eventTapRef else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
}

// MARK: - Accessibility Permissions
class AccessibilityPermission {
    private static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    
    @discardableResult
    static func ensureAuthorized() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if !trusted {
            DispatchQueue.main.async {
                presentInstructions()
            }
        }
        
        return trusted
    }
    
    private static func presentInstructions() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
        Mouse Smoothly must be enabled under Privacy & Security → Accessibility before it can smooth scroll events.
        
        1. Click “Open Settings” below (or open System Settings manually).
        2. In Accessibility, unlock the panel and add/enable Mouse Smoothly.
        3. Quit and relaunch the app.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSettings()
        }
        NSApp.terminate(nil)
    }
    
    private static func openSettings() {
        guard let url = privacyURL else { return }
        NSWorkspace.shared.open(url)
    }
}
