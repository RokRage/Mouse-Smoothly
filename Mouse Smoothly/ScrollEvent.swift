import Cocoa

struct AxisData {
    var valid = false
    var value = 0.0
}

class ScrollEvent {
    let event: CGEvent
    var y: AxisData
    var x: AxisData
    
    init(with cgEvent: CGEvent) {
        self.event = cgEvent
        self.y = ScrollEvent.getAxisData(event: cgEvent, axis: .Y)
        self.x = ScrollEvent.getAxisData(event: cgEvent, axis: .X)
    }
    
    enum AxisType { case X, Y }
    
    static func getAxisData(event: CGEvent, axis: AxisType) -> AxisData {
        var data = AxisData()
        let pixelField: CGEventField = (axis == .Y) ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
        let fixedField: CGEventField = (axis == .Y) ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        let intField: CGEventField = (axis == .Y) ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        
        let pixelVal = event.getDoubleValueField(pixelField)
        let fixedVal = event.getDoubleValueField(fixedField)
        let intVal = event.getIntegerValueField(intField)
        
        if pixelVal != 0 {
            data.valid = true
            data.value = pixelVal
        } else if fixedVal != 0 {
            data.valid = true
            data.value = fixedVal
        } else if intVal != 0 {
            data.valid = true
            data.value = Double(intVal)
        }
        return data
    }
    
    // Simplified trackpad detection
    func isTrackpad() -> Bool {
        // Mos logic: check phase. If non-zero, it's likely a trackpad or magic mouse doing smooth scrolling naturally.
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        // If system is sending phase info, it handles the smoothness (Native scroll)
        if phase != 0 || momPhase != 0 {
            return true
        }
        return false
    }
}
