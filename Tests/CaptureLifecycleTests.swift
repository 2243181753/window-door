import Foundation

@MainActor final class Log { var events: [String] = [] }
enum Failure: Error { case expected }
@MainActor final class FakeSession: CaptureSessionResource {
    let name: String
    let log: Log
    var failStart = false
    var failStop = false
    var holdStop = false
    var continuation: CheckedContinuation<Void, Never>?
    var whenStopping: (() -> Void)?
    init(_ name: String, _ log: Log) { self.name = name; self.log = log }
    func startSession() async throws {
        log.events.append("start " + name)
        if failStart { throw Failure.expected }
    }
    func stopSession() async throws {
        log.events.append("stop " + name)
        whenStopping?()
        if holdStop { await withCheckedContinuation { continuation = $0 } }
        if failStop { throw Failure.expected }
    }
    func detachOutput() { log.events.append("detach " + name) }
}

@main struct CaptureLifecycleTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: Bool) { precondition(value); checks += 1 }
        let log = Log(), lifecycle = CaptureLifecycle<FakeSession>()
        let a = FakeSession("A", log), b = FakeSession("B", log)
        try await lifecycle.replace { a }
        check(lifecycle.owns(a))
        a.whenStopping = { check(!lifecycle.owns(a)); check(lifecycle.current == nil) }
        try await lifecycle.replace { b }
        check(log.events == ["start A", "stop A", "detach A", "start B"])
        check(lifecycle.owns(b) && !lifecycle.owns(a))
        try await lifecycle.stop()
        check(lifecycle.current == nil && !lifecycle.owns(b))
        check(log.events.suffix(2) == ["stop B", "detach B"])
        try await lifecycle.stop()
        check(log.events.count == 6)

        let broken = FakeSession("broken", log)
        broken.failStop = true
        try await lifecycle.replace { broken }
        var created = false
        do { try await lifecycle.replace { created = true; return b }; preconditionFailure() }
        catch { check(!created) }
        check(lifecycle.current == nil && log.events.last == "detach broken")
        let failed = FakeSession("failed", log)
        failed.failStart = true
        do { try await lifecycle.replace { failed }; preconditionFailure() }
        catch { check(lifecycle.current == nil) }
        check(log.events.suffix(3) == ["start failed", "stop failed", "detach failed"])

        let held = FakeSession("held", log), next = FakeSession("next", log)
        held.holdStop = true
        try await lifecycle.replace { held }
        let stopping = Task { @MainActor in try await lifecycle.stop() }
        while held.continuation == nil { await Task.yield() }
        check(!lifecycle.owns(held))
        var replacementCreated = false
        let replacing = Task { @MainActor in
            try await lifecycle.replace { replacementCreated = true; return next }
        }
        for _ in 0..<10 { await Task.yield() }
        check(!replacementCreated && lifecycle.current == nil)
        held.continuation?.resume()
        try await stopping.value
        try await replacing.value
        check(log.events.suffix(3) == ["stop held", "detach held", "start next"])
        check(lifecycle.owns(next) && !lifecycle.owns(held))
        try await lifecycle.stop()
        print("PASS: \(checks) capture replacement, late callback ownership and teardown checks")
    }
}
