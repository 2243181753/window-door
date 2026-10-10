import Foundation

// Stable across source builds and future app bundles using the same bundle identifier.
enum PortalPreferences {
    static let shared: UserDefaults = {
        let identifier = "local.hoverportal.camera"
        // In a packaged app, its own domain is already UserDefaults.standard.
        // AppKit rejects opening that same identifier as an additional suite.
        let settings = Bundle.main.bundleIdentifier == identifier
            ? UserDefaults.standard : UserDefaults(suiteName: identifier)!
        for key in ["showOutline", "followWindow", "contentOpacity", "shortcutBindingsV1"] {
            if settings.object(forKey: key) == nil, let value = UserDefaults.standard.object(forKey: key) {
                settings.set(value, forKey: key)
            }
        }
        return settings
    }()
}
