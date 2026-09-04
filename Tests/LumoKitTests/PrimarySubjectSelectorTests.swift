import Foundation
import XCTest

@testable import LumoKit

final class PrimarySubjectSelectorTests: XCTestCase {
    func testSingleDominantRegionProducesHighConfidencePick() throws {
        let subjectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let subjectBounds = NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let regions = [
            makeRegion(
                id: subjectID, kind: .foregroundInstance(0), confidence: 0.95,
                coverage: 0.25, bounds: subjectBounds
            ),
            makeRegion(
                id: UUID(), kind: .subject, confidence: 0.95, coverage: 0.25,
                bounds: subjectBounds
            ),
        ]

        let selection = PrimarySubjectSelector.select(from: regions)

        XCTAssertEqual(selection.primaryRegionID, subjectID)
        XCTAssertGreaterThan(selection.confidence, 0.8)
        XCTAssertEqual(selection.secondaryRegionIDs.count, 0)
    }

    func testSimilarCandidatesAreDeterministicAndLowerConfidence() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))
        let firstBounds = NormalizedRect(x: 0.17, y: 0.17, width: 0.28, height: 0.28)
        let secondBounds = NormalizedRect(x: 0.55, y: 0.55, width: 0.28, height: 0.28)
        let subjectBounds = NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        let regions = [
            makeRegion(
                id: firstID, kind: .foregroundInstance(0), confidence: 0.9,
                coverage: 0.2, bounds: firstBounds),
            makeRegion(
                id: secondID, kind: .foregroundInstance(1), confidence: 0.9,
                coverage: 0.2, bounds: secondBounds),
            makeRegion(
                id: UUID(), kind: .subject, confidence: 0.9,
                coverage: 0.4, bounds: subjectBounds),
        ]

        let forward = PrimarySubjectSelector.select(from: regions)
        let reversed = PrimarySubjectSelector.select(from: Array(regions.reversed()))

        XCTAssertEqual(forward.primaryRegionID, firstID)
        XCTAssertEqual(reversed.primaryRegionID, firstID)
        XCTAssertEqual(forward.rankedSubjects, reversed.rankedSubjects)
        XCTAssertLessThan(forward.confidence, 0.8)
        XCTAssertEqual(forward.secondaryRegionIDs, [secondID])
    }

    func testNoSubjectEvidenceDoesNotForceBackgroundOrUnknownPick() {
        let regions = [
            makeRegion(kind: .background, confidence: 1, coverage: 0.8),
            makeRegion(kind: .unknown("sky"), confidence: 1, coverage: 0.2),
        ]

        let selection = PrimarySubjectSelector.select(from: regions)

        XCTAssertNil(selection.primaryRegionID)
        XCTAssertEqual(selection.confidence, 0)
        XCTAssertTrue(selection.rankedSubjects.isEmpty)
    }

    func testWeakSaliencyRemainsVeryLowConfidence() {
        let region = makeRegion(
            kind: .subject, confidence: 0.05, coverage: 0.01,
            bounds: NormalizedRect(x: 0.33, y: 0.33, width: 0.1, height: 0.1)
        )

        let selection = PrimarySubjectSelector.select(from: [region])

        XCTAssertEqual(selection.primaryRegionID, region.id)
        XCTAssertLessThan(selection.confidence, 0.1)
    }

    func testRepeatedSelectionOfNearIdenticalInputIsStable() {
        let first = makeRegion(
            kind: .foregroundInstance(0), confidence: 0.8, coverage: 0.21,
            bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.25, height: 0.25)
        )
        let second = makeRegion(
            kind: .foregroundInstance(1), confidence: 0.79, coverage: 0.2,
            bounds: NormalizedRect(x: 0.6, y: 0.6, width: 0.25, height: 0.25)
        )
        let regions = [first, second]

        let selections = (0..<20).map { _ in PrimarySubjectSelector.select(from: regions) }

        XCTAssertTrue(selections.allSatisfy { $0.primaryRegionID == first.id })
        XCTAssertTrue(selections.dropFirst().allSatisfy { $0 == selections[0] })
    }

    private func makeRegion(
        id: UUID = UUID(),
        kind: SemanticMaskKind,
        confidence: Float,
        coverage: Float,
        bounds: NormalizedRect? = nil
    ) -> AnalyzedRegion {
        let source = Data("primary-subject-selector".utf8)
        let key = MaskCacheKey(
            assetID: .data(source), sourceFingerprint: .data(source), kind: kind
        )
        let reference = RegionMaskReference(
            cacheKey: key, size: PixelDimensions(width: 10, height: 10)
        )
        return AnalyzedRegion(
            id: id, kind: kind, mask: reference, bounds: bounds,
            confidence: confidence, importance: confidence * coverage,
            tone: .neutral, color: .neutral, coverage: coverage
        )
    }
}
