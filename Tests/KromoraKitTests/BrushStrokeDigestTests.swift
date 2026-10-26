import CoreGraphics
import XCTest

@testable import KromoraKit

final class BrushStrokeDigestTests: XCTestCase {
    private static func stroke(_ seed: Double, count: Int = 8) -> BrushStroke {
        BrushStroke(
            samples: (0..<count).map {
                BrushSample(point: CGPoint(x: 0.1 + Double($0) * 0.05, y: 0.2 + seed * 0.1), pressure: 0.8)
            },
            radius: 0.04, feather: 0.5, flow: 0.8, density: 1)
    }

    private func digest(_ strokes: [BrushStroke]) -> String {
        BrushStrokeDigest.definitionDigest(of: BrushMaskDefinition(strokes: strokes))
    }

    func testUnchangedStrokeListKeepsDigestAndDecodedCopyMatches() throws {
        let strokes = [Self.stroke(1), Self.stroke(2)]
        XCTAssertEqual(digest(strokes), digest(strokes))
        let decoded = try JSONDecoder().decode(
            [BrushStroke].self, from: JSONEncoder().encode(strokes))
        XCTAssertEqual(digest(strokes), digest(decoded))
    }

    func testReorderingEditingAndAppendingEachChangeDigest() {
        let a = Self.stroke(1), b = Self.stroke(2)
        let base = digest([a, b])
        XCTAssertNotEqual(base, digest([b, a]))

        var radius = a; radius.radius = 0.07
        var feather = a; feather.feather = 0.9
        var flow = a; flow.flow = 0.3
        var density = a; density.density = 0.4
        for edited in [radius, feather, flow, density] {
            XCTAssertNotEqual(base, digest([edited, b]))
        }

        var appended = b
        appended.samples.append(BrushSample(point: CGPoint(x: 0.9, y: 0.9)))
        XCTAssertNotEqual(base, digest([a, appended]))
        XCTAssertNotEqual(base, digest([a]))
    }

    func testMemoNeverAliasesDistinctStrokesSharingAnID() {
        let first = Self.stroke(1)
        var second = first
        second.radius = 0.09
        XCTAssertNotEqual(
            BrushStrokeDigest.digest(of: first), BrushStrokeDigest.digest(of: second))
        XCTAssertEqual(BrushStrokeDigest.digest(of: first), RenderCacheHash.digest(first))
        XCTAssertEqual(BrushStrokeDigest.digest(of: second), RenderCacheHash.digest(second))
    }

    func testIdentityBrushComponentChangesWithActiveStrokeOnly() {
        let componentID = UUID()
        let committed = Self.stroke(1)
        var active = Self.stroke(2)
        func make() -> EditDocument {
            var d = EditDocument()
            d.localAdjustments = [LocalAdjustmentLayer(
                name: "Brush",
                components: [MaskComponent(
                    id: componentID, name: "Brush", source: .brush(BrushMaskDefinition(strokes: [committed, active])))],
                adjustments: LocalAdjustments(exposure: 0.4))]
            return d
        }
        let before = RenderDocumentIdentity(make())
        active.samples.append(BrushSample(point: CGPoint(x: 0.7, y: 0.7)))
        let after = RenderDocumentIdentity(make())
        XCTAssertNotEqual(before.maskComponents, after.maskComponents)
        XCTAssertNotEqual(before.sessionKey, after.sessionKey)
        XCTAssertEqual(after.maskComponents, RenderDocumentIdentity(make()).maskComponents)
    }

