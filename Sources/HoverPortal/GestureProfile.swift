import Foundation
import CoreGraphics

// Positive examples explicitly supplied by the user. No images are retained.
struct GestureDescriptor: Codable {
    static let names = ["indexTip", "indexPIP", "middleTip", "middlePIP", "ringTip", "ringPIP", "littleTip", "littlePIP"]
    static let allNames = ["thumbCMC", "thumbMP", "thumbIP", "thumbTip",
        "indexMCP", "indexPIP", "indexDIP", "indexTip", "middleMCP", "middlePIP", "middleDIP", "middleTip",
        "ringMCP", "ringPIP", "ringDIP", "ringTip", "littleMCP", "littlePIP", "littleDIP", "littleTip"]
    let values: [Double]
    init?(points: [String: CGPoint], includeAllJoints: Bool = false, palmAnchor: Bool = false) {
        let names = includeAllJoints ? Self.allNames : Self.names
        guard let wrist = points["wrist"], let index = points[palmAnchor ? "indexMCP" : "indexPIP"], let middle = points[palmAnchor ? "middleMCP" : "middlePIP"],
              names.allSatisfy({ points[$0] != nil }) else { return nil }
        let dx = (index.x + middle.x) / 2 - wrist.x, dy = (index.y + middle.y) / 2 - wrist.y
        let scale = hypot(dx, dy)
        guard scale > 0.025 else { return nil }
        let ax = dx / scale, ay = dy / scale
        let indexSide = (index.x - wrist.x) * ay - (index.y - wrist.y) * ax
        let mirror = indexSide < 0 ? -1.0 : 1.0
        values = names.flatMap { name -> [Double] in
            let point = points[name]!
            let x = point.x - wrist.x, y = point.y - wrist.y
            return [Double((x * ay - y * ax) / scale) * mirror, Double((x * ax + y * ay) / scale)]
        }
        guard valid else { return nil }
    }
    var valid: Bool { (values.count == 16 || values.count == 40) && values.allSatisfy { $0.isFinite && abs($0) < 12 } }
    func distance(to other: GestureDescriptor) -> Double {
        guard valid, other.valid, values.count == other.values.count else { return .infinity }
        return sqrt(zip(values, other.values).reduce(0) { $0 + pow($1.0 - $1.1, 2) } / Double(values.count))
    }
    static func plausiblePeace(_ points: [String: CGPoint]) -> Bool {
        guard let wrist = points["wrist"], names.allSatisfy({ points[$0] != nil }) else { return false }
        func radius(_ name: String) -> CGFloat { hypot(points[name]!.x - wrist.x, points[name]!.y - wrist.y) }
        let index = radius("indexTip"), middle = radius("middleTip")
        guard index > 0.05, middle > 0.05,
              index > radius("indexPIP") * 1.1, middle > radius("middlePIP") * 1.1,
              radius("ringTip") < radius("ringPIP") * 1.25,
              radius("littleTip") < radius("littlePIP") * 1.25 else { return false }
        let a = points["indexTip"]!, b = points["middleTip"]!
        let cosine = ((a.x - wrist.x) * (b.x - wrist.x) + (a.y - wrist.y) * (b.y - wrist.y)) / (index * middle)
        return cosine > 0.2 && cosine < 0.999
    }
}

