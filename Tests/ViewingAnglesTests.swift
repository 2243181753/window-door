import Foundation
import Vision
@main struct ViewingAnglesTests {
    static func main() throws {
        var count = 0
        func check(_ value: Bool) { precondition(value); count += 1 }
        func pose(_ yaw: Double = 0, _ pitch: Double = 0, _ roll: Double = 0) -> ViewingAngle {
            ViewingAngle(yaw: yaw * .pi / 180, pitch: pitch * .pi / 180, roll: roll * .pi / 180)!
        }
        let sample = pose(25, -15, 10)
        let profile = ViewingAngleProfile(revision: 1, samples: Array(repeating: sample, count: 12))
        check(profile.valid)
        check(profile.permits(sample))
        check(profile.permits(pose(27, -13, 12)))
        check(!profile.permits(pose(32, -15, 10)))
        check(!profile.permits(pose(25, -22, 10)))
        check(!profile.permits(pose(25, -15, 21)))
        check(!profile.permits(pose()))
        check(!profile.permits(nil))
        check(ViewingAngle(yaw: .nan, pitch: 0, roll: 0) == nil)
        check(ViewingAngle(yaw: 0, pitch: nil, roll: 0) == nil)
        let twoIslands = ViewingAngleProfile(revision: 1, samples: Array(repeating: pose(-20), count: 6) + Array(repeating: pose(20), count: 6))
        check(twoIslands.permits(pose(-20)) && twoIslands.permits(pose(20)))
        check(!twoIslands.permits(pose()))
        check(!ViewingAngleProfile(revision: 99, samples: profile.samples).permits(sample))
        check(!ViewingAngleProfile(revision: 1, samples: Array(profile.samples.prefix(11))).permits(sample))
        let restored = try JSONDecoder().decode(ViewingAngleProfile.self, from: JSONEncoder().encode(profile))
        check(restored.valid && restored.permits(sample))
        var learning = ViewingAngleLearning()
        for i in 0..<20 { learning.observe(sample, ownerAlone: false, time: Double(i)) }
        check(learning.samples.isEmpty)
        learning.observe(sample, ownerAlone: true, time: 21)
        learning.observe(sample, ownerAlone: true, time: 22)
        check(learning.samples.isEmpty)
        learning.observe(sample, ownerAlone: true, time: 23)
        check(learning.samples.count == 1)
        learning.observe(sample, ownerAlone: true, time: 23.01)
        check(learning.samples.count == 1)
        learning.observe(nil, ownerAlone: true, time: 24)
        learning.observe(sample, ownerAlone: true, time: 25)
        learning.observe(sample, ownerAlone: true, time: 26)
        check(learning.samples.count == 1)
        for i in 27..<40 { learning.observe(sample, ownerAlone: true, time: Double(i)) }
        check(learning.profile?.permits(sample) == true)
        for i in 40..<1300 { learning.observe(sample, ownerAlone: true, time: Double(i)) }
        check(learning.samples.count == 1200 && learning.profile?.valid == true)
        check(profile.permits(pose(28, -12, 15))) // Previous joint ellipsoid rejected this natural drift.
        check(profile.permits(pose(31, -9, 20)))
        check(!profile.permits(pose(31.01, -9, 20)))
        check(!profile.permits(pose(31, -8.99, 20)))
        check(!profile.permits(pose(31, -9, 20.01)))
        let outlier = ViewingAngleProfile(revision: 2, samples: Array(repeating: pose(), count: 12) + [pose(30)])
        check(!outlier.permits(pose(30)))
        var additional = ViewingAngleLearning(existing: profile.samples)
        for i in 0..<8 { additional.observe(pose(-20), ownerAlone: true, time: Double(i)) }
        check(additional.profile?.permits(sample) == true && additional.profile?.permits(pose(-20)) == true)
        check(additional.profile?.permits(pose()) == false)
        check(additional.profile?.revision == 2)
        check(profile.nearestDifferences(pose(28, -12, 15))!.map { Int($0.rounded()) } == [3, 3, 5])
        if let directory = ProcessInfo.processInfo.environment["HOVERPORTAL_FACE_FIXTURES"] {
            for name in ["obama.jpg", "obama2.jpg", "biden.jpg"] {
                let request = VNDetectFaceRectanglesRequest(); request.revision = VNDetectFaceRectanglesRequestRevision3
                let landmarks = VNDetectFaceLandmarksRequest()
                let handler = VNImageRequestHandler(url: URL(fileURLWithPath: directory).appendingPathComponent(name), options: [:])
                try handler.perform([request]); landmarks.inputFaceObservations = request.results
                try handler.perform([landmarks])
                let face = landmarks.results!.max { $0.boundingBox.width < $1.boundingBox.width }!
                let angle = ViewingAngle(yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, roll: face.roll?.doubleValue)
                check(angle != nil)
                let learned = ViewingAngleProfile(revision: 1, samples: Array(repeating: angle!, count: 12))
                check(learned.permits(angle))
                check(!learned.permits(ViewingAngle(yaw: angle!.yaw+20 * .pi/180, pitch: angle!.pitch, roll: angle!.roll)))
            }
        }
        print("PASS: \(count) personalized viewing-angle boundary, learning and persistence checks")
    }
}
