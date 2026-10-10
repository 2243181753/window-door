import Foundation
@main struct WindowSelectionTests {
    static func main() throws {
        let saved = WindowSelection(id: 100, processID: 20, bundleID: "test.editor", appName: "Editor", title: "My document")
        let changed = WindowSelection(id: 100, processID: 20, bundleID: "test.editor", appName: "Editor", title: "Renamed document")
        precondition(saved.resolve(in: [changed]) == changed)
        let reopened = WindowSelection(id: 101, processID: 21, bundleID: "test.editor", appName: "Editor", title: "My document")
        precondition(saved.resolve(in: [reopened]) == reopened)
        let otherApp = WindowSelection(id: 100, processID: 30, bundleID: "test.browser", appName: "Browser", title: "My document")
        precondition(saved.resolve(in: [otherApp]) == nil)
        let duplicate = WindowSelection(id: 102, processID: 21, bundleID: "test.editor", appName: "Editor", title: "My document")
        precondition(saved.resolve(in: [reopened, duplicate]) == nil)
        precondition(saved.resolve(in: []) == nil)
        let blank = WindowSelection(id: 103, processID: 20, bundleID: "test.editor", appName: "Editor", title: "")
        precondition(blank.displayName == "Editor")
        precondition(blank.resolve(in: [reopened]) == nil)
        let restored = try JSONDecoder().decode(WindowSelection.self, from: JSONEncoder().encode(saved))
        precondition(restored == saved)
        precondition(restored.displayName == "My document")
        print("PASS: 9 remembered-window identity, title, ambiguity and storage checks")
    }
}
