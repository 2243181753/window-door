import Foundation

// Runtime demand is separate from saved settings: closing the portal does not turn off its guard.
enum ResourcePolicy {
    static func needsCamera(guardEnabled: Bool, portalRunning: Bool, previewing: Bool) -> Bool {
        previewing || (guardEnabled && portalRunning)
    }
    static func renderFrame(visible: Bool, sameStream: Bool, elapsed: Double) -> Bool {
        visible || !sameStream || elapsed >= 0.2
    }
}