// Local shape of each finger prevents shared palm joints from diluting a wrong fingertip.
struct FingerShape {
    let state: Int // 0 folded, 1 partly bent/ambiguous, 2 extended
    let radial: Double
    let straightness: Double
    let alignment: Double
    static func signature(_ points: [String: CGPoint]) -> [FingerShape]? {
        guard let wrist = points["wrist"] else { return nil }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x-b.x, a.y-b.y)) }
        var result: [FingerShape] = []
        for name in ["thumb", "index", "middle", "ring", "little"] {
            let names = name == "thumb" ? ["thumbCMC", "thumbMP", "thumbIP", "thumbTip"] : [name+"MCP", name+"PIP", name+"DIP", name+"Tip"]
            guard names.allSatisfy({ points[$0] != nil }) else { return nil }
            let a = points[names[0]]!, b = points[names[1]]!, c = points[names[2]]!, d = points[names[3]]!
            let lengths = [distance(a,b), distance(b,c), distance(c,d)]
            guard lengths.allSatisfy({ $0 > 0.0001 }), distance(b,wrist) > 0.0001 else { return nil }
            let straightness = distance(a,d) / lengths.reduce(0,+)
            let radial = distance(d,wrist) / distance(b,wrist)
            let u = CGPoint(x: b.x-a.x, y: b.y-a.y), v = CGPoint(x: d.x-b.x, y: d.y-b.y)
            let alignment = Double(u.x*v.x+u.y*v.y) / max(0.000001, distance(a,b)*distance(b,d))
            let extended = radial > (name == "thumb" ? 1.3 : 1.12) && straightness > 0.8 && alignment > 0.55
            let folded = radial < (name == "thumb" ? 1.15 : 1.05) || straightness < 0.6 || alignment < 0.15
            result.append(FingerShape(state: extended ? 2 : folded ? 0 : 1, radial: radial, straightness: straightness, alignment: alignment))
        }
        return result
    }
    static func from(_ descriptor: GestureDescriptor) -> [FingerShape]? {
        guard descriptor.values.count == 40 else { return nil }
        var points = ["wrist": CGPoint.zero]
        for (i, name) in GestureDescriptor.allNames.enumerated() { points[name] = CGPoint(x: descriptor.values[2*i], y: descriptor.values[2*i+1]) }
        return signature(points)
    }
    static func similar(_ a: [FingerShape], _ b: [FingerShape]) -> Bool {
        guard a.count == 5, b.count == 5 else { return false }
        return zip(a,b).allSatisfy { left, right in
            left.state == right.state && abs(left.radial-right.radial) <= 0.18
                && abs(left.straightness-right.straightness) <= 0.14 && abs(left.alignment-right.alignment) <= 0.35
        }
    }
}

struct GestureProfile: Codable {
    let revision: Int
    let samples: [GestureDescriptor]
    private let cachedFingerStates: [Int]?
    private let cachedShapes: [[FingerShape]?]
    private enum CodingKeys: String, CodingKey { case revision, samples }
    init(revision: Int, samples: [GestureDescriptor]) {
        self.revision = revision; self.samples = samples
        cachedShapes = samples.map { FingerShape.from($0) }
        var counts: [[Int]: Int] = [:]
        for shape in cachedShapes.compactMap({ $0 }) { counts[shape.map(\.state), default: 0] += 1 }
        if let winner = counts.max(by: { $0.value < $1.value }), winner.value >= max(12, Int(ceil(Double(samples.count)*0.75))) { cachedFingerStates = winner.key }
        else { cachedFingerStates = nil }
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(revision: try values.decode(Int.self, forKey: .revision), samples: try values.decode([GestureDescriptor].self, forKey: .samples))
    }
    var valid: Bool { (1...3).contains(revision) && (12...48).contains(samples.count) && samples.allSatisfy { $0.valid && $0.values.count == (revision >= 2 ? 40 : 16) } }
    var dominantFingerStates: [Int]? { cachedFingerStates }
    func matches(_ points: [String: CGPoint]) -> Bool {
        guard valid, (revision >= 2 || GestureDescriptor.plausiblePeace(points)),
              let candidate = GestureDescriptor(points: points, includeAllJoints: revision >= 2, palmAnchor: revision == 3) else { return false }
        if revision == 1 { return samples.filter { candidate.distance(to: $0) <= 0.2 }.count >= 2 }
        guard let fingers = FingerShape.signature(points), let required = dominantFingerStates,
              fingers.map(\.state) == required else { return false }
        return zip(samples, cachedShapes).lazy.filter { sample, shape in
            guard let learned = shape, FingerShape.similar(fingers, learned),
                  candidate.distance(to: sample) <= 0.14 else { return false }
            // Every fingertip must match; a global average cannot hide one different finger.
            for finger in ["thumbTip", "indexTip", "middleTip", "ringTip", "littleTip"] {
                let i = GestureDescriptor.allNames.firstIndex(of: finger)! * 2
                if hypot(candidate.values[i]-sample.values[i], candidate.values[i+1]-sample.values[i+1]) > 0.24 { return false }
            }
            return true
        }.prefix(3).count == 3
    }
}
