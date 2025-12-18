import Cocoa

class DebugWindow: NSWindowController {
    private var textView: NSTextView!
    private static var shared: DebugWindow?
    var isEnabled = false  // Controls whether logging actually happens
    
    static var instance: DebugWindow? {
        return shared
    }
    
    static func show() -> DebugWindow {
        if shared == nil {
            shared = DebugWindow()
        }
        shared?.showWindow(nil)
        shared?.isEnabled = true
        return shared!
    }
    
    func toggle() {
        if window?.isVisible == true {
            window?.orderOut(nil)
            isEnabled = false
        } else {
            showWindow(nil)
            isEnabled = true
        }
    }
    
    var isVisible: Bool {
        return window?.isVisible ?? false
    }
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mouse Smoothly Debug"
        window.level = .floating
        
        super.init(window: window)
        
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        
        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        window.contentView = scrollView
        
        log("=== Mouse Smoothly Debug Window ===")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func log(_ message: String) {
        guard isEnabled else { return }  // Don't log if disabled
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        
        DispatchQueue.main.async {
            self.textView.string += line
            self.textView.scrollToEndOfDocument(nil)
        }
    }
}
