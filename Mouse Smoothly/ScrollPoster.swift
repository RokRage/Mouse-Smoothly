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
    
    private var buffer = (x: 0.0, y: 0.0)   // raw accumulated target
    private var smooth = (x: 0.0, y: 0.0)   // intermediate stage (continuous position)
    private var current = (x: 0.0, y: 0.0)  // emitted position (continuous velocity)

    // `update()` runs on the event-tap (main) thread while `processing()` runs on the
    // CVDisplayLink thread; this guards the shared buffer/current state they both touch.
    private let stateLock = NSLock()

    // Sub-pixel remainder so fractional motion isn't lost to integer rounding
    private var pixelRemainder = (x: 0.0, y: 0.0)

    // Wall-clock time of the previous frame, for frame-rate-independent smoothing
    private var lastFrameTime: CFTimeInterval = 0
    
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
    // Low-pass-filtered inter-event interval used to drive acceleration smoothly.
    private var smoothedInterval: CFTimeInterval = 0
    
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
        let rawInterval = lastEventTime > 0 ? now - lastEventTime : 1.0
        lastEventTime = now

        // Wheel notches don't arrive at even intervals, so the raw gap is noisy.
        // After an idle gap, start a fresh estimate; otherwise low-pass filter it so
        // acceleration reflects sustained scroll speed rather than per-notch jitter.
        if rawInterval > 0.2 {
            smoothedInterval = rawInterval
        } else {
            smoothedInterval = smoothedInterval * 0.6 + rawInterval * 0.4
        }
        let timeSinceLast = smoothedInterval

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

        stateLock.lock()
        // Detect direction change - if scrolling in opposite direction, reset to prevent jerk
        let remainingY = buffer.y - current.y
        let remainingX = buffer.x - current.x

        // If new scroll is in opposite direction to remaining scroll, reset
        if (dy * remainingY < 0) || (dx * remainingX < 0) {
            // Direction changed - reset to current position
            buffer = current
            smooth = current
        }

        // Add to buffer. Rapid scrolls simply accumulate here; the cascaded smoothing
        // in processing() eases the output into the new target without a hard step.
        buffer.x += dx
        buffer.y += dy
        stateLock.unlock()

        startLoop()
    }
    
    // Inject a raw scroll distance (in pixels) directly into the smoothing buffer.
    // Used for synthetic scrolls like Page Up/Down so they glide through the same
    // easing pipeline as the mouse wheel instead of jumping.
    func scrollBy(x: Double, y: Double) {
        stateLock.lock()
        // Match update()'s direction-change reset so reversing mid-glide doesn't jerk.
        let remainingY = buffer.y - current.y
        let remainingX = buffer.x - current.x
        if (y * remainingY < 0) || (x * remainingX < 0) {
            buffer = current
            smooth = current
        }
        buffer.x += x
        buffer.y += y
        stateLock.unlock()

        startLoop()
    }

    func processing() {
        // Measure the actual time elapsed since the previous frame so smoothing
        // behaves identically on 60Hz, 120Hz ProMotion, or when frames are dropped.
        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime > 0 ? min(now - lastFrameTime, 0.1) : (1.0 / 60.0)
        lastFrameTime = now

        // Convert the per-frame `friction` (tuned at 60fps) into a time constant and
        // derive an exponentially-decaying interpolation factor for this frame's dt.
        // This factor trades responsiveness for smoothness across the two cascaded
        // stages below: lower = smoother/longer glide, higher = snappier.
        let clampedFriction = min(max(friction, 0.001), 0.999)
        let rate = -log(1.0 - clampedFriction) * 60.0 * 1.2
        let factor = 1.0 - exp(-rate * dt)

        stateLock.lock()
        // Stage 1: ease the intermediate position toward the raw target. This absorbs
        // bursty input so `smooth` is always a continuous curve, never a hard step.
        smooth.x = Interpolator.lerp(src: smooth.x, dest: buffer.x, trans: factor)
        smooth.y = Interpolator.lerp(src: smooth.y, dest: buffer.y, trans: factor)

        // Stage 2: ease the emitted position toward the intermediate one. Because
        // `smooth` is continuous, `current` ends up with continuous velocity too, so
        // even a large single scroll ramps in along an S-curve instead of jumping.
        let newX = Interpolator.lerp(src: current.x, dest: smooth.x, trans: factor)
        let newY = Interpolator.lerp(src: current.y, dest: smooth.y, trans: factor)

        let diffX = newX - current.x
        let diffY = newY - current.y

        current.x = newX
        current.y = newY

        // Check if stopped (relative to the true target)
        let distRemaining = abs(buffer.x - current.x) + abs(buffer.y - current.y)
        let settleX = buffer.x - current.x
        let settleY = buffer.y - current.y
        if distRemaining < stopThreshold {
            current = buffer
            smooth = buffer
        }
        stateLock.unlock()

        if distRemaining < stopThreshold {
            // Flush any final motion (including the tiny settle distance) then stop.
            postEvent(dx: settleX + diffX, dy: settleY + diffY)
            stopLoop()
            return
        }

        postEvent(dx: diffX, dy: diffY)
    }
    
    private func postEvent(dx: Double, dy: Double) {
        // Apply natural scroll inversion if enabled
        let finalDx = naturalScroll ? -dx : dx
        let finalDy = naturalScroll ? -dy : dy

        // Carry over the fractional part of the previous frame so sub-pixel motion
        // accumulates instead of being thrown away by integer rounding. This is what
        // keeps slow scrolling smooth rather than stepping in visible chunks.
        let rawX = finalDx + pixelRemainder.x
        let rawY = finalDy + pixelRemainder.y
        let postX = rawX.rounded(.toNearestOrEven)
        let postY = rawY.rounded(.toNearestOrEven)
        pixelRemainder.x = rawX - postX
        pixelRemainder.y = rawY - postY

        if postX == 0 && postY == 0 { return }

        // Create scroll event in PIXEL units for fine-grained, smooth movement.
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32(postY),
                                  wheel2: Int32(postX),
                                  wheel3: 0) else {
            return
        }

        // Set pixel deltas explicitly for apps that read them directly.
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: postY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: postX)

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

        // Reset timing/remainder so the next scroll burst starts cleanly.
        lastFrameTime = 0
        pixelRemainder = (x: 0.0, y: 0.0)
        stateLock.lock()
        smooth = current
        stateLock.unlock()

        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }
}

