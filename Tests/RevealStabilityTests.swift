import Foundation
@main struct RevealStabilityTests {
    static func main() {
        var gate = RevealStability()
        gate.observe(safe: true, time: 0); assert(!gate.confirmed)
        gate.observe(safe: true, time: 0.1); assert(!gate.confirmed)
        gate.observe(safe: false, time: 0.2); assert(!gate.confirmed)
        gate.observe(safe: true, time: 0.3); assert(!gate.confirmed)
        gate.observe(safe: true, time: 0.56); assert(gate.confirmed)
        gate.observe(safe: false, time: 0.57); assert(!gate.confirmed)
        gate.observe(safe: true, time: 0.6)
        gate.observe(safe: true, time: 1); assert(!gate.confirmed)
        gate.observe(safe: true, time: 1.26); assert(gate.confirmed)
        gate.observe(safe: true, time: 1.1); assert(!gate.confirmed)
        gate.observe(safe: true, time: .nan); assert(!gate.confirmed)
        gate.reset(); assert(!gate.confirmed)
        print("Reveal stability checks passed")
    }
}
