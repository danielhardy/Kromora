import CoreGraphics
import XCTest

@testable import KromoraKit

final class MaskPresentationPolicyTests: XCTestCase {
    func testOverlayOpacityOnlyControlsCoverageAndToolingStaysOpaque() {
        let low = MaskOverlayPresentation(coverageOpacity: 0.08)
        let high = MaskOverlayPresentation(coverageOpacity: 0.8)

        XCTAssertEqual(low.coverageOpacity, 0.08, accuracy: 0.000_001)
        XCTAssertEqual(high.coverageOpacity, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(low.toolingOpacity, 1)
        XCTAssertEqual(high.toolingOpacity, 1)
    }

    func testStrongSubjectIsActionable() {
        XCTAssertEqual(MaskPresentationPolicy.decision(for: makeMask(.subject, confidence: 0.9, coverage: 0.2)), .actionable)
    }

    func testWeakAndEmptySubjectsAreFilteredWithDifferentReasons() {
        XCTAssertEqual(MaskPresentationPolicy.decision(for: makeMask(.subject, confidence: 0.4, coverage: 0.2)), .lowConfidence)
        XCTAssertEqual(MaskPresentationPolicy.decision(for: makeMask(.subject, confidence: 0.9, coverage: 0)), .empty)
    }

    func testUsefulBackgroundRemainsActionableWhenSubjectIsAbsent() {
        XCTAssertEqual(MaskPresentationPolicy.decision(for: makeMask(.background, confidence: 1, coverage: 1)), .actionable)
    }

    private func makeMask(_ kind: SemanticMaskKind, confidence: Float, coverage: Float) -> RegionMask {
        let source = Data("mask-policy".utf8)
        let key = MaskCacheKey(
            assetID: .data(source), sourceFingerprint: .data(source), kind: kind, quality: .preview,
            providerVersion: "policy-test"
        )
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: RegionMaskReference(cacheKey: key, size: PixelDimensions(width: 1, height: 1)),
            confidence: confidence,
            coverage: coverage
        )
    }
}
