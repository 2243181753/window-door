import Foundation
@main struct ResourcePolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool) { precondition(value); checks += 1 }
        check(!ResourcePolicy.needsCamera(guardEnabled: true, portalRunning: false, previewing: false))
        check(ResourcePolicy.needsCamera(guardEnabled: true, portalRunning: true, previewing: false))
        check(!ResourcePolicy.needsCamera(guardEnabled: false, portalRunning: true, previewing: false))
        check(ResourcePolicy.needsCamera(guardEnabled: false, portalRunning: false, previewing: true))
        check(ResourcePolicy.needsCamera(guardEnabled: true, portalRunning: false, previewing: true))
        check(ResourcePolicy.renderFrame(visible: false, sameStream: false, elapsed: 0))
        check(!ResourcePolicy.renderFrame(visible: false, sameStream: true, elapsed: 0.1))
        check(ResourcePolicy.renderFrame(visible: false, sameStream: true, elapsed: 0.2))
        check(ResourcePolicy.renderFrame(visible: true, sameStream: true, elapsed: 0))
        var gate = EnhancedGate(manuallyPaused: true)
        gate.invalidateFrame()
        check(gate.manuallyPaused && !gate.allowsReveal)
        print("PASS: \(checks) camera demand, hidden-frame budget and retained protection checks")
    }
}
