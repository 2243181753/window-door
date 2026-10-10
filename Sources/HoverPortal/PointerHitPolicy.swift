import Foundation
import CoreGraphics

// Never promote a page, player canvas or broad container into one semantic button.
enum PointerHitPolicy {
    static let roles: Set<String> = ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuItem", "AXTab", "AXSwitch", "AXDisclosureTriangle"]
    static func accepts(role: String, frame: CGRect, point: CGPoint, window: CGRect) -> Bool {
        roles.contains(role) && frame.width > 0 && frame.height > 0 && frame.contains(point)
            && frame.intersection(window).width * frame.intersection(window).height < window.width * window.height * 0.6
    }
}
