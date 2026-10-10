import AppKit
@main struct OpacityPointerTests {
    @MainActor static func main() {
        var count = 0
        func check(_ value: Bool) { precondition(value); count += 1 }
        var range = OpacityRange(minimum: 15, maximum: 85)
        check(range.opacity(shift: true, active: true, normal: 50) == 0.85)
        check(range.opacity(shift: true, active: false, normal: 50) == 0.15)
        check(range.opacity(shift: false, active: true, normal: 50) == 0.5)
        check(range.opacity(shift: false, active: false, normal: 50) == 0)
        range.setMinimum(95); check(range.minimum == 95 && range.maximum == 95)
        range.setMaximum(40); check(range.minimum == 40 && range.maximum == 40)
        range.setMinimum(-4); range.setMaximum(120); check(range == OpacityRange(minimum: 0, maximum: 100))
        check(OpacityRange.clamp(.nan) == 0)
        let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 280, y: 170), mouseButton: .left)!
        event.setIntegerValueField(.mouseEventClickState, value: 2)
        let copy = event.copy()!
        PointerRouter.address(copy, pid: 1234, windowID: 5678)
        check(copy.location == event.location && copy.type == .leftMouseDown)
        check(copy.getIntegerValueField(.eventTargetUnixProcessID) == 1234)
        check(copy.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 5678)
        check(copy.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == 5678)
        check(copy.getIntegerValueField(.mouseEventClickState) == 2)
        let targetWindow: CGWindowID = 8765
        let originalNS = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 20), modifierFlags: [.shift], timestamp: 1, windowNumber: 2222, context: nil, eventNumber: 456, clickCount: 2, pressure: 0.5)!
        let routed = PointerEventFactory.make(originalNS, point: CGPoint(x: -250, y: 500), windowID: targetWindow, bounds: CGRect(x: -300, y: 0, width: 600, height: 600))!
        check(NSEvent(cgEvent: routed)!.windowNumber == Int(targetWindow))
        check(routed.location == CGPoint(x: -250, y: 500) && routed.type == .leftMouseDown)
        check(routed.flags.contains(.maskShift) && routed.getIntegerValueField(.mouseEventClickState) == 2)
        check(routed.getIntegerValueField(.mouseEventNumber) == 456)
        // CGEvent.type alone is insufficient: NSEvent also carries the native type.
        let nativeType = CGEventField(rawValue: 55)!
        check(routed.getIntegerValueField(nativeType) == originalNS.cgEvent!.getIntegerValueField(nativeType))
        check(routed.getIntegerValueField(.mouseEventSubtype) == 3)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp] {
            let input = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 2222, context: nil, eventNumber: 457, clickCount: 1, pressure: 0.5)!
            let output = PointerEventFactory.make(input, point: CGPoint(x: -250, y: 500), windowID: targetWindow, bounds: CGRect(x: -300, y: 0, width: 600, height: 600))!
            check(output.getIntegerValueField(nativeType) == input.cgEvent!.getIntegerValueField(nativeType))
        }
        let backgroundClick = PointerEventFactory.make(originalNS, point: CGPoint(x: -250, y: 500), windowID: targetWindow, bounds: CGRect(x: -300, y: 0, width: 600, height: 600), background: true)!
        check(backgroundClick.flags.contains([.maskCommand, .maskShift]))
        check(backgroundClick.getIntegerValueField(.mouseEventClickState) == 2)
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -18, wheel2: 7, wheel3: 0)!
        wheel.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        wheel.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        wheel.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -18.75)
        let scroll = PointerEventFactory.make(NSEvent(cgEvent: wheel)!, point: CGPoint(x: 100, y: 200), windowID: targetWindow, bounds: CGRect(x: -300, y: 0, width: 600, height: 600))!
        let backgroundScroll = PointerEventFactory.make(NSEvent(cgEvent: wheel)!, point: CGPoint(x: 100, y: 200), windowID: targetWindow, bounds: CGRect(x: -300, y: 0, width: 600, height: 600), background: true)!
        check(!backgroundScroll.flags.contains(.maskCommand))
        check(NSEvent(cgEvent: scroll)!.windowNumber == Int(targetWindow) && scroll.type == .scrollWheel)
        check(scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == wheel.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        check(scroll.getIntegerValueField(.scrollWheelEventScrollPhase) == 2 && scroll.getIntegerValueField(.scrollWheelEventMomentumPhase) == 1)
        check(scroll.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -18.75)
        let window = CGRect(x: 0, y: 0, width: 500, height: 500)
        check(!PointerHitPolicy.accepts(role: "AXGroup", frame: window, point: CGPoint(x: 200, y: 200), window: window))
        check(!PointerHitPolicy.accepts(role: "AXButton", frame: window, point: CGPoint(x: 200, y: 200), window: window))
        check(PointerHitPolicy.accepts(role: "AXButton", frame: CGRect(x: 100, y: 100, width: 60, height: 30), point: CGPoint(x: 110, y: 110), window: window))
        check(!PointerHitPolicy.accepts(role: "AXButton", frame: CGRect(x: 100, y: 100, width: 60, height: 30), point: CGPoint(x: 200, y: 200), window: window))
        // Disabled routing never emits an error or an event, and cannot hit an unrelated app.
        let router = PointerRouter(); var failed = false; router.onFailure = { _ in failed = true }
        let nsEvent = NSEvent(cgEvent: event)!
        router.route(nsEvent, selection: WindowSelection(id: 5678, processID: 1234, bundleID: "test", appName: "test", title: "test"),
                     bounds: CGRect(x: 0, y: 0, width: 500, height: 500), allowed: false)
        check(!failed)
        router.cancel()
        var click = BackgroundClick(origin: .zero)
        check(click.finish(at: CGPoint(x: 2, y: 2)))
        var drag = BackgroundClick(origin: .zero)
        drag.update(CGPoint(x: 10, y: 0)); check(!drag.finish(at: .zero))
        var outside = BackgroundClick(origin: .zero)
        check(!outside.finish(at: CGPoint(x: 0, y: 6)))
        print("PASS: \(count) opacity bounds, activation and selected-target event addressing checks")
    }
}
