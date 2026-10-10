import Foundation

// Never prolong unsafe display. Only reopening waits for a brief continuous safe interval.
struct RevealStability {
    static let confirmation: TimeInterval = 0.25
    private var safeSince: TimeInterval?
    private var lastSample: TimeInterval?
    private(set) var confirmed = false
    mutating func reset() { safeSince = nil; lastSample = nil; confirmed = false }
    mutating func observe(safe: Bool, time: TimeInterval) {
        guard safe, time.isFinite else { reset(); return }
        if let lastSample, time < lastSample || time - lastSample > GuardianPolicy.freshness { reset() }
        if safeSince == nil { safeSince = time }
        lastSample = time
        confirmed = time - safeSince! >= Self.confirmation
    }
}
