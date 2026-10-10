import Foundation
@main struct StatusIconTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool) { precondition(value); checks += 1 }
        let ready = GuardStatusSnapshot(enabled: true, enrolled: true, hasFrame: true, faceCount: 1,
            rawOwnerMatch: true, confirmedOwner: true, enhanced: true, frontFacing: true,
            sceneReady: true, automaticAllows: true)
        check(ready.reason == nil)
        var s = ready; s.previewing = true; check(s.reason == .learning)
        s = ready; s.previewing = true; s.cameraFault = true; check(s.reason == .cameraUnavailable)
        s = ready; s.enabled = false; s.cameraFault = true; check(s.reason == nil)
        s = ready; s.manualLock = true; s.faceCount = 3; check(s.reason == .gestureLocked)
        s = ready; s.enrolled = false; check(s.reason == .unenrolled)
        s = ready; s.cameraFault = true; s.hasFrame = false; check(s.reason == .cameraUnavailable)
        s = ready; s.hasFrame = false; check(s.reason == .checkingOwner)
        s = ready; s.faceCount = 0; check(s.reason == .ownerAbsent)
        s = ready; s.faceCount = 2; check(s.reason == .others)
        s = ready; s.rawOwnerMatch = false; check(s.reason == .others)
        s = ready; s.confirmedOwner = false; check(s.reason == .checkingOwner)
        s = ready; s.frontFacing = false; s.moving = true; check(s.reason == .angle)
        s = ready; s.moving = true; check(s.reason == .motion)
        s = ready; s.sceneReady = false; check(s.reason == .quiet)
        s = ready; s.automaticAllows = false; check(s.reason == .quiet)
        s = ready; s.enhanced = false; s.frontFacing = false; check(s.reason == nil)
        func resolve(_ running: Bool = true, _ busy: Bool = false, _ fault: Bool = false,
                     _ guardReason: DoorStatus? = nil, _ content: Bool = true, _ editing: Bool = false, _ activation: Bool = true) -> DoorStatus {
            DoorStatusResolver.resolve(running: running, busy: busy, captureFault: fault, guardian: guardReason, hasContent: content, editing: editing, activation: activation)
        }
        check(resolve() == .active)
        check(resolve(false) == .closed)
        check(resolve(false, false, true) == .captureUnavailable)
        check(resolve(false, true) == .starting)
        check(resolve(true, false, false, .gestureLocked, false) == .gestureLocked)
        check(resolve(true, false, false, nil, false) == .captureUnavailable)
        check(resolve(true, false, false, nil, true, true) == .editing)
        check(resolve(true, false, false, nil, true, false, false) == .waitingMouse)
        for status in DoorStatus.allCases { check(!status.explanation.isEmpty) }
        print("PASS: \(checks) blocked-reason precedence, recovery and status description checks")
    }
}
