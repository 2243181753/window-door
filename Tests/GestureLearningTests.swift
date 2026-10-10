import Foundation
import CoreGraphics
@main struct GestureLearningTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1; precondition(condition, name)
        }
        let points: [String: CGPoint] = ["wrist": CGPoint(x: 0.5, y: 0.2),
            "indexTip": CGPoint(x: 0.36, y: 0.65), "indexPIP": CGPoint(x: 0.43, y: 0.43),
            "middleTip": CGPoint(x: 0.62, y: 0.68), "middlePIP": CGPoint(x: 0.56, y: 0.44),
            "ringTip": CGPoint(x: 0.56, y: 0.35), "ringPIP": CGPoint(x: 0.59, y: 0.44),
            "littleTip": CGPoint(x: 0.6, y: 0.32), "littlePIP": CGPoint(x: 0.66, y: 0.4)]
        let baseline = GestureDescriptor(points: points)!
        check(baseline.valid, "normal descriptor valid")
        let profile = GestureProfile(revision: 1, samples: Array(repeating: baseline, count: 24))
        check(profile.valid && profile.matches(points), "explicit positive samples recognize the pose")
        for angle in [-1.5, -0.5, 0.5, 1.5] {
            let transformed = points.mapValues { p in
                CGPoint(x: (p.x * cos(angle) - p.y * sin(angle)) * 0.6 + 0.3,
                        y: (p.x * sin(angle) + p.y * cos(angle)) * 0.6 + 0.3)
            }
            check(profile.matches(transformed), "translation scale and rotation accepted")
        }
        check(profile.matches(points.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) }), "mirrored hand accepted")
        var tilted = points
        tilted["indexTip"] = CGPoint(x: 0.38, y: 0.50)
        tilted["middleTip"] = CGPoint(x: 0.60, y: 0.49)
        check(!PeaceGesture.isPeace(tilted), "perspective-shortened gesture is rejected by old strict rule")
        check(GestureDescriptor.plausiblePeace(tilted), "shortened pose remains plausible for explicit learning")
        let tiltedProfile = GestureProfile(revision: 1, samples: Array(repeating: GestureDescriptor(points: tilted)!, count: 24))
        check(tiltedProfile.matches(tilted), "personal learning recovers shortened pose")
        var openPalm = tilted; openPalm["ringTip"] = CGPoint(x: 0.66, y: 0.68); openPalm["littleTip"] = CGPoint(x: 0.74, y: 0.61)
        check(!tiltedProfile.matches(openPalm), "open palm rejected")
        var fist = tilted; fist["indexTip"] = CGPoint(x: 0.46, y: 0.31); fist["middleTip"] = CGPoint(x: 0.53, y: 0.31)
        check(!tiltedProfile.matches(fist), "fist rejected")
        var missing = tilted; missing.removeValue(forKey: "middlePIP")
        check(!tiltedProfile.matches(missing), "missing joints rejected")
        let restored = try JSONDecoder().decode(GestureProfile.self, from: JSONEncoder().encode(tiltedProfile))
        check(restored.valid && restored.matches(tilted), "profile roundtrip keeps personal recognition")
        check(!GestureProfile(revision: 1, samples: [baseline]).valid, "single noisy sample cannot form a profile")
        check(!GestureProfile(revision: 99, samples: profile.samples).valid, "unknown format rejected")
        let corrupt = Data("{\"revision\":1,\"samples\":[{\"values\":[0]}]}".utf8)
        check(!(try JSONDecoder().decode(GestureProfile.self, from: corrupt)).valid, "malformed vectors rejected")
        var custom = fist
        custom["thumbCMC"] = CGPoint(x: 0.41, y: 0.26)
        custom["thumbMP"] = CGPoint(x: 0.37, y: 0.31)
        custom["thumbIP"] = CGPoint(x: 0.34, y: 0.39)
        custom["thumbTip"] = CGPoint(x: 0.31, y: 0.47)
        for finger in ["index", "middle", "ring", "little"] {
            let pip = custom[finger + "PIP"]!, tip = custom[finger + "Tip"]!
            custom[finger + "MCP"] = CGPoint(x: pip.x, y: pip.y - 0.08)
            custom[finger + "DIP"] = CGPoint(x: (pip.x + tip.x)/2, y: (pip.y + tip.y)/2)
        }
        let customDescriptor = GestureDescriptor(points: custom, includeAllJoints: true)!
        let customProfile = GestureProfile(revision: 2, samples: Array(repeating: customDescriptor, count: 24))
        check(customProfile.valid && customProfile.matches(custom), "arbitrary non-V gesture learns full hand")
        check(!PeaceGesture.isPeace(custom), "custom gesture requires no V shape")
        check(customDescriptor.values.count == 40, "all fingers including thumb are saved")
        var thumbChanged = custom
        thumbChanged["thumbTip"] = CGPoint(x: 0.62, y: 0.28)
        thumbChanged["thumbIP"] = CGPoint(x: 0.58, y: 0.28)
        check(!customProfile.matches(thumbChanged), "thumb position distinguishes otherwise same fist")
        check(customProfile.matches(custom.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) }), "custom palm/back mirror accepted")
        let customRestored = try JSONDecoder().decode(GestureProfile.self, from: JSONEncoder().encode(customProfile))
        check(customRestored.matches(custom), "custom format survives restart")
        check(!GestureProfile(revision: 2, samples: profile.samples).valid, "new custom format cannot silently reuse incomplete old vectors")
        func hand(_ extended: Set<String>) -> [String: CGPoint] {
            var hand = ["wrist": CGPoint.zero, "thumbCMC": CGPoint(x: -0.3, y: 0.2), "thumbMP": CGPoint(x: -0.5, y: 0.45)]
            hand["thumbIP"] = extended.contains("thumb") ? CGPoint(x: -0.7, y: 0.65) : CGPoint(x: -0.4, y: 0.3)
            hand["thumbTip"] = extended.contains("thumb") ? CGPoint(x: -0.9, y: 0.85) : CGPoint(x: -0.26, y: 0.3)
            for (i, finger) in ["index", "middle", "ring", "little"].enumerated() {
                let x = Double(i) * 0.2 - 0.2
                hand[finger+"MCP"] = CGPoint(x: x, y: 0.6)
                hand[finger+"PIP"] = CGPoint(x: x, y: 0.95)
                hand[finger+"DIP"] = CGPoint(x: x, y: extended.contains(finger) ? 1.15 : 0.78)
                hand[finger+"Tip"] = CGPoint(x: x, y: extended.contains(finger) ? 1.35 : 0.68)
            }
            return hand
        }
        let gestures: [(String, Set<String>)] = [("six", ["thumb", "little"]), ("eight", ["thumb", "index"]), ("V", ["index", "middle"]), ("fist", []), ("palm", ["thumb", "index", "middle", "ring", "little"])]
        for (name, extended) in gestures {
            let original = hand(extended)
            let descriptor = GestureDescriptor(points: original, includeAllJoints: true, palmAnchor: true)!
            let learned = GestureProfile(revision: 3, samples: Array(repeating: descriptor, count: 24))
            for (other, otherExtended) in gestures {
                check(learned.matches(hand(otherExtended)) == (name == other), "\(name) must distinguish \(other)")
            }
            let reflected = original.mapValues { CGPoint(x: 1-$0.x, y: $0.y) }
            check(learned.matches(reflected), "full hand reflection keeps finger identities")
            let rotated = original.mapValues { p in CGPoint(x: p.x*cos(0.7)-p.y*sin(0.7)+0.2, y: p.x*sin(0.7)+p.y*cos(0.7)+0.1) }
            check(learned.matches(rotated), "full hand rotation keeps finger identities")
        }
        let mixed = gestures.prefix(3).flatMap { _, fingers in Array(repeating: GestureDescriptor(points: hand(fingers), includeAllJoints: true, palmAnchor: true)!, count: 8) }
        let mixedProfile = GestureProfile(revision: 3, samples: mixed)
        check(mixedProfile.dominantFingerStates == nil && !mixedProfile.matches(hand(["index", "middle"])), "mixed positive gestures cannot create an all-purpose trigger")
        let v = hand(["index", "middle"])
        let legacyCustom = GestureProfile(revision: 2, samples: Array(repeating: GestureDescriptor(points: v, includeAllJoints: true)!, count: 24))
        check(legacyCustom.matches(v) && !legacyCustom.matches(hand([])) && !legacyCustom.matches(hand(["thumb", "index"])), "old custom samples also receive finger-specific rejection")
        let savedV = GestureProfile(revision: 3, samples: Array(repeating: GestureDescriptor(points: v, includeAllJoints: true, palmAnchor: true)!, count: 24))
        let restoredV = try JSONDecoder().decode(GestureProfile.self, from: JSONEncoder().encode(savedV))
        check(restoredV.matches(v) && !restoredV.matches(hand([])), "strict gesture profile survives restart")
        var oneWrongFinger = v
        oneWrongFinger["littleTip"] = CGPoint(x: 0.4, y: 1.2)
        let oldReference = GestureDescriptor(points: v, includeAllJoints: true)!
        let oldWrong = GestureDescriptor(points: oneWrongFinger, includeAllJoints: true)!
        check(oldReference.distance(to: oldWrong) < 0.2, "regression: old whole-hand average would accept one wrong finger")
        check(!savedV.matches(oneWrongFinger), "regression: finger-specific gate rejects diluted mismatch")
        print("PASS: \(count) personal gesture learning checks")
    }
}
