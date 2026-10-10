import Foundation
import CoreGraphics
import CoreVideo
import Vision

struct SceneFacts {
    var ready = false
    var moving = false
    var peace = false
    var frontFacing = false
    var analysisFailed = false
    var viewingAngleDifference: [Double]?
    var poseAvailable = false
}

// Automatic validation recovers on its own. Gesture pause is an independent, explicit toggle.
struct EnhancedGate {
    private(set) var manuallyPaused = false
    private(set) var allowsReveal = false
    var locked: Bool { !allowsReveal }
    private var quietSince: TimeInterval?
    var recoveryDelay: TimeInterval = 3
    private var gestureArmed = true
    private var releaseSince: TimeInterval?
    init(manuallyPaused: Bool = false) { self.manuallyPaused = manuallyPaused }
    mutating func resetManualProtection() {
        manuallyPaused = false; gestureArmed = true; releaseSince = nil; allowsReveal = false
    }
    mutating func invalidateFrame() {
        allowsReveal = false; quietSince = nil; releaseSince = nil
    }
    mutating func update(ownerSafe: Bool, scene: SceneFacts, now: TimeInterval, gestureEligible: Bool? = nil, gesturesEnabled: Bool = true, otherPersonPresent: Bool = false) {
        let eligible = gestureEligible ?? ownerSafe
        if !gesturesEnabled {
            manuallyPaused = false; gestureArmed = true; releaseSince = nil
        } else if !scene.peace {
            if releaseSince == nil { releaseSince = now }
            if now - releaseSince! >= 0.2 { gestureArmed = true }
        } else {
            releaseSince = nil
            if gestureArmed {
                if !manuallyPaused {
                    // Anyone can close the privacy gate, even when no owner face is visible.
                    manuallyPaused = true; gestureArmed = false
                } else if eligible {
                    // Reopening needs a confirmed owner, but no gesture hold timer.
                    manuallyPaused = false; gestureArmed = false
                }
            }
        }
        if otherPersonPresent || !scene.ready || scene.moving {
            quietSince = nil
        } else if quietSince == nil { quietSince = now }
        allowsReveal = ownerSafe && scene.frontFacing && scene.ready && !scene.moving
            && !manuallyPaused && quietSince.map { now - $0 >= max(0, recoveryDelay) } == true
    }
}

enum FaceFacing {
    // A small natural pose variation is tolerated; missing estimates never count as frontal.
    static func isFront(yaw: Double?, pitch: Double?) -> Bool {
        guard let yaw, let pitch, yaw.isFinite, pitch.isFinite else { return false }
        return abs(yaw) <= 15 * .pi / 180 && abs(pitch) <= 12 * .pi / 180
    }
}

// Samples a small luminance grid, masks the owner's estimated body, and compensates exposure drift.
struct BackgroundMotion {
    static let width = 64, height = 48
    private var previous: [Float]?
    private var previousRegion = CGRect.zero
    mutating func reset() { previous = nil; previousRegion = .zero }
    static func ownerRegion(face: CGRect) -> CGRect {
        CGRect(x: face.midX - face.width * 1.8, y: 0,
               width: face.width * 3.6, height: min(1, face.maxY + face.height * 0.4))
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    mutating func analyze(_ pixels: [Float], region: CGRect) -> SceneFacts {
        defer { previous = pixels; previousRegion = region }
        guard pixels.count == Self.width * Self.height, let previous, previous.count == pixels.count else { return SceneFacts() }
        var indexes = [Int](); var shift: Float = 0
        for y in 0..<Self.height { for x in 0..<Self.width {
            let point = CGPoint(x: (Double(x) + 0.5) / Double(Self.width), y: 1 - (Double(y) + 0.5) / Double(Self.height))
            if !region.contains(point), !previousRegion.contains(point) {
                let i = y * Self.width + x; indexes.append(i); shift += pixels[i] - previous[i]
            }
        } }
        guard indexes.count >= 80 else { return SceneFacts() }
        shift /= Float(indexes.count)
        var changed = Set<Int>()
        for i in indexes where abs((pixels[i] - previous[i]) - shift) > 18 { changed.insert(i) }
        var largest = 0
        while let start = changed.first {
            changed.remove(start); var pending = [start]; var size = 0
            while let i = pending.popLast() {
                size += 1
                let neighbors = [i - Self.width, i + Self.width] + (i % Self.width > 0 ? [i - 1] : []) + (i % Self.width < Self.width - 1 ? [i + 1] : [])
                for next in neighbors where changed.remove(next) != nil { pending.append(next) }
            }
            largest = max(largest, size)
        }
        // A connected change helps reject isolated sensor noise. Small objects can still be missed.
        return SceneFacts(ready: true, moving: largest >= max(8, Int(Double(indexes.count) * 0.015)), peace: false)
    }
    mutating func analyze(buffer: CVPixelBuffer, face: CGRect) -> SceneFacts {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { reset(); return SceneFacts() }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer), w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        var pixels = [Float](); pixels.reserveCapacity(Self.width * Self.height)
        for y in 0..<Self.height { for x in 0..<Self.width {
            let i = min(h - 1, (y * h + h / 2) / Self.height) * stride + min(w - 1, (x * w + w / 2) / Self.width) * 4
            pixels.append(0.114 * Float(bytes[i]) + 0.587 * Float(bytes[i + 1]) + 0.299 * Float(bytes[i + 2]))
        } }
        return analyze(pixels, region: Self.ownerRegion(face: face))
    }
}

