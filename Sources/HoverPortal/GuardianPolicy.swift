import Foundation

struct GuardianPolicy {
    static let freshness: TimeInterval = 0.35
    static func permits(enabled: Bool, enrolled: Bool, faceCount: Int, ownerMatches: Bool,
                        lastFrame: TimeInterval?, now: TimeInterval) -> Bool {
        if !enabled { return true }
        guard enrolled, faceCount == 1, ownerMatches, let lastFrame,
              now >= lastFrame, now - lastFrame <= freshness else { return false }
        return true
    }
}
