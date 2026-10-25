import XCTest

@testable import KromoraKit

/// KRMA-1098: `editHash` is the durable cross-launch identity, so its bytes are pinned; the
/// in-memory change checks use `==` and must keep the same Auto-metadata exclusion.
final class EditDocumentIdentityTests: XCTestCase {
    private func fixture(fingerprint: AutoRunFingerprint? = nil) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = 0.3
        document.light.contrast = 12
        document.color.vibrance = 10
        document.lut = LUTSettings(lutID: LUTID(raw: "golden-look"), intensity: 0.6)
        let stroke = BrushStroke(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            samples: (0..<8).map {
                BrushSample(
                    point: CGPoint(x: 0.1 * Double($0), y: 0.5), pressure: 0.5 + 0.05 * Double($0))
            },
            radius: 0.04, feather: 0.5, flow: 0.8, density: 1)
        document.localAdjustments = [
            LocalAdjustmentLayer(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Brush",
                components: [
                    MaskComponent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                        name: "Brush",
                        source: .brush(BrushMaskDefinition(strokes: [stroke])))
                ],
                adjustments: LocalAdjustments(exposure: 0.4))
        ]
        document.lastAutoRunFingerprint = fingerprint
        return document
    }

    func testEditHashGoldenIsStable() {
        XCTAssertEqual(
            fixture().editHash,
            "41715f91641cbe0a84a4e25f63bc295843c05380451d9328d60909d333335b70", "the durable editHash scheme changed; see docs/RENDER_KEY_PLAN.md")
    }

    func testEditHashExcludesAutoFingerprint() {
        let fingerprint = AutoRunFingerprint(
            sourceFingerprint: "s", documentHash: "d", renderIdentity: "r")
        XCTAssertEqual(fixture(fingerprint: fingerprint).editHash, fixture().editHash)
        XCTAssertTrue(fixture(fingerprint: fingerprint).hasSameVisibleEdits(as: fixture()))
    }

    func testEqualDocumentsShareIdentityAndEachFieldChangesIt() {
        let base = fixture()
        XCTAssertEqual(base.editHash, fixture().editHash)
        XCTAssertTrue(base.hasSameVisibleEdits(as: fixture()))
        let edits: [(String, (inout EditDocument) -> Void)] = [
            ("version", { $0.version += 1 }),
            ("rawDevelop", { $0.rawDevelop.exposure = 0.25 }),
            ("light", { $0.light.exposure += 0.01 }),
            ("color", { $0.color.vibrance += 1 }),
            ("effects", { $0.effects.texture = 1 }),
            ("crop", { $0.crop.flipHorizontal = true }),
            ("rotation", { $0.rotation = .clockwise90 }),
            ("adjustments", { $0.adjustments = [.exposure(ev: 0.1)] }),
            ("lut", { $0.lut.intensity = 0.2 }),
            ("mask", { $0.localAdjustments[0].adjustments.exposure = 0.9 }),
            ("retouch", { $0.retouch = RetouchSettings(spots: [RetouchSpot(seed: 1)]) }),
        ]
        for (name, edit) in edits {
            var changed = base
            edit(&changed)
            XCTAssertFalse(base.hasSameVisibleEdits(as: changed), name)
            XCTAssertNotEqual(base.editHash, changed.editHash, name)
        }
    }

    func testMarkingManualEditsKeepsFingerprintWhenOnlyFingerprintDiffers() {
        let fingerprint = AutoRunFingerprint(
            sourceFingerprint: "s", documentHash: "d", renderIdentity: "r")
        let old = fixture(fingerprint: fingerprint)
        XCTAssertEqual(
            EditDocument.markingManualEdits(from: old, to: fixture(fingerprint: fingerprint))
                .lastAutoRunFingerprint, fingerprint)
        var edited = old
        edited.light.exposure += 0.1
        XCTAssertNil(EditDocument.markingManualEdits(from: old, to: edited).lastAutoRunFingerprint)
    }

    /// KRMA-1099: a 30-tick drag with every durable consumer reading the hash computes one digest
    /// per distinct document value, and the bytes match the uncached digest.
    func testMemoComputesOneDigestPerDistinctDocumentDuringDrag() {
        let memo = DurableEditIdentityMemo()
        var document = fixture()
        for tick in 0..<30 {
            document.light.exposure = 0.01 * Double(tick)
            // Preview classification, canonical write, thumbnail, Look strip, Auto, measurement.
            let digests = (0..<6).map { _ in memo.digest(for: document) }
            XCTAssertEqual(Set(digests).count, 1)
            XCTAssertEqual(digests[0], RenderCacheHash.digest(document.visibleEditValue))
        }
        XCTAssertEqual(memo.computationCount, 30)
    }

    func testMemoIgnoresAutoFingerprintAndSurvivesEviction() {
        let memo = DurableEditIdentityMemo(capacity: 2)
        let fingerprint = AutoRunFingerprint(
            sourceFingerprint: "s", documentHash: "d", renderIdentity: "r")
        _ = memo.digest(for: fixture())
        _ = memo.digest(for: fixture(fingerprint: fingerprint))
        XCTAssertEqual(memo.computationCount, 1)
        for index in 1...3 {
            var other = fixture()
            other.light.exposure = Double(index)
            _ = memo.digest(for: other)
        }
        XCTAssertNil(memo.cachedDigest(for: fixture()))
        XCTAssertEqual(
            memo.digest(for: fixture()),
            "41715f91641cbe0a84a4e25f63bc295843c05380451d9328d60909d333335b70")
    }

    /// KRMA-1099: simultaneous consumers of one new document value share a single computation.
    func testConcurrentMissesCoalesceIntoOneDigest() async {
        let memo = DurableEditIdentityMemo()
        let document = fixture()
        let digests = await withTaskGroup(of: String.self) { group in
            for index in 0..<16 {
                group.addTask {
                    index.isMultiple(of: 2)
                        ? memo.digest(for: document) : await memo.digestOffCaller(for: document)
                }
            }
            return await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        XCTAssertEqual(digests.count, 1)
        XCTAssertEqual(memo.computationCount, 1)
    }

    func testDigestOffCallerMatchesSynchronousDigest() async {
        let memo = DurableEditIdentityMemo()
        let document = fixture()
        let off = await memo.digestOffCaller(for: document)
        XCTAssertEqual(off, RenderCacheHash.digest(document.visibleEditValue))
        XCTAssertEqual(memo.cachedDigest(for: document), off)
        XCTAssertEqual(memo.computationCount, 1)
    }

    /// KRMA-1099: a frame signed with the pre-memo golden digest, round-tripped through its
    /// persisted encoding, still classifies exact against the memoized hash of the same document.
    func testStoredFrameWithGoldenHashClassifiesExactAfterRoundTrip() throws {
        let golden = "41715f91641cbe0a84a4e25f63bc295843c05380451d9328d60909d333335b70"
        let identity = FrameFixtures.identity()
        let stored = FrameFixtures.metadata(identity: identity, edit: golden)
        let decoded = try JSONDecoder().decode(
            PresentationFrameMetadata.self, from: JSONEncoder().encode(stored))
        let inputs = FrameCurrentInputs(
            source: identity, editHash: fixture().editHash, look: LookSignature.none,
            workingSpace: .current)
        XCTAssertEqual(FrameClassifier.classify(decoded, against: inputs), .exact)
        var edited = fixture()
        edited.light.exposure += 0.01
        let staleInputs = FrameCurrentInputs(
            source: identity, editHash: edited.editHash, look: LookSignature.none,
            workingSpace: .current)
        XCTAssertNotEqual(FrameClassifier.classify(decoded, against: staleInputs), .exact)
    }
}
