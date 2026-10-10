import Foundation

enum RecoveryDelay {
    static func clamp(_ seconds: Double) -> Double {
        seconds.isFinite ? min(60, max(0, seconds)) : 3
    }
}