struct PeaceGesture {
    static func isPeace(_ points: [String: CGPoint]) -> Bool {
        guard let wrist = points["wrist"], let indexTip = points["indexTip"], let middleTip = points["middleTip"],
              let indexPIP = points["indexPIP"], let middlePIP = points["middlePIP"],
              let ringTip = points["ringTip"], let ringPIP = points["ringPIP"],
              let littleTip = points["littleTip"], let littlePIP = points["littlePIP"] else { return false }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        let a = distance(indexTip, wrist), b = distance(middleTip, wrist)
        guard a > 0.08, b > 0.08,
              a > distance(indexPIP, wrist) * 1.25, b > distance(middlePIP, wrist) * 1.25,
              distance(ringTip, wrist) < distance(ringPIP, wrist) * 1.1,
              distance(littleTip, wrist) < distance(littlePIP, wrist) * 1.1 else { return false }
        let cosine = ((indexTip.x - wrist.x) * (middleTip.x - wrist.x) + (indexTip.y - wrist.y) * (middleTip.y - wrist.y)) / (a * b)
        return cosine > 0.4 && cosine < 0.985
    }
    static func points(_ observation: VNHumanHandPoseObservation, minimumConfidence: Float = 0.5) -> [String: CGPoint] {
        let names: [(String, VNHumanHandPoseObservation.JointName)] = [
            ("wrist", .wrist), ("thumbCMC", .thumbCMC), ("thumbMP", .thumbMP), ("thumbIP", .thumbIP), ("thumbTip", .thumbTip),
            ("indexMCP", .indexMCP), ("indexDIP", .indexDIP), ("middleMCP", .middleMCP), ("middleDIP", .middleDIP),
            ("ringMCP", .ringMCP), ("ringDIP", .ringDIP), ("littleMCP", .littleMCP), ("littleDIP", .littleDIP),
            ("indexTip", .indexTip), ("indexPIP", .indexPIP),
            ("middleTip", .middleTip), ("middlePIP", .middlePIP), ("ringTip", .ringTip),
            ("ringPIP", .ringPIP), ("littleTip", .littleTip), ("littlePIP", .littlePIP)]
        var points = [String: CGPoint]()
        for (name, joint) in names {
            if let point = try? observation.recognizedPoint(joint), point.confidence >= minimumConfidence { points[name] = point.location }
        }
        return points
    }
    static func detected(_ observations: [VNHumanHandPoseObservation], ownerRegion: CGRect? = nil, profile: GestureProfile? = nil) -> Bool {
        for observation in observations {
            let strict = points(observation)
            let personal = points(observation, minimumConfidence: (profile?.revision ?? 1) >= 2 ? 0.5 : 0.35)
            guard let wrist = personal["wrist"], ownerRegion == nil || ownerRegion!.contains(wrist) else { continue }
            if let profile {
                if profile.matches(personal) { return true }
            } else if isPeace(strict) { return true }
        }
        return false
    }
}
