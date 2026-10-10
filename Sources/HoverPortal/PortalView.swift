import AppKit

final class PortalPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PortalView: NSView {
    var frameImage: CapturedFrame?
    var sourceBounds = CGRect.zero
    var reveal = false
    var showOutline = true
    var contentOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    var onPointerEvent: ((NSEvent) -> Void)?
    var onUserManipulation: (() -> Void)?
    var editGestureActive: (() -> Bool)?
    var targetMoveActive: (() -> Bool)?
    var onTargetMoveBegin: (() -> Bool)?
    var onTargetMove: ((CGPoint) -> Void)?
    var onTargetMoveEnd: (() -> Void)?
    private(set) var isMovingTarget = false
    private var targetMoveMouse = CGPoint.zero
    var allowsManipulation = false
    var editing = false { didSet { if oldValue != editing { needsDisplay = true } } }
    private(set) var isManipulating = false
    private var corner: PortalCorner?
    private var startMouse = CGPoint.zero
    private var startFrame = CGRect.zero
    private var ownsCursor = false
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        if reveal, let frameImage, let window {
            let h = NSScreen.screens.first?.frame.height ?? 0
            let portal = PortalGeometry.quartzRect(window.frame, primaryHeight: h)
            if let normalized = PortalGeometry.crop(portal: portal, source: sourceBounds) {
                let content = frameImage.contentRect
                let pixels = CGRect(x: content.minX + normalized.minX * content.width,
                                    y: content.minY + normalized.minY * content.height,
                                    width: normalized.width * content.width,
                                    height: normalized.height * content.height)
                if let crop = frameImage.image.cropping(to: pixels) {
                    let overlap = portal.intersection(sourceBounds)
                    let dest = CGRect(x: overlap.minX - portal.minX, y: portal.maxY - overlap.maxY,
                                      width: overlap.width, height: overlap.height)
                    NSGraphicsContext.current?.imageInterpolation = .none
                    NSImage(cgImage: crop, size: dest.size).draw(in: dest, from: .zero, operation: .sourceOver, fraction: contentOpacity)
                }
            }
        }
        if showOutline || editing {
            (editing ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
            let width: CGFloat = 1 / (window?.backingScaleFactor ?? 2)
            let border = NSBezierPath(rect: bounds.insetBy(dx: width / 2, dy: width / 2))
            border.lineWidth = width; border.stroke()
        }
        if editing {
            NSColor.controlAccentColor.setFill()
            for x in [bounds.minX + 1, bounds.maxX - 7] {
                for y in [bounds.minY + 1, bounds.maxY - 7] {
                    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: 6, height: 6), xRadius: 1, yRadius: 1).fill()
                }
            }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Consume pointer actions locally. This nonactivating panel never focuses the window underneath.
    override func rightMouseDown(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func rightMouseUp(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func rightMouseDragged(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func otherMouseDown(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func otherMouseUp(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func otherMouseDragged(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func scrollWheel(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) { if !editing { onPointerEvent?(event) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        if targetMoveActive?() == true {
            if onTargetMoveBegin?() == true {
                targetMoveMouse = NSEvent.mouseLocation; isMovingTarget = true
                NSCursor.closedHand.set()
            }
            return
        }
        guard allowsManipulation, (editGestureActive?() ?? false), let window else {
            onPointerEvent?(event); return
        }
        onUserManipulation?()
        startMouse = NSEvent.mouseLocation; startFrame = window.frame
        corner = PortalGeometry.corner(at: startMouse, in: startFrame)
        isManipulating = true
        updateCursor(mouse: startMouse, option: true)
    }
    override func mouseDragged(with event: NSEvent) {
        if isMovingTarget {
            guard targetMoveActive?() == true else { endTargetMove(); return }
            let mouse = NSEvent.mouseLocation
            onTargetMove?(CGPoint(x: mouse.x - targetMoveMouse.x, y: mouse.y - targetMoveMouse.y))
            return
        }
        guard allowsManipulation, isManipulating, let window else { onPointerEvent?(event); return }
        guard (editGestureActive?() ?? false) else { endManipulation(); return }
        let mouse = NSEvent.mouseLocation
        let delta = CGPoint(x: mouse.x - startMouse.x, y: mouse.y - startMouse.y)
        let next = PortalGeometry.manipulatedFrame(start: startFrame, delta: delta, corner: corner)
        window.setFrame(next, display: true)
        needsDisplay = true
        updateCursor(mouse: mouse, option: true)
    }
    override func mouseUp(with event: NSEvent) {
        if isMovingTarget { endTargetMove(); return }
        if isManipulating { endManipulation() } else { onPointerEvent?(event) }
    }
    func endTargetMove() {
        guard isMovingTarget else { return }
        isMovingTarget = false; onTargetMoveEnd?(); NSCursor.arrow.set()
    }
    func endManipulation() {
        isManipulating = false; corner = nil
        updateCursor(mouse: NSEvent.mouseLocation, option: (editGestureActive?() ?? false))
    }

    func updateCursor(mouse: CGPoint, option: Bool) {
        guard allowsManipulation, let window, option, isManipulating || window.frame.contains(mouse) else {
            if ownsCursor { NSCursor.arrow.set(); ownsCursor = false }
            return
        }
        ownsCursor = true
        if let corner = isManipulating ? corner : PortalGeometry.corner(at: mouse, in: window.frame) {
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch corner {
                case .topLeft: position = .topLeft
                case .topRight: position = .topRight
                case .bottomLeft: position = .bottomLeft
                case .bottomRight: position = .bottomRight
                }
                NSCursor.frameResize(position: position, directions: [.inward, .outward]).set()
            } else { NSCursor.crosshair.set() }
        } else { (isManipulating ? NSCursor.closedHand : NSCursor.openHand).set() }
    }
}
