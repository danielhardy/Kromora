import XCTest

@testable import KromoraKit

final class EditDocumentRetentionCostTests: XCTestCase {
    func testEstimateCountsColorRangeSamples() {
        func document(sampleCount: Int) -> EditDocument {
            let samples = (0..<sampleCount).map { index in
                ColorRangeSample(red: Double(index) / 8, green: 0.5, blue: 0.25)
            }
            let component = MaskComponent(source: .color(ColorRangeDefinition(samples: samples)))
            return EditDocument(localAdjustments: [LocalAdjustmentLayer(components: [component])])
        }

        let oneSample = document(sampleCount: 1).estimatedRetentionBytes
        let fourSamples = document(sampleCount: 4).estimatedRetentionBytes

        XCTAssertEqual(
            fourSamples - oneSample,
            3 * MemoryLayout<ColorRangeSample>.stride
        )
    }

    func testEstimateCountsAutoFingerprintStringsByUTF8Length() {
        let baseline = EditDocument().estimatedRetentionBytes
        let document = EditDocument(lastAutoRunFingerprint: AutoRunFingerprint(
            sourceFingerprint: "é",
            documentHash: "hash",
            renderIdentity: "v"
        ))

        XCTAssertEqual(document.estimatedRetentionBytes - baseline, 7)
    }
}
