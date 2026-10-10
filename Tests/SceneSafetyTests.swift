import Foundation
import CoreGraphics
import CoreVideo
import Vision

@main struct SceneSafetyTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            guard value else { fatalError("FAIL: \(message)") }
        }
        let quiet = SceneFacts(ready: true, moving: false, peace: false, frontFacing: true)
        let peace = SceneFacts(ready: true, moving: false, peace: true, frontFacing: true)
        let moving = SceneFacts(ready: true, moving: true, peace: false, frontFacing: true)
        var gate = EnhancedGate()
        var time = 0.0
        func frame(_ scene: SceneFacts, after: Double = 0.1, ownerSafe: Bool = true, eligible: Bool? = nil) {
            time += after
            gate.update(ownerSafe: ownerSafe, scene: scene, now: time, gestureEligible: eligible)
        }
        frame(quiet)
        frame(quiet, after: 2.99)
        check(!gate.allowsReveal, "background less than three seconds blocks")
        frame(quiet, after: 0.02)
        check(gate.allowsReveal && !gate.manuallyPaused, "three quiet seconds enables without gesture")
        for (yaw, pitch) in [(25.0, 0.0), (-25.0, 0.0), (0.0, 20.0), (0.0, -20.0)] {
            var turned = quiet
            turned.frontFacing = FaceFacing.isFront(yaw: yaw * .pi / 180, pitch: pitch * .pi / 180)
            frame(turned)
            check(!gate.allowsReveal && !gate.manuallyPaused, "four head directions hide without manual latch")
            frame(quiet)
            check(gate.allowsReveal, "face straight automatically resumes")
        }
        frame(SceneFacts(), ownerSafe: false)
        check(!gate.allowsReveal && !gate.manuallyPaused, "face missing blocks without manual pause")
        frame(quiet); frame(quiet, after: 3.1)
        check(gate.allowsReveal, "face returns and quiet background automatically resumes")
        time += 0.1
        gate.update(ownerSafe: false, scene: quiet, now: time, otherPersonPresent: true)
        check(!gate.allowsReveal, "other person blocks")
        frame(quiet)
        check(!gate.allowsReveal, "other person leaving starts recovery delay")
        frame(quiet, after: 3.01)
        check(gate.allowsReveal, "other person leaving resumes after delay")
        frame(peace, ownerSafe: false, eligible: false)
        check(gate.manuallyPaused && !gate.allowsReveal, "first gesture pauses even without owner")
        frame(peace, after: 4)
        check(gate.manuallyPaused, "holding first gesture cannot undo pause when owner returns")
        frame(quiet); frame(peace, after: 0.05)
        check(gate.manuallyPaused, "brief missed gesture cannot rearm")
        frame(quiet); frame(quiet, after: 0.3)
        frame(peace)
        check(!gate.manuallyPaused && gate.allowsReveal, "new gesture with owner immediately resumes without holding")
        frame(peace, after: 4)
        check(gate.allowsReveal, "holding resumed gesture does not repause")
        frame(moving)
        check(!gate.allowsReveal && !gate.manuallyPaused, "movement blocks independently")
        frame(quiet); frame(quiet, after: 2.99)
        check(!gate.allowsReveal, "background recovery waits full three seconds")
        frame(moving)
        frame(quiet); frame(quiet, after: 2.99)
        check(!gate.allowsReveal, "new motion restarts quiet timer")
        frame(quiet, after: 0.02)
        check(gate.allowsReveal, "three consecutive quiet seconds automatically resumes")
        frame(peace)
        check(gate.manuallyPaused, "new gesture pauses again")
        frame(quiet, after: 5)
        check(gate.manuallyPaused && !gate.allowsReveal, "automatic safety recovery never clears manual protection")
        frame(quiet, after: 0.3)
        frame(peace, ownerSafe: false, eligible: false)
        check(gate.manuallyPaused && !gate.allowsReveal, "second gesture without owner cannot clear protection")
        frame(peace, after: 5, ownerSafe: false, eligible: false)
        check(gate.manuallyPaused, "waiting never overrides owner requirement")
        frame(peace)
        check(!gate.manuallyPaused && gate.allowsReveal, "confirmed owner allows pending new gesture immediately")
        frame(quiet); frame(quiet, after: 0.3); frame(peace)
        check(gate.manuallyPaused, "explicit next gesture closes again")
        frame(quiet); frame(quiet, after: 0.3)
        var turned = peace; turned.frontFacing = false
        frame(turned)
        check(!gate.manuallyPaused && !gate.allowsReveal, "gesture clears manual switch without overriding face validation")
        frame(quiet)
        check(gate.allowsReveal, "front face resumes after manual toggle restored")
        frame(quiet, after: 0.3)
        frame(peace, ownerSafe: false, eligible: false)
        check(gate.manuallyPaused, "unknown or multiple-person gesture can close protection")
        var restored = EnhancedGate(manuallyPaused: true)
        restored.update(ownerSafe: true, scene: quiet, now: 30)
        restored.update(ownerSafe: true, scene: quiet, now: 34)
        check(restored.manuallyPaused && !restored.allowsReveal, "explicit paused gate remains protected during automatic recovery")
        restored.invalidateFrame()
        check(restored.manuallyPaused && !restored.allowsReveal, "camera faults do not erase manual protection")
        check(FaceFacing.isFront(yaw: 0, pitch: 0), "front pose accepted")
        check(!FaceFacing.isFront(yaw: nil, pitch: 0), "missing yaw rejected")
        check(!FaceFacing.isFront(yaw: 0, pitch: nil), "missing pitch rejected")
        check(!FaceFacing.isFront(yaw: .nan, pitch: 0), "nonfinite pose rejected")
        var immediate = EnhancedGate(); immediate.recoveryDelay = 0
        immediate.update(ownerSafe: true, scene: quiet, now: 1)
        check(immediate.allowsReveal, "disabled delay immediately reveals safe frame")
        immediate.update(ownerSafe: false, scene: quiet, now: 2)
        check(!immediate.allowsReveal, "disabled delay still blocks other people")
        immediate.update(ownerSafe: true, scene: moving, now: 3)
        check(!immediate.allowsReveal, "disabled delay still blocks motion")
        immediate.update(ownerSafe: true, scene: quiet, now: 4)
        check(immediate.allowsReveal, "disabled delay immediately recovers")
        var custom = EnhancedGate(); custom.recoveryDelay = 1.5
        custom.update(ownerSafe: true, scene: quiet, now: 10)
        custom.update(ownerSafe: true, scene: quiet, now: 11.49)
        check(!custom.allowsReveal, "custom delay waits entire duration")
        custom.update(ownerSafe: true, scene: quiet, now: 11.5)
        check(custom.allowsReveal, "custom delay duration respected")
        check(RecoveryDelay.clamp(-2) == 0 && RecoveryDelay.clamp(90) == 60 && RecoveryDelay.clamp(.nan) == 3, "delay input bounds and non-finite values")
        let baseline = [Float](repeating: 100, count: 64 * 48)
        let region = CGRect(x: 0.3, y: 0, width: 0.4, height: 0.9)
        var motion = BackgroundMotion()
        check(!motion.analyze(baseline, region: region).ready, "warmup frame")
        check(!motion.analyze(baseline, region: region).moving, "static background")
        check(!motion.analyze(baseline.map { $0 + 25 }, region: region).moving, "uniform exposure shift compensated")
        motion.reset(); _ = motion.analyze(baseline, region: region)
        var background = baseline
        for y in 12..<22 { for x in 2..<12 { background[y * 64 + x] = 230 } }
        check(motion.analyze(background, region: region).moving, "connected outside motion detected")
        motion.reset(); _ = motion.analyze(baseline, region: region)
        var owner = baseline
        for y in 20..<40 { for x in 25..<38 { owner[y * 64 + x] = 230 } }
        check(!motion.analyze(owner, region: region).moving, "owner body motion masked")
        motion.reset(); _ = motion.analyze(baseline, region: region)
        var noise = baseline
        for i in stride(from: 0, to: noise.count, by: 67) { noise[i] = 230 }
        check(!motion.analyze(noise, region: region).moving, "isolated noise ignored")
        var joints: [String: CGPoint] = ["wrist": CGPoint(x: 0.5, y: 0.2),
            "indexTip": CGPoint(x: 0.36, y: 0.65), "indexPIP": CGPoint(x: 0.43, y: 0.43),
            "middleTip": CGPoint(x: 0.62, y: 0.68), "middlePIP": CGPoint(x: 0.56, y: 0.44),
            "ringTip": CGPoint(x: 0.56, y: 0.35), "ringPIP": CGPoint(x: 0.59, y: 0.44),
            "littleTip": CGPoint(x: 0.6, y: 0.32), "littlePIP": CGPoint(x: 0.66, y: 0.4)]
        check(PeaceGesture.isPeace(joints), "peace finger geometry")
        joints["ringTip"] = CGPoint(x: 0.65, y: 0.7)
        check(!PeaceGesture.isPeace(joints), "open palm rejected")
        joints.removeValue(forKey: "wrist")
        check(!PeaceGesture.isPeace(joints), "incomplete joints rejected")
        let empty = VNDetectHumanHandPoseRequest(); empty.maximumHandCount = 4
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, nil, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), 0, CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        do { try VNImageRequestHandler(cvPixelBuffer: buffer!, orientation: .up).perform([empty]) }
        catch { fatalError("Vision hand request failed: \(error)") }
        check(!PeaceGesture.detected(empty.results ?? [], ownerRegion: region), "real Vision request on blank frame cannot unlock")
        if let directory = ProcessInfo.processInfo.environment["HOVERPORTAL_FACE_FIXTURES"] {
            for (name, expectedFront) in [("obama.jpg", true), ("obama2.jpg", false), ("biden.jpg", true)] {
                let pose = VNDetectFaceRectanglesRequest(); pose.revision = VNDetectFaceRectanglesRequestRevision3
                let landmarks = VNDetectFaceLandmarksRequest()
                let handler = VNImageRequestHandler(url: URL(fileURLWithPath: directory).appendingPathComponent(name), options: [:])
                do {
                    try handler.perform([pose]); landmarks.inputFaceObservations = pose.results
                    try handler.perform([landmarks])
                    guard let face = landmarks.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { fatalError("fixture face missing") }
                    check(face.yaw != nil && face.pitch != nil, "actual Vision pose available for \(name)")
                    check(FaceFacing.isFront(yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue) == expectedFront, "actual photo pose classification \(name)")
                } catch { fatalError("photo pose test failed: \(error)") }
            }
        }
        print("PASS: \(checks) enhanced motion, latch and hand-pose checks")
    }
}
