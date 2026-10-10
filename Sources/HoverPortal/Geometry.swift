import AppKit

enum PortalGeometry {
    // Quartz uses a top-left origin relative to the primary display; AppKit uses bottom-left.
    static func quartzRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    static let defaultSize = CGSize(width: 180, height: 90)
    static let minimumSize = CGSize(width: 60, height: 30)

    static func corner(at point: CGPoint, in frame: CGRect, margin: CGFloat = 10) -> PortalCorner? {
        guard frame.contains(point) else { return nil }
        let left = point.x <= frame.minX + margin
        let right = point.x >= frame.maxX - margin
        let bottom = point.y <= frame.minY + margin
        let top = point.y >= frame.maxY - margin
        if top && left { return .topLeft }
        if top && right { return .topRight }
        if bottom && left { return .bottomLeft }
        if bottom && right { return .bottomRight }
        return nil
    }

    // Keep the diagonally opposite corner fixed, including when the pointer crosses it.
    static func manipulatedFrame(start: CGRect, delta: CGPoint, corner: PortalCorner?) -> CGRect {
        guard let corner else { return start.offsetBy(dx: delta.x, dy: delta.y) }
        let left = corner == .topLeft || corner == .bottomLeft
        let bottom = corner == .bottomLeft || corner == .bottomRight
        let width = max(minimumSize.width, start.width + (left ? -delta.x : delta.x))
        let height = max(minimumSize.height, start.height + (bottom ? -delta.y : delta.y))
        return CGRect(x: left ? start.maxX - width : start.minX,
                      y: bottom ? start.maxY - height : start.minY,
                      width: width, height: height)
    }
    // Return normalized coordinates in the captured window, with a top-left origin.
    static func crop(portal: CGRect, source: CGRect) -> CGRect? {
        let overlap = portal.intersection(source)
        guard !overlap.isNull, !overlap.isEmpty, source.width > 0, source.height > 0 else { return nil }
        return CGRect(x: (overlap.minX - source.minX) / source.width,
                      y: (overlap.minY - source.minY) / source.height,
                      width: overlap.width / source.width, height: overlap.height / source.height)
    }
    static func interceptsMouse(option: Bool, manipulating: Bool) -> Bool {
        // Only manual Option editing receives mouse events; ordinary pointer input passes through.
        option || manipulating
    }
    static func shortcutScope(enabled: Bool, hovering: Bool, hasFrame: Bool, settingsShown: Bool) -> Bool {
        enabled && hovering && hasFrame && !settingsShown
    }
    static func opacity(_ value: Double) -> CGFloat {
        CGFloat(value.isFinite ? min(1, max(0, value)) : 1)
    }
    static func reveals(enabled: Bool, hovering: Bool, dragging: Bool, hasFrame: Bool) -> Bool {
        enabled && (hovering || dragging) && hasFrame
    }
}

enum PortalCorner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

struct SelectionSizing {
    private(set) var pending = false
    mutating func beginSelection() { pending = true }
    mutating func cancel() { pending = false }
    mutating func takeSize(_ size: CGSize) -> CGSize? {
        guard pending, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        pending = false
        return size
    }
}

struct SourcePositionFollower {
    private var lastOrigin: CGPoint?
    mutating func reset(to origin: CGPoint? = nil) { lastOrigin = origin }
    mutating func translation(to origin: CGPoint, enabled: Bool, manipulating: Bool) -> CGPoint? {
        guard origin.x.isFinite, origin.y.isFinite, !manipulating else { return nil }
        let previous = lastOrigin
        lastOrigin = origin
        guard enabled, let previous else { return nil }
        // Quartz top-left y increases downwards; AppKit y increases upwards.
        return CGPoint(x: origin.x - previous.x, y: previous.y - origin.y)
    }
}
