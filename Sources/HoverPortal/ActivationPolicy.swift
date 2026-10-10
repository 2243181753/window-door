import Foundation

enum ActivationPolicy {
    static func triggered(mouseEnabled: Bool, hovering: Bool, faceEnabled: Bool) -> Bool {
        mouseEnabled ? hovering : faceEnabled
    }
}
