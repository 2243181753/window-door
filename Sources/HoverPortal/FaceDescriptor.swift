import Foundation

struct FaceDescriptor: Codable {
    let values: [Float]
    func similarity(to other: FaceDescriptor) -> Float {
        guard values.count == 128, other.values.count == 128 else { return -1 }
        return zip(values,other.values).reduce(0) { $0 + $1.0*$1.1 }
    }
}
struct OwnerProfile: Codable {
    let revision: Int
    let descriptors: [FaceDescriptor]
    var valid: Bool {
        revision == 3 && descriptors.count >= 12 && descriptors.count <= 40 && descriptors.allSatisfy {
            $0.values.count == 128 && $0.values.allSatisfy { $0.isFinite } &&
            abs($0.values.reduce(0) { $0 + $1*$1 } - 1) < 0.02
        }
    }
}

enum FaceMatcher {
    static let threshold: Float = 0.55
    static func matches(_ candidate: FaceDescriptor, profiles: [FaceDescriptor]) -> Bool {
        var matches = 0
        for profile in profiles where profile.similarity(to: candidate) >= threshold {
            matches += 1
            if matches == 2 { return true }
        }
        return false
    }
}
