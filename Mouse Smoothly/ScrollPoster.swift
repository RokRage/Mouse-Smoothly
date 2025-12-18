import Cocoa
import CoreVideo

// CVDisplayLink callback (must be at file scope)
private func displayLinkCallback(displayLink: CVDisplayLink,
                                 inNow: UnsafePointer<CVTimeStamp>,
                                 inOutputTime: UnsafePointer<CVTimeStamp>,
                                 flagsIn: CVOptionFlags,
                                 flagsOut: UnsafeMutablePointer<CVOptionFlags>,
                                 displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn {
    ScrollPoster.shared.processing()
    return kCVReturnSuccess
}

class ScrollPoster {
    static let shared = ScrollPoster()
    
    private var displayLink: CVDisplayLink?
    
    private var buffer = (x: 0.0, y: 0.0)
    private var current = (x: 0.0, y: 0.0)
    
    // Acceleration curve types
    enum AccelCurve: Int, CaseIterable {
        case linear = 0
        case easeIn = 1
        case easeOut = 2
        case easeInOut = 3
        case exponential = 4
        
        var name: String {
            switch self {
            case .linear: return "Linear"
            case .easeIn: return "Ease In"
            case .easeOut: return "Ease Out"
            case .easeInOut: return "Ease In-Out"
            case .exponential: return "Exponential"
            }
        }
        
        // Apply curve to time value (0-1 range, representing scroll velocity fraction)
        func apply(_ t: Double) -> Double {
            switch self {
            case .linear:
                return t
            case .easeIn:
                return t * t  // Quadratic ease in
            case .easeOut:
                return 1 - (1 - t) * (1 - t)  // Quadratic ease out
            case .easeInOut:
                return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            case .exponential:
                return t * t * t  // Cubic for more aggressive acceleration
            }
        }
    }
    
    // UserDefaults keys
    private let kSpeedMulti = "MouseSmoothly.speedMulti"
    private let kFriction = "MouseSmoothly.friction"
    private let kAccelFactor = "MouseSmoothly.accelFactor"
    private let kNaturalScroll = "MouseSmoothly.naturalScroll"
    private let kAccelCurve = "MouseSmoothly.accelCurve"
    
    // Config (adjustable at runtime, persisted)
    var speedMulti: Double = 80.0 {
        didSet { UserDefaults.standard.set(speedMulti, forKey: kSpeedMulti) }
    }
    var friction: Double = 0.08 {
        didSet { UserDefaults.standard.set(friction, forKey: kFriction) }
    }
    var accelFactor: Double = 1.0 {
        didSet { UserDefaults.standard.set(accelFactor, forKey: kAccelFactor) }
    }
    var naturalScroll: Bool = false {
        didSet { UserDefaults.standard.set(naturalScroll, forKey: kNaturalScroll) }
    }
    var accelCurve: AccelCurve = .linear {
        didSet { UserDefaults.standard.set(accelCurve.rawValue, forKey: kAccelCurve) }
    }
    private let stopThreshold: Double = 0.05 // Lower = longer coasting
    
    // State
    private var lastEventRef: CGEvent?
    private var lastEventTime: CFTimeInterval = 0
    
    // Config state
    private var isRunning = false
    
    init() {
        // Load saved settings
        let defaults = UserDefaults.standard
        if defaults.object(forKey: kSpeedMulti) != nil {
            speedMulti = defaults.double(forKey: kSpeedMulti)
        }
        if defaults.object(forKey: kFriction) != nil {
            friction = defaults.double(forKey: kFriction)
        }
        if defaults.object(forKey: kAccelFactor) != nil {
            accelFactor = defaults.double(forKey: kAccelFactor)
        }
        if defaults.object(forKey: kNaturalScroll) != nil {
            naturalScroll = defaults.bool(forKey: kNaturalScroll)
        }
        if defaults.object(forKey: kAccelCurve) != nil {
            if let curve = AccelCurve(rawValue: defaults.integer(forKey: kAccelCurve)) {
                accelCurve = curve
            }
        }
    }
    
    func update(event: CGEvent, proxy: CGEventTapProxy) {
        lastEventRef = event
        
        // Calculate acceleration based on event frequency
        let now = CFAbsoluteTimeGetCurrent()
        let timeSinceLast = lastEventTime > 0 ? now - lastEventTime : 1.0
        lastEventTime = now
        
        // Acceleration: the faster events come in, the higher the multiplier
        // timeSinceLast of ~0.016s (60fps) = fast scrolling
        // timeSinceLast of ~0.1s = slow scrolling
        // Normalize time to 0-1 range (0.1s = slow, 0.016s = fast)
        let normalizedSpeed = max(0, min(1, (0.1 - timeSinceLast) / 0.084))
        
        // Apply selected curve to the normalized speed
        let curvedSpeed = accelCurve.apply(normalizedSpeed)
        
        // Calculate multiplier based on curved speed and accel factor
        let accelMultiplier = 1.0 + (curvedSpeed * 1.5 * accelFactor)
        
        // Get scroll delta
        var dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        var dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        
        let isPixel = (dx != 0 || dy != 0)
        
        if !isPixel {
            // Fallback to line-based delta
            dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * speedMulti
            dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * speedMulti
        } else {
            // Apply speed multiplier to pixel deltas too
            dx *= (speedMulti / 80.0)  // Normalize since default is 80
            dy *= (speedMulti / 80.0)
        }
        
        // Apply acceleration
        dx *= accelMultiplier
        dy *= accelMultiplier
        
        // Detect direction change - if scrolling in opposite direction, reset to prevent jerk
        let remainingY = buffer.y - current.y
        let remainingX = buffer.x - current.x
        
        // If new scroll is in opposite direction to remaining scroll, reset
        if (dy * remainingY < 0) || (dx * remainingX < 0) {
            // Direction changed - reset to current position
            buffer = current
        }
        
        // Add to buffer
        buffer.x += dx
        buffer.y += dy
        
        startLoop()
    }
    
    func processing() {
        // Calculate next frame
        let newX = Interpolator.lerp(src: current.x, dest: buffer.x, trans: friction)
        let newY = Interpolator.lerp(src: current.y, dest: buffer.y, trans: friction)
        
        let diffX = newX - current.x
        let diffY = newY - current.y
        
        current.x = newX
        current.y = newY
        
        // Check if stopped
        let distRemaining = abs(buffer.x - current.x) + abs(buffer.y - current.y)
        if distRemaining < stopThreshold {
            stopLoop()
            // Reset to prevent drift
            current = buffer 
            return
        }
        
        // Post event
        if abs(diffX) > 0.01 || abs(diffY) > 0.01 {
            postEvent(dx: diffX, dy: diffY)
        }
    }
    
    private func postEvent(dx: Double, dy: Double) {
        // Apply natural scroll inversion if enabled
        let finalDx = naturalScroll ? -dx : dx
        let finalDy = naturalScroll ? -dy : dy
        
        // Create scroll event using LINE units (better app compatibility)
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .line,
                                  wheelCount: 2,
                                  wheel1: Int32(round(finalDy / 10)),
                                  wheel2: Int32(round(finalDx / 10)),
                                  wheel3: 0) else {
            return
        }
        
        // Set pixel deltas for smooth scrolling
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: finalDy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: finalDx)
        
        // Set fixed-point deltas
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: finalDy / 10)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: finalDx / 10)
        
        // Mark as our event so we don't re-intercept it
        event.setIntegerValueField(.eventSourceUserData, value: 42)
        
        // Post at HID level
        event.post(tap: .cghidEventTap)
    }
    
    private func startLoop() {
        if isRunning { return }
        isRunning = true
        
        // Create display link if needed
        if displayLink == nil {
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
            if let link = displayLink {
                CVDisplayLinkSetOutputCallback(link, displayLinkCallback, nil)
            }
        }
        
        // Start the display link (synced to vsync)
        if let link = displayLink, !CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStart(link)
        }
    }
    
    private func stopLoop() {
        if !isRunning { return }
        isRunning = false
        
        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }
}

