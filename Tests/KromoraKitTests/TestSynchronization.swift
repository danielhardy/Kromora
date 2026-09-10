import Foundation

/// A serial consumer for FakeRenderEngine's lifecycle stream. It turns actor events into explicit
/// synchronization points while retaining a bounded timeout so a real deadlock remains actionable.
final class FakeRenderEventReader: @unchecked Sendable {
    private var iterator: AsyncStream<FakeRenderEngine.Event>.Iterator

    init(_ stream: AsyncStream<FakeRenderEngine.Event>) {
        iterator = stream.makeAsyncIterator()
    }

    private func nextMatching(
        _ predicate: @escaping @Sendable (FakeRenderEngine.Event) -> Bool,
        description: String
    ) async throws -> FakeRenderEngine.Event {
        while let event = await iterator.next() {
            if predicate(event) { return event }
        }
        throw TestSynchronizationError.streamEnded(description)
    }

    func next(
        matching predicate: @escaping @Sendable (FakeRenderEngine.Event) -> Bool,
        timeout: Duration,
        description: String,
        diagnostics: @escaping @Sendable () async -> String
    ) async throws -> FakeRenderEngine.Event {
        do {
            return try await withThrowingTaskGroup(of: FakeRenderEngine.Event.self) { group in
                group.addTask {
                    try await self.nextMatching(predicate, description: description)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw TestSynchronizationError.timedOut(description, await diagnostics())
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch let error as TestSynchronizationError {
            throw error
        } catch is CancellationError {
            throw TestSynchronizationError.timedOut(description, await diagnostics())
        }
    }
}

enum TestSynchronizationError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case timedOut(String, String)
    case streamEnded(String)

    var description: String {
        switch self {
        case .timedOut(let description, let diagnostics):
            return "timed out waiting for \(description); \(diagnostics)"
        case .streamEnded(let description):
            return "event stream ended while waiting for \(description)"
        }
    }

    var errorDescription: String? { description }
}

@MainActor
enum TestSynchronization {
    static func nextEvent(
        from reader: FakeRenderEventReader,
        _ description: String,
        timeout: Duration = .seconds(10),
        matching predicate: @escaping @Sendable (FakeRenderEngine.Event) -> Bool,
        diagnostics: @escaping @Sendable () async -> String
    ) async throws -> FakeRenderEngine.Event {
        do {
            return try await reader.next(
                matching: predicate, timeout: timeout, description: description,
                diagnostics: diagnostics
            )
        } catch {
            throw error
        }
    }
}
