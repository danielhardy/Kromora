import Foundation

@testable import KromoraKit

actor WorkGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var active = 0
    private(set) var peak = 0
    func hold() async {
        active += 1
        peak = max(peak, active)
        await withCheckedContinuation { waiting.append($0) }
        active -= 1
    }
    func release() {
        let saved = waiting
        waiting = []
        for continuation in saved { continuation.resume() }
    }
}
@MainActor final class Host {
    var document = EditDocument()
    var continuation: CheckedContinuation<Bool, Never>?
    func flush() async -> Bool { await withCheckedContinuation { continuation = $0 } }
}
@main struct QualityProbes {
    @MainActor static func main() async throws {
        // Cancellation-oblivious operations model ImageIO/framework calls already in progress.
        let scheduler = ImageWorkScheduler(configuration: .init(maxConcurrentThumbnails: 1))
        let gate = WorkGate()
        for i in 0..<8 {
            let id = ImageWorkScheduler.JobID("probe-\(i)")
            scheduler.enqueue(id: id, lane: .thumbnail, priority: .visibleGrid) {
                await gate.hold()
            }
            while await gate.active < i + 1 { await Task.yield() }
            scheduler.cancel(id: id)
        }
        await scheduler.cancelAllAndWait()
        print(
            "scheduler: configured=1 peakActual=\(await gate.peak) runningReported=\(scheduler.runningThumbnailCount) actualAfterShutdownBarrier=\(await gate.active)"
        )
        await gate.release()
        for _ in 0..<20 { await Task.yield() }

        // A large undo entry remains resident after the current document becomes small.
        let samples = (0..<100_000).map {
            BrushSample(point: CGPoint(x: Double($0 % 100) / 100, y: 0.5))
        }
        var heavy = EditDocument()
        heavy.localAdjustments = [
            LocalAdjustmentLayer(
                name: "Heavy",
                components: [
                    MaskComponent(
                        source: .brush(
                            BrushMaskDefinition(strokes: [BrushStroke(samples: samples)])))
                ])
        ]
        let neutral = EditDocument()
        let id = PhotoAssetID(rawValue: "retention-probe")
        let editor = EditorDocumentCoordinator(
            maximumResidentSessions: 32, maximumResidentSessionBytes: 1_000_000)
        editor.activate(session: nil, for: id)
        editor.commit(document: heavy, for: id)
        editor.recordChange(from: heavy, to: neutral)
        editor.commit(document: neutral, for: id)
        editor.clearActiveHistory()
        editor.evictIfNeeded()
        let session = editor.session(for: id)!
        let actualEstimatedPayload =
            session.document.estimatedRetentionBytes
            + session.history.undoSnapshots.reduce(0) { $0 + $1.document.estimatedRetentionBytes }
            + session.history.redoSnapshots.reduce(0) { $0 + $1.document.estimatedRetentionBytes }
        print(
            "retention: byteBudget=1000000 reported=\(editor.estimatedResidentBytes) sumOfRetainedDocumentEstimates=\(actualEstimatedPayload) retainedSessions=\(editor.retainedSessionCount)"
        )

        // Drive the real history coordinator and real package store with a paused flush.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kromora-quality-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try PortableLibraryPackage.create(
            at: root.appendingPathComponent("Probe.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        let sourceURL = root.appendingPathComponent("probe.jpg")
        try Data("disposable synthetic source".utf8).write(to: sourceURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = imported.imported[0].assetID
        let reference = EditSourceReference(
            assetID: PhotoAssetID(rawValue: "portable:\(asset.raw)"))
        let store = EditDocumentStore(package: package, lease: lease)
        let host = Host()
        host.document.light.exposure = 0.1
        try await store.save(host.document, for: reference)
        let history = EditHistoryCoordinator(
            store: store,
            environment: .init(
                activeSourceReference: { reference }, currentDocument: { host.document },
                endUndoGrouping: {},
                flushPersistence: { await host.flush() }, adoptRestoredRevision: { _, _ in },
                reportStatus: { _ in }
            ))
        let saving = history.saveSnapshot(named: "Captured")!
        while host.continuation == nil { await Task.yield() }
        host.document.light.exposure = 0.9
        try await store.save(host.document, for: reference)
        host.continuation?.resume(returning: true)
        host.continuation = nil
        await saving.value
        await history.shutdown()
        let reloaded = await store.load(for: reference)
        print(
            "snapshot: liveExposure=\(host.document.light.exposure) durableExposure=\(reloaded.document.light.exposure) loadReady=\(reloaded.status == .ready)"
        )
    }
}
