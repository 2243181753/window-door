import Foundation
@main struct ActivationPolicyTests {
    static func main() {
        var count = 0
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (false, false, false, false), (false, false, true, false),
            (false, true, false, true), (false, true, true, true),
            (true, false, false, false), (true, false, true, true),
            (true, true, false, false), (true, true, true, true)]
        for (mouse, face, hover, expected) in cases {
            precondition(ActivationPolicy.triggered(mouseEnabled: mouse, hovering: hover, faceEnabled: face) == expected)
            count += 1
        }
        let peace = SceneFacts(ready: true, moving: false, peace: true, frontFacing: true)
        var fresh = EnhancedGate()
        precondition(!fresh.manuallyPaused); count += 1
        fresh.update(ownerSafe: true, scene: peace, now: 1, gesturesEnabled: false)
        precondition(!fresh.manuallyPaused); count += 1
        fresh.update(ownerSafe: true, scene: peace, now: 2, gesturesEnabled: true)
        precondition(fresh.manuallyPaused); count += 1
        fresh.resetManualProtection()
        precondition(!fresh.manuallyPaused); count += 1
        var paused = EnhancedGate(manuallyPaused: true)
        paused.update(ownerSafe: true, scene: peace, now: 1, gesturesEnabled: false)
        precondition(!paused.manuallyPaused); count += 1
        print("PASS: \(count) mouse/face combinations, gesture opt-in and fresh manual-state checks")
    }
}
