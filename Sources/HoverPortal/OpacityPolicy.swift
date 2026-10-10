import Foundation

struct OpacityRange: Equatable {
    var minimum: Double
    var maximum: Double
    init(minimum: Double, maximum: Double) {
        self.minimum = Self.clamp(minimum)
        self.maximum = max(self.minimum, Self.clamp(maximum))
    }
    static func clamp(_ value: Double) -> Double { value.isFinite ? min(100, max(0, value)) : 0 }
    mutating func setMinimum(_ value: Double) { minimum = Self.clamp(value); maximum = max(minimum, maximum) }
    mutating func setMaximum(_ value: Double) { maximum = Self.clamp(value); minimum = min(minimum, maximum) }
    func opacity(shift: Bool, active: Bool, normal: Double) -> Double {
        (shift ? (active ? maximum : minimum) : (active ? Self.clamp(normal) : 0)) / 100
    }
}