    func testRendererStrokeCacheHitsForUnchangedStrokesWhilePainting() throws {
        let renderer = LocalMaskRenderer()
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let committed = Self.stroke(1)
        var active = Self.stroke(2)
        func render() -> CIImage? {
            let definition = BrushMaskDefinition(strokes: [committed, active])
            let payload = LocalMaskPayload(
                sourceFingerprint: "test", definitionHash: BrushStrokeDigest.definitionDigest(of: definition),
                targetSize: PixelDimensions(width: 64, height: 64), quality: .interactive,
                descriptor: .brush(definition))
            return renderer.image(for: payload, extent: extent, transform: .identity)
        }
        XCTAssertNotNil(render())
        XCTAssertEqual(renderer.diagnosticsSnapshot.cachedBrushStrokeCount, 2)
        active.samples.append(BrushSample(point: CGPoint(x: 0.7, y: 0.7)))
        XCTAssertNotNil(render())
        // The committed stroke's raster is reused; only the active stroke adds an entry.
        XCTAssertEqual(renderer.diagnosticsSnapshot.cachedBrushStrokeCount, 3)
    }

    func testDurableEncodingKeepsRawStrokesAndSessionDigestDoesNot() throws {
        let definition = BrushMaskDefinition(strokes: [Self.stroke(1)])
        let durable = try JSONEncoder().encode(definition)
        let decoded = try JSONDecoder().decode(BrushMaskDefinition.self, from: durable)
        XCTAssertEqual(decoded, definition)
        XCTAssertNotEqual(RenderCacheHash.digest(definition), RenderCacheHash.sessionDigest(definition))
        var edited = definition
        edited.strokes[0].samples.append(BrushSample(point: CGPoint(x: 0.9, y: 0.9)))
        XCTAssertNotEqual(RenderCacheHash.sessionDigest(definition), RenderCacheHash.sessionDigest(edited))
    }

    // MARK: Retention (KRMA-1137)

    func testMemoByteBudgetBoundsRetainedBytesAndEvictsOldestFirst() {
        var memo = BrushStrokeDigest.Memo(byteBudget: 64 * 1024)
        let strokes = (0..<40).map { Self.stroke(Double($0), count: 100) }
        for s in strokes { memo.store(s, digest: RenderCacheHash.digest(s)) }
        XCTAssertLessThanOrEqual(memo.retainedBytes, 64 * 1024)
        XCTAssertLessThan(memo.idCount, strokes.count)
        XCTAssertNil(memo.lookup(strokes[0]))
        XCTAssertEqual(memo.lookup(strokes[39]), RenderCacheHash.digest(strokes[39]))
    }

    func testMemoEvictionKeepsRecentlyUsedStrokes() {
        var memo = BrushStrokeDigest.Memo(byteBudget: 64 * 1024)
        let hot = Self.stroke(0, count: 100)
        memo.store(hot, digest: "hot")
        for n in 1..<60 {
            let s = Self.stroke(Double(n), count: 100)
            memo.store(s, digest: "d\(n)")
            XCTAssertEqual(memo.lookup(hot), "hot", "recently used stroke evicted at \(n)")
        }
    }

    func testMemoDoesNotRetainStrokeLargerThanBudgetAndStaysCorrect() {
        var memo = BrushStrokeDigest.Memo(byteBudget: 4 * 1024)
        let huge = Self.stroke(1, count: 1000)
        memo.store(huge, digest: "x")
        XCTAssertEqual(memo.retainedBytes, 0)
        XCTAssertNil(memo.lookup(huge))
    }

    func testMemoByteBudgetCountsReservedSampleCapacity() {
        var samples: [BrushSample] = []
        samples.reserveCapacity(1000)
        samples.append(BrushSample(point: CGPoint(x: 0.5, y: 0.5)))
        let stroke = BrushStroke(samples: samples)
        XCTAssertGreaterThan(stroke.samples.capacity, stroke.samples.count)

        var memo = BrushStrokeDigest.Memo(byteBudget: 4 * 1024)
        memo.store(stroke, digest: "reserved-capacity")
        XCTAssertEqual(memo.retainedBytes, 0)
        XCTAssertNil(memo.lookup(stroke))
    }

