import Foundation

@MainActor protocol CaptureSessionResource: AnyObject {
    func startSession() async throws
    func stopSession() async throws
    func detachOutput()
}

// Invalidate callbacks before teardown. Concurrent stops share the same teardown;
// a replacement cannot start while the previous resource is still being released.
@MainActor final class CaptureLifecycle<Resource: CaptureSessionResource> {
    private(set) var current: Resource?
    private var retiring: (id: UUID, task: Task<Void, Error>)?
    func owns(_ resource: Resource) -> Bool { current === resource }
    func replace(make: () throws -> Resource) async throws {
        try await stop()
        let next = try make()
        current = next
        do { try await next.startSession() }
        catch {
            try? await stop()
            throw error
        }
    }
    func stop() async throws {
        let pending: (id: UUID, task: Task<Void, Error>)
        if let retiring { pending = retiring }
        else {
            guard let old = current else { return }
            current = nil
            pending = (UUID(), Task { @MainActor in
                defer { old.detachOutput() }
                try await old.stopSession()
            })
            retiring = pending
        }
        defer { if retiring?.id == pending.id { retiring = nil } }
        try await pending.task.value
    }
}
