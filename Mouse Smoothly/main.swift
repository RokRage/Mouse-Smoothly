import Cocoa

// Redirect stdout and stderr to /dev/null to prevent task port errors
// This is necessary for menu bar accessory apps
let devNull = freopen("/dev/null", "w", stdout)
freopen("/dev/null", "w", stderr)

// Create the application
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menu bar only, no dock icon

// Initialize debug window (but don't show it - use menu to toggle)
let debugWindow = DebugWindow.show()
debugWindow.window?.orderOut(nil)  // Hide it initially
debugWindow.log("App launched")

// Create the menu bar controller (holds reference to status item)
let menuBarController = MenuBarController()

// Start the scroll manager
ScrollManager.shared.start()

// Run the application
app.run()
