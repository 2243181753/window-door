import Foundation

// Match identity before title. Ambiguous same-name windows must never be picked arbitrarily.
struct WindowSelection: Codable, Equatable {
    let id: UInt32
    let processID: Int32
    let bundleID: String
    let appName: String
    let title: String
    var displayName: String { title.isEmpty ? (appName.isEmpty ? "未命名窗口" : appName) : title }
    func resolve(in windows: [WindowSelection]) -> WindowSelection? {
        if let exact = windows.first(where: { $0.id == id && $0.processID == processID && $0.bundleID == bundleID }) { return exact }
        guard !title.isEmpty, !bundleID.isEmpty else { return nil }
        let matches = windows.filter { $0.bundleID == bundleID && $0.title == title }
        return matches.count == 1 ? matches[0] : nil
    }
}
