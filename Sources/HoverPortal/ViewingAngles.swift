import Foundation

struct ViewingAngle: Codable, Equatable {
    let yaw: Double
    let pitch: Double
    let roll: Double
    init?(yaw: Double?, pitch: Double?, roll: Double?) {
        guard let yaw, let pitch, let roll,
              yaw.isFinite, pitch.isFinite, roll.isFinite,
              abs(yaw) <= .pi, abs(pitch) <= .pi, abs(roll) <= .pi else { return nil }
        self.yaw = yaw; self.pitch = pitch; self.roll = roll
    }
    var valid: Bool { Self(yaw: yaw, pitch: pitch, roll: roll) != nil }
    func differences(to other: Self) -> [Double] {
        func distance(_ a: Double, _ b: Double) -> Double {
            let d = abs(a-b).truncatingRemainder(dividingBy: 2 * .pi)
            return min(d, 2 * .pi-d) * 180 / .pi
        }
        return [distance(yaw, other.yaw), distance(pitch, other.pitch), distance(roll, other.roll)]
    }
    func close(to other: Self) -> Bool {
        let delta = differences(to: other)
        // Independent bounded tolerances: simultaneous small changes no longer add up to rejection.
        return delta[0] <= 6.000001 && delta[1] <= 6.000001 && delta[2] <= 10.000001
    }
}

struct ViewingAngleProfile: Codable {
    let revision: Int
    let samples: [ViewingAngle]
    var valid: Bool { (revision == 1 || revision == 2) && (12...1200).contains(samples.count) && samples.allSatisfy(\.valid) }
    func permits(_ angle: ViewingAngle?) -> Bool {
        guard valid, let angle, angle.valid else { return false }
        // Two nearby examples are required. Never fill an unlearned gap using a global min/max box.
        return samples.lazy.filter { angle.close(to: $0) }.prefix(2).count == 2
    }
    func nearestDifferences(_ angle: ViewingAngle?) -> [Double]? {
        guard valid, let angle, angle.valid else { return nil }
        return samples.lazy.map { angle.differences(to: $0) }.min {
            max($0[0]/6, $0[1]/6, $0[2]/10) < max($1[0]/6, $1[1]/6, $1[2]/10)
        }
    }
}

struct ViewingAngleLearning {
    private(set) var samples: [ViewingAngle]
    private var lastTime: Double?
    private var ownerStreak = 0
    init(existing: [ViewingAngle] = []) { samples = existing.filter(\.valid).prefix(1200).map { $0 } }
    mutating func observe(_ angle: ViewingAngle?, ownerAlone: Bool, time: Double) {
        guard ownerAlone, let angle, angle.valid, time.isFinite else { ownerStreak = 0; return }
        ownerStreak += 1
        guard ownerStreak >= 3, samples.count < 1200,
              lastTime == nil || time - lastTime! >= 0.2 else { return }
        samples.append(angle); lastTime = time
    }
    var profile: ViewingAngleProfile? {
        let candidate = ViewingAngleProfile(revision: 2, samples: samples)
        return candidate.valid ? candidate : nil
    }
}