    func testOversizedStrokeDoesNotEvictOtherVersionsWithSameID() {
        var memo = BrushStrokeDigest.Memo(byteBudget: 4 * 1024)
        let recent = Self.stroke(0, count: 8)
        var oversized = Self.stroke(1, count: 1000)
        oversized.id = recent.id

        memo.store(recent, digest: "recent")
        memo.store(oversized, digest: "oversized")
        XCTAssertEqual(memo.lookup(recent), "recent")
        XCTAssertNil(memo.lookup(oversized))
    }

    func testEncodingFailuresRemainUncacheable() {
        BrushStrokeDigest.removeAll()
        var stroke = Self.stroke(1)
        stroke.samples[0].pressure = .nan

        let first = BrushStrokeDigest.digest(of: stroke)
        let second = BrushStrokeDigest.digest(of: stroke)
        XCTAssertTrue(first.hasPrefix("encoding-failed:"))
        XCTAssertTrue(second.hasPrefix("encoding-failed:"))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(BrushStrokeDigest.retained.ids, 0)
    }

    func testMemoIDLimitEvictsWithoutClearingAndDigestsStayExact() {
        var memo = BrushStrokeDigest.Memo(byteBudget: 64 * 1024 * 1024, idLimit: 8)
        let strokes = (0..<30).map { Self.stroke(Double($0)) }
        for s in strokes { memo.store(s, digest: RenderCacheHash.digest(s)) }
        XCTAssertLessThanOrEqual(memo.idCount, 8)
        XCTAssertGreaterThan(memo.idCount, 1)
        // After eviction the public path recomputes the identical digest.
        for s in strokes { XCTAssertEqual(BrushStrokeDigest.digest(of: s), RenderCacheHash.digest(s)) }
    }

    func testMemoEditedStrokeWithSameIDDoesNotAliasAfterEviction() {
        var memo = BrushStrokeDigest.Memo(byteBudget: 64 * 1024)
        let a = Self.stroke(1, count: 50)
        var b = a; b.samples.append(BrushSample(point: CGPoint(x: 0.9, y: 0.9)))
        memo.store(a, digest: "A")
        XCTAssertNil(memo.lookup(b))
        memo.store(b, digest: "B")
        XCTAssertEqual(memo.lookup(a), "A")
        XCTAssertEqual(memo.lookup(b), "B")
    }

    func testBeyondUUIDThresholdRepeatedPaintTicksReuseCommittedDigests() {
        BrushStrokeDigest.removeAll()
        let committed = (0..<5000).map { Self.stroke(Double($0 % 7), count: 4).withID(UUID()) }
        var active = Self.stroke(9, count: 4)
        _ = BrushStrokeDigest.definitionDigest(of: BrushMaskDefinition(strokes: committed + [active]))
        let retained = BrushStrokeDigest.retained
        XCTAssertLessThanOrEqual(retained.ids, BrushStrokeDigest.Memo.idLimit)
        XCTAssertLessThanOrEqual(retained.bytes, BrushStrokeDigest.defaultByteBudget)
        XCTAssertEqual(retained.ids, committed.count + 1, "warm recipe was unexpectedly evicted")
        // Prewarm committed digests, then time ticks that encode only the changed active stroke.
        _ = BrushStrokeDigest.definitionDigest(of: BrushMaskDefinition(strokes: committed + [active]))
        let start = ContinuousClock.now
        for n in 0..<20 {
            active.samples.append(BrushSample(point: CGPoint(x: 0.5, y: Double(n) / 20)))
            _ = BrushStrokeDigest.definitionDigest(of: BrushMaskDefinition(strokes: committed + [active]))
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(BrushStrokeDigest.retained.ids, committed.count + 1)
        print("KRMA-1137 5001-stroke recipe: 20 paint ticks in \(elapsed)")
    }
}

private extension BrushStroke {
    func withID(_ id: UUID) -> BrushStroke { var copy = self; copy.id = id; return copy }
}
