import Foundation
import XCTest

@testable import KromoraKit

final class RegionRelationshipsTests: XCTestCase {
    func testDarkSubjectBrightBackgroundUsesSignedPerceptualDeltas() {
        let subjectID = UUID()
        let subject = region(
            id: subjectID, kind: .foregroundInstance(0), mean: 0.2,
            bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.5)
        )
        let background = region(
            kind: .background, mean: 0.8,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )
        let relationships = RegionRelationships.make(
            globalTone: ToneStatistics(variant: .perceptual, mean: 0.6),
            regions: [subject, background],
            primarySubject: PrimarySubjectSelection(primaryRegionID: subjectID, confidence: 0.9)
        )

        XCTAssertEqual(relationships.subjectToGlobalLuminanceDelta!, -0.4, accuracy: 0.0001)
        XCTAssertEqual(relationships.subjectToBackgroundLuminanceDelta!, -0.6, accuracy: 0.0001)
        XCTAssertEqual(relationships.subjectContrast!, 0.6, accuracy: 0.0001)
        XCTAssertEqual(relationships.backgroundContrast!, 0.2, accuracy: 0.0001)
        XCTAssertNil(relationships.faceToSubjectLuminanceDelta)
    }

    func testFaceRelationshipsRemainNilWithoutFaceButSubjectRelationshipsRemain() {
        let subjectID = UUID()
        let subject = region(id: subjectID, kind: .person, mean: 0.4)
        let relationships = RegionRelationships.make(
            globalTone: ToneStatistics(variant: .perceptual, mean: 0.5),
            regions: [subject],
            primarySubject: PrimarySubjectSelection(primaryRegionID: subjectID, confidence: 0.8)
        )

        XCTAssertEqual(relationships.subjectToGlobalLuminanceDelta!, -0.1, accuracy: 0.0001)
        XCTAssertNil(relationships.subjectToBackgroundLuminanceDelta)
        XCTAssertNil(relationships.faceToSubjectLuminanceDelta)
        XCTAssertNil(relationships.faceToBackgroundLuminanceDelta)
    }

    func testNoPrimarySubjectProducesNoFabricatedRelationships() {
        let relationships = RegionRelationships.make(
            globalTone: ToneStatistics(variant: .perceptual, mean: 0.5),
            regions: [region(kind: .background, mean: 0.9)],
            primarySubject: .none
        )
        XCTAssertEqual(relationships, .unavailable)
    }

    private func region(
        id: UUID = UUID(), kind: SemanticMaskKind, mean: Float, bounds: NormalizedRect? = nil
    ) -> AnalyzedRegion {
        let bytes = Data("relationship-\(id.uuidString)".utf8)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(bytes), sourceFingerprint: PhotoSourceFingerprint.data(bytes),
            kind: kind
        )
        return AnalyzedRegion(
            id: id, kind: kind,
            mask: RegionMaskReference(cacheKey: key, size: PixelDimensions(width: 1, height: 1)),
            bounds: bounds, confidence: 1, importance: 1,
            tone: ToneStatistics(variant: .perceptual, mean: mean),
            color: .neutral, coverage: 0.5
        )
    }
}
