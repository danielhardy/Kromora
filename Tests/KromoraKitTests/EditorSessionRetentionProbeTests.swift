import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-1059 evidence: how much `EditorDocumentCoordinator` retains as the number of edited
/// photos grows. The probe is window-independent and uses generated documents only. Byte figures
/// are *estimates of value payload* (encoded document size and brush/retouch sample storage), not
/// a process RSS measurement or a device-wide guarantee. See `docs/EDITOR_SESSION_RETENTION.md`.
@MainActor
final class EditorSessionRetentionProbeTests: XCTestCase {
    private static let layersPerDocument = 6
    private static let strokesPerLayer = 12
    private static let samplesPerStroke = 400
    private static let retouchSpots = 40
    private static let samplesPerSpot = 64

    /// A document whose heavy payload is brush masks and retouch recipes. `seed` makes the payload
    /// distinct so a history entry cannot share storage with its neighbour by accident.
    private func heavyDocument(seed: Int) -> EditDocument {
        func sample(_ i: Int) -> BrushSample {
            let t = Double((i &+ seed &* 7919) % 1000) / 1000
            return BrushSample(point: CGPoint(x: t, y: 1 - t), pressure: t)
        }
        var document = EditDocument()
        document.light.exposure = Double(seed % 50) / 100
        document.localAdjustments = (0..<Self.layersPerDocument).map { layer in
            let strokes = (0..<Self.strokesPerLayer).map { stroke in
                BrushStroke(samples: (0..<Self.samplesPerStroke).map { sample($0 + stroke) })
            }
            var adjustments = LocalAdjustments()
            adjustments.exposure = 0.1 + Double(layer) / 100
            return LocalAdjustmentLayer(
                name: "Layer \(layer)",
                components: [MaskComponent(source: .brush(BrushMaskDefinition(strokes: strokes)))],
                adjustments: adjustments
            )
        }
        document.retouch = RetouchSettings(spots: (0..<Self.retouchSpots).map { spot in
            RetouchSpot(
                region: RetouchRegion(samples: (0..<Self.samplesPerSpot).map { sample($0 + spot) }),
                source: .manual(offset: CGVector(dx: 0.1, dy: 0.05))
            )
        })
        return document
    }

    /// Encoded size is a stable, reproducible proxy for value payload; sample storage is added
    /// because decoded arrays carry the in-memory stride rather than the JSON text length.
    private func estimatedBytes(_ document: EditDocument) throws -> Int {
        let encoded = try JSONEncoder().encode(document).count
        let brushSamples = document.localAdjustments
            .flatMap(\.components)
            .reduce(0) { total, component in
                guard case .brush(let brush) = component.source else { return total }
                return total + brush.strokes.reduce(0) { $0 + $1.samples.count }
            }
        let retouchSamples = document.retouch.spots.reduce(0) { $0 + $1.region.samples.count }
        return encoded + (brushSamples + retouchSamples) * MemoryLayout<BrushSample>.stride
    }

    private func assetID(_ index: Int) -> PhotoAssetID {
        .photos(localIdentifier: "retention-\(index)")
    }

    /// One edited photo with `depth` undo entries, each carrying a distinct heavy payload (the
    /// worst case: no copy-on-write sharing between history entries).
    private func populate(
        _ coordinator: EditorDocumentCoordinator, photo index: Int, depth: Int
    ) {
        var current = heavyDocument(seed: index * 1000)
        coordinator.activate(session: nil)
        coordinator.commit(document: current, for: assetID(index))
        for step in 1...depth {
            let next = heavyDocument(seed: index * 1000 + step)
            coordinator.recordChange(from: current, to: next)
            coordinator.commit(document: next, for: assetID(index))
            current = next
        }
    }

    func testUnboundedRetentionGrowsLinearlyWithEditedPhotoCount() throws {
        let perDocument = try estimatedBytes(heavyDocument(seed: 1))
        XCTAssertGreaterThan(perDocument, 100_000, "fixture must be a substantial recipe")

        var report: [String] = []
        for count in [5, 20, 80] {
            let coordinator = EditorDocumentCoordinator()
            for index in 0..<count { populate(coordinator, photo: index, depth: 10) }

            XCTAssertEqual(coordinator.retainedSessionCount, count)
            XCTAssertEqual(coordinator.retainedHistoryEntryCount, count * 10)
            // Worst-case estimate: current document plus each distinct undo entry.
            let worstCase = count * (1 + 10) * perDocument
            report.append(
                "photos=\(count) sessions=\(coordinator.retainedSessionCount) "
                    + "historyEntries=\(coordinator.retainedHistoryEntryCount) "
                    + "estimatedWorstCaseBytes=\(worstCase)")
        }
        print("KRMA-1059 probe (depth 10, per-document ≈ \(perDocument) B)\n" + report.joined(separator: "\n"))
    }

    func testHistoryCapBoundsOnePhotoButNotTheWholeSession() throws {
        let perDocument = try estimatedBytes(heavyDocument(seed: 1))
        let coordinator = EditorDocumentCoordinator()
        populate(coordinator, photo: 0, depth: EditHistory.maximumDepth + 25)

        XCTAssertEqual(coordinator.undoDepth, EditHistory.maximumDepth)
        // Every commit snapshots the history by value into the photo's session, so a full
        // 100-entry history is retained for every photo that was ever edited until it is removed.
        XCTAssertEqual(coordinator.retainedHistoryEntryCount, EditHistory.maximumDepth)
        let session = try XCTUnwrap(coordinator.session(for: assetID(0)))
        XCTAssertEqual(session.history.undoCount, EditHistory.maximumDepth)
        print(
            "KRMA-1059 per-photo worst case: \(EditHistory.maximumDepth + 1) documents ≈ "
                + "\((EditHistory.maximumDepth + 1) * perDocument) B")
    }

    func testRemovingSessionsReleasesRetainedCounts() {
        let coordinator = EditorDocumentCoordinator()
        for index in 0..<4 { populate(coordinator, photo: index, depth: 3) }
        coordinator.removeSessions(for: (0..<4).map(assetID))
        XCTAssertEqual(coordinator.retainedSessionCount, 0)
        XCTAssertEqual(coordinator.retainedHistoryEntryCount, 0)
    }

    /// KRMA-1060: with a budget, clean inactive photos plateau instead of growing linearly.
    func testBoundedRetentionPlateausForCleanInactivePhotos() throws {
        let perDocument = heavyDocument(seed: 1).estimatedRetentionBytes
        let budget = perDocument * 12
        let coordinator = EditorDocumentCoordinator(
            maximumResidentSessions: 3, maximumResidentSessionBytes: budget)
        coordinator.isDirty = { _ in false }
        for index in 0..<20 {
            populate(coordinator, photo: index, depth: 2)
            coordinator.evictIfNeeded()
            XCTAssertLessThanOrEqual(coordinator.retainedSessionCount, 3)
            XCTAssertLessThanOrEqual(coordinator.estimatedResidentBytes, budget)
        }
        XCTAssertEqual(coordinator.peakResidentSessions, 4, "one new photo past the cap before each pass")
    }
}
