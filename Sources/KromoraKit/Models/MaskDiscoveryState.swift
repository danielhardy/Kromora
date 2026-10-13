import Combine
import Foundation

/// Presentation events only. Discovery never requests inference, delays a document commit, or
/// claims analysis progress. A replacement visual needs only this boundary and stored pixels.
@MainActor
final class MaskDiscoveryState: ObservableObject {
    struct Request: Equatable, Sendable {
        enum Phase: Equatable, Sendable {
            case waiting
            case resolved(RegionMaskReference)
            case ending(TimeInterval)
        }

        let id: UUID
        let title: String
        let startedAt: TimeInterval
        var phase: Phase
    }

    @Published private(set) var request: Request?

    @discardableResult
    func begin(title: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> UUID {
        let id = UUID()
        request = Request(id: id, title: title, startedAt: now, phase: .waiting)
        return id
    }

    func resolve(_ id: UUID, reference: RegionMaskReference) {
        guard request?.id == id, request?.phase == .waiting else { return }
        request?.phase = .resolved(reference)
    }

    func end(_ id: UUID, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard request?.id == id, request?.phase == .waiting else { return }
        request?.phase = .ending(now)
    }

    func finish(_ id: UUID) {
        guard request?.id == id else { return }
        request = nil
    }

    func reset() { request = nil }
}

/// Monotonic, duration-independent choreography. Long waits settle into a quieter breathing
/// exposure; cached results can reveal immediately. These are artistic envelopes, not progress.
enum MaskDiscoveryTiming {
    static let revealDuration: TimeInterval = 2.4
    static let dismissalDuration: TimeInterval = 0.25

    static func waitingOpacity(elapsed: TimeInterval) -> Float {
        let entrance = min(max(elapsed / 0.25, 0), 1)
        let settle = 1 - 0.35 * min(max((elapsed - 8) / 12, 0), 1)
        return Float(entrance * settle)
    }

    static func revealProgress(elapsed: TimeInterval) -> Float {
        Float(min(max(elapsed / revealDuration, 0), 1))
    }
}
