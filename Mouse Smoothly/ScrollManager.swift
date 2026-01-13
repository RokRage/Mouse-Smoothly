import Cocoa

class ScrollManager {
    static let shared = ScrollManager()
    
    private var interceptor: Interceptor?
    private let magicNumber: Int64 = 42
    private let bypassModifier: CGEventFlags = .maskAlternate  // Hold Option to bypass smoothing
    private var excludedBundleIDs: Set<String> = []
    private let excludedDefaultsKey = "MouseSmoothly.excludedBundleIDs"
    
    init() {
        loadExcludedBundleIDs()
    }
    
    private func loadExcludedBundleIDs() {
        if let stored = UserDefaults.standard.array(forKey: excludedDefaultsKey) as? [String] {
            excludedBundleIDs = Set(stored)
        }
    }
    
    private func persistExcluded() {
        UserDefaults.standard.set(Array(excludedBundleIDs), forKey: excludedDefaultsKey)
    }
    
    private func isFrontmostExcluded() -> Bool {
        guard !excludedBundleIDs.isEmpty else { return false }
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        if excludedBundleIDs.contains(bundleID) {
            DebugWindow.instance?.log("Excluded app detected (\(bundleID)), passing scroll through")
            return true
        }
        return false
    }
    
    func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }
    
    func toggleExclusion(bundleID: String) -> Bool {
        if excludedBundleIDs.contains(bundleID) {
            excludedBundleIDs.remove(bundleID)
        } else {
            excludedBundleIDs.insert(bundleID)
        }
        persistExcluded()
        return excludedBundleIDs.contains(bundleID)
    }
    
    func start() {
        DebugWindow.instance?.log("start() called")
        
        // Don't re-create if already running
        if interceptor != nil {
            DebugWindow.instance?.log("Already running, skipping")
            return
        }
        
        guard AccessibilityPermission.ensureAuthorized() else {
            DebugWindow.instance?.log("Accessibility permission missing")
            return
        }
        
        DebugWindow.instance?.log("Creating event tap...")
        
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
            // Check if it's our own event
            if event.getIntegerValueField(.eventSourceUserData) == 42 {
                return Unmanaged.passUnretained(event)
            }
            
            // CRITICAL: Check trackpad FIRST before any logging or processing
            // This prevents jitter by passing trackpad events through immediately
            let scrollEvent = ScrollEvent(with: event)
            if scrollEvent.isTrackpad() {
                return Unmanaged.passUnretained(event)
            }
            
            // Log that we received a mouse scroll event
            DebugWindow.instance?.log("📥 Mouse scroll event received")
            
            if ScrollManager.shared.isFrontmostExcluded() {
                return Unmanaged.passUnretained(event)
            }
            
            // If the bypass modifier is held, let the native scroll through untouched
            if event.flags.contains(ScrollManager.shared.bypassModifier) {
                DebugWindow.instance?.log("Bypass modifier held, passing scroll through")
                return Unmanaged.passUnretained(event)
            }
            
            // It's a chunky mouse wheel event - process it!
            DebugWindow.instance?.log("🖱️ Processing mouse scroll")
            // Feed to poster
            ScrollPoster.shared.update(event: event, proxy: proxy)
            
            // Suppress original event
            return nil
        }
        
        do {
            interceptor = try Interceptor(event: (1 << CGEventType.scrollWheel.rawValue),
                                          listenOn: .cgSessionEventTap,
                                          callback: callback)
            DebugWindow.instance?.log("✅ Interceptor created successfully")
            DebugWindow.instance?.log("Now intercepting scroll events")
        } catch {
            DebugWindow.instance?.log("❌ Failed to create interceptor: \(error)")
            
            // Show alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Unexpected Error"
                alert.informativeText = """
                Failed to create event tap even though permissions were granted.
                
                Error: \(error)
                
                Try restarting your Mac or contact support.
                """
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Quit")
                
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }
    
    func stop() {
        DebugWindow.instance?.log("stop() called")
        interceptor?.stop()
        interceptor = nil
        DebugWindow.instance?.log("Interceptor stopped")
    }
}
