import AppKit

final class InputView: NSView {
    var points: [NSPoint] = []
    var types: [NSEvent.EventType] = []
    var scroll: NSPoint = .zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func mouseDown(with event: NSEvent) { points.append(event.locationInWindow); types.append(event.type) }
    override func mouseDragged(with event: NSEvent) { points.append(event.locationInWindow); types.append(event.type) }
    override func mouseUp(with event: NSEvent) { points.append(event.locationInWindow); types.append(event.type) }
    override func scrollWheel(with event: NSEvent) { types.append(event.type); scroll = NSPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY) }
}

@main struct PointerWindowTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let view = InputView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = view
        window.orderFront(nil)
        let h = NSScreen.screens.first!.frame.height
        func deliver(_ type: NSEvent.EventType, at point: NSPoint) {
            let input = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1, windowNumber: 7777, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let global = window.convertPoint(toScreen: point)
            let cg = PointerEventFactory.make(input, point: CGPoint(x: global.x, y: h - global.y), windowID: CGWindowID(window.windowNumber), bounds: CGRect(x: window.frame.minX, y: h - window.frame.maxY, width: window.frame.width, height: window.frame.height), background: true)!
            let incoming = NSEvent(cgEvent: cg)!
            app.sendEvent(incoming)
        }
        // The target is inactive and explicitly refuses first mouse. One down/up
        // must reach it without making the application active or posting two clicks.
        precondition(!app.isActive && !window.isKeyWindow)
        deliver(.leftMouseDown, at: NSPoint(x: 25, y: 40))
        deliver(.leftMouseDragged, at: NSPoint(x: 175, y: 90))
        deliver(.leftMouseUp, at: NSPoint(x: 175, y: 90))
        precondition(view.types == [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        precondition(view.points == [NSPoint(x: 25, y: 40), NSPoint(x: 175, y: 90), NSPoint(x: 175, y: 90)])
        precondition(!app.isActive)
        view.types.removeAll(); view.points.removeAll()
        deliver(.leftMouseDown, at: NSPoint(x: 90, y: 60))
        deliver(.leftMouseUp, at: NSPoint(x: 90, y: 60))
        precondition(view.types == [.leftMouseDown, .leftMouseUp])
        precondition(view.points == [NSPoint(x: 90, y: 60), NSPoint(x: 90, y: 60)])
        precondition(!app.isActive)
        let original = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -24, wheel2: 9, wheel3: 0)!
        let cg = PointerEventFactory.make(NSEvent(cgEvent: original)!, point: CGPoint(x: window.frame.midX, y: h - window.frame.midY), windowID: CGWindowID(window.windowNumber), bounds: CGRect(x: window.frame.minX, y: h - window.frame.maxY, width: window.frame.width, height: window.frame.height), background: true)!
        app.sendEvent(NSEvent(cgEvent: cg)!)
        precondition(view.types.last == .scrollWheel && view.scroll == NSPoint(x: 9, y: -24))
        window.orderOut(nil)
        print("PASS: inactive first-mouse-refusing window receives exactly one down/up, distinct drag coordinates and two-axis scrolling without application activation")
    }
}
