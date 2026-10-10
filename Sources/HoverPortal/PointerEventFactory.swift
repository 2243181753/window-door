import AppKit
import Darwin

@MainActor
enum PointerEventFactory {
    // macOS has no public setter for the event's destination-local coordinates.
    // Resolve the compatibility entry point at runtime; never send a malformed event.
    private typealias WindowLocationSetter = @convention(c) (CGEvent, CGPoint) -> Void
    private static let setWindowLocation: WindowLocationSetter? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else { return nil }
        return unsafeBitCast(symbol, to: WindowLocationSetter.self)
    }()
    static var available: Bool { setWindowLocation != nil }

    static func make(_ event: NSEvent, point: CGPoint, windowID: CGWindowID, bounds: CGRect, background: Bool = false) -> CGEvent? {
        // AppKit normally consumes a click on an inactive window for activation.
        // Command-click is its nonactivating dispatch path. Apply it to mouse buttons
        // only: adding Command to wheel events would change scrolling into zooming.
        let buttonEvent = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                           .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                           .otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(event.type)
        var modifiers = event.modifierFlags
        if background && buttonEvent { modifiers.insert(.command) }
        guard let setWindowLocation, let original = event.cgEvent,
              let native = NSEvent.mouseEvent(with: event.type == .scrollWheel ? .mouseMoved : event.type, location: CGPoint(x: point.x - bounds.minX, y: bounds.maxY - point.y),
                  modifierFlags: modifiers, timestamp: event.timestamp,
                  windowNumber: Int(windowID), context: nil, eventNumber: event.type == .scrollWheel ? 0 : event.eventNumber,
                  clickCount: event.type == .scrollWheel || event.type == .mouseMoved ? 0 : event.clickCount,
                  pressure: event.type == .scrollWheel ? 0 : event.pressure),
              let routed = native.cgEvent else { return nil }
        // Reconstruct the native event with the destination window number. A copy of the
        // overlay event retains the overlay's window number even after its location changes.
        routed.type = original.type; routed.location = point
        setWindowLocation(routed, CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
        routed.flags = original.flags
        if background && buttonEvent { routed.flags.insert(.maskCommand) }
        routed.timestamp = original.timestamp
        let integerFields: [CGEventField] = [.mouseEventButtonNumber, .mouseEventClickState,
            .mouseEventDeltaX, .mouseEventDeltaY,
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3,
            .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase,
            .scrollWheelEventMomentumPhase, .scrollWheelEventScrollCount]
        for field in integerFields { routed.setIntegerValueField(field, value: original.getIntegerValueField(field)) }
        for field in [CGEventField.mouseEventPressure, .scrollWheelEventFixedPtDeltaAxis1,
                      .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis3] {
            routed.setDoubleValueField(field, value: original.getDoubleValueField(field))
        }
        // Mark mouse input as explicitly addressed to a window, rather than a physical
        // cursor event that AppKit can consume to activate an inactive window.
        if event.type != .scrollWheel { routed.setIntegerValueField(.mouseEventSubtype, value: 3) }
        return routed
    }
}
