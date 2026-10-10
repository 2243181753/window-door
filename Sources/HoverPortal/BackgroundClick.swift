import Foundation

// A semantic press is committed on release. Moving away never becomes a click when the pointer returns.
struct BackgroundClick {
    let origin: CGPoint
    private(set) var cancelled = false
    mutating func update(_ point: CGPoint) {
        if hypot(point.x - origin.x, point.y - origin.y) > 5 { cancelled = true }
    }
    mutating func finish(at point: CGPoint) -> Bool { update(point); return !cancelled }
}
