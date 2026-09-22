import XCTest
import CoreGraphics
@testable import KromoraKit

final class AutoEnhancementResultTests: TempDirectoryTestCase {
    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: "auto-result.png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 48))
    }

    func testResultAndOwnershipMetadataRoundTrip() throws {
        let layer = LocalAdjustmentLayer(
            name: AutoRegionalPurpose.subjectLift.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 0.35),
            ownership: .auto,
            autoProvenance: AutoLayerProvenance(
                purpose: .subjectLift, algorithmVersion: 7, generationID: "run-1"
            )
        )
        let document = EditDocument(localAdjustments: [layer])
        let result = AutoEnhancementResult(
            proposedDocument: document,
            algorithmVersion: 7,
            changedControls: [.exposure],
            confidence: 0.8,
            reasons: ["regional conflict"],
            validationMeasurements: AutoValidationMeasurements(globalExposure: 0.03, score: 0.2),
            candidateProvenance: .native,
            fingerprint: AutoRunFingerprint(
                sourceFingerprint: "source", documentHash: document.renderingHash,
                algorithmVersion: 7, renderIdentity: "renderer-test"
            ),
            generatedLayerIDs: [layer.id]
        )

        let decoded = try JSONDecoder().decode(
            AutoEnhancementResult.self,
            from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.proposedDocument.localAdjustments.first?.ownership, .auto)
        XCTAssertEqual(decoded.proposedDocument.localAdjustments.first?.autoProvenance?.purpose, .subjectLift)
        XCTAssertFalse(decoded.isNoOp)
    }

    func testLegacyDocumentsUseNeutralAutoMetadata() throws {
        let legacy = Data("""
        {"version":3,"rawDevelop":{},"light":{},"color":{},"effects":{},"crop":{},
         "adjustments":[],"lut":{"lutID":null,"intensity":1},"localAdjustments":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: legacy)
        XCTAssertNil(decoded.lastAutoRunFingerprint)
        XCTAssertEqual(decoded.version, EditDocument.currentVersion)

        let layer = try JSONDecoder().decode(
            LocalAdjustmentLayer.self,
            from: Data("""
            {"id":"\(UUID().uuidString)","name":"old","components":[],"adjustments":{}}
            """.utf8)
        )
        XCTAssertEqual(layer.ownership, .user)
        XCTAssertNil(layer.autoProvenance)
    }

    func testFingerprintChangesForSourceDocumentAlgorithmAndRenderer() throws {
        let image = try source()
        let document = EditDocument()
        let fingerprint = AutoRunFingerprint.make(
            source: image, document: document, algorithmVersion: 4, renderIdentity: "r1"
        )
        XCTAssertTrue(fingerprint.matches(
            source: image, document: document, algorithmVersion: 4, renderIdentity: "r1"
        ))
        XCTAssertFalse(fingerprint.matches(
            source: image, document: EditDocument(light: LightAdjustments(exposure: 0.1)),
            algorithmVersion: 4, renderIdentity: "r1"
        ))
        XCTAssertFalse(fingerprint.matches(
            source: image, document: document, algorithmVersion: 5, renderIdentity: "r1"
        ))
        XCTAssertFalse(fingerprint.matches(
            source: image, document: document, algorithmVersion: 4, renderIdentity: "r2"
        ))

        var metadataOnly = document
        metadataOnly.lastAutoRunFingerprint = fingerprint
        XCTAssertEqual(
            metadataOnly.editHash, document.editHash,
            "review metadata must not invalidate the render identity"
        )
    }

    func testManualEditReleasesAutoLayerAndClearsFingerprint() {
        let layer = LocalAdjustmentLayer(
            name: AutoRegionalPurpose.subjectLift.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 0.3),
            ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
        let old = EditDocument(
            localAdjustments: [layer],
            lastAutoRunFingerprint: AutoRunFingerprint(
                sourceFingerprint: "s", documentHash: "d", renderIdentity: "r"
            )
        )
        var editedLayer = layer
        editedLayer.adjustments.exposure = 0.5
        let updated = EditDocument.markingManualEdits(
            from: old, to: EditDocument(localAdjustments: [editedLayer], lastAutoRunFingerprint: old.lastAutoRunFingerprint)
        )
        XCTAssertEqual(updated.localAdjustments.first?.ownership, .user)
        XCTAssertEqual(updated.localAdjustments.first?.autoProvenance?.purpose, .subjectLift)
        XCTAssertNil(updated.lastAutoRunFingerprint)
        XCTAssertEqual(updated.localAdjustments.first?.adjustments.exposure, 0.5)
    }

    func testProtectedUserLayerIsNotDuplicatedByLaterAutoResult() {
        let generated = LocalAdjustmentLayer(
            name: AutoRegionalPurpose.subjectLift.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 0.2), ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
        var userLayer = generated
        userLayer.adjustments.exposure = 0.8
        userLayer.markUserOwned()

        var replacement = generated
        replacement.adjustments.exposure = 0.1
        let result = AutoEnhancementResult(
            proposedDocument: EditDocument(localAdjustments: [replacement]),
            changedControls: [.exposure]
        )
        let applied = result.applying(to: EditDocument(localAdjustments: [userLayer]))

        XCTAssertEqual(applied.localAdjustments.count, 1)
        XCTAssertEqual(applied.localAdjustments[0].ownership, .user)
        XCTAssertEqual(applied.localAdjustments[0].adjustments.exposure, 0.8)
        XCTAssertEqual(applied.localAdjustments[0].autoProvenance?.purpose, .subjectLift)
    }

    func testFingerprintMatchesDocumentAfterExistingAutoLayerIsReused() throws {
        let image = try source()
        let existing = LocalAdjustmentLayer(
            id: UUID(), name: AutoRegionalPurpose.subjectLift.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 0.2), ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
        var candidateLayer = existing
        candidateLayer.id = UUID()
        candidateLayer.adjustments.exposure = 0.6
        let candidate = EditDocument(localAdjustments: [candidateLayer])
        let result = AutoEnhancementResult(
            proposedDocument: candidate,
            changedControls: [.exposure],
            fingerprint: AutoRunFingerprint(
                sourceFingerprint: image.cacheFingerprint,
                documentHash: candidate.renderingHash,
                algorithmVersion: 9,
                renderIdentity: "renderer-test"
            )
        )

        let applied = result.applying(to: EditDocument(localAdjustments: [existing]))
        XCTAssertEqual(applied.localAdjustments.first?.id, existing.id)
        XCTAssertTrue(applied.lastAutoRunFingerprint?.matches(
            source: image, document: applied, algorithmVersion: 9,
            renderIdentity: "renderer-test"
        ) == true)
    }

    func testAutoAndUserOwnedLayersSurviveRecordSaveAndReopen() throws {
        let autoLayer = LocalAdjustmentLayer(
            name: AutoRegionalPurpose.subjectLift.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 0.3), ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift, generationID: "run-1")
        )
        let userLayer = LocalAdjustmentLayer(
            name: "My mask",
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .background)))],
            adjustments: LocalAdjustments(highlights: -20)
        )
        let document = EditDocument(localAdjustments: [autoLayer, userLayer])
        let reopened = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(document)
        )
        XCTAssertEqual(reopened.localAdjustments, document.localAdjustments)
        XCTAssertEqual(reopened.localAdjustments[0].ownership, .auto)
        XCTAssertEqual(reopened.localAdjustments[1].ownership, .user)
    }

    func testAutoResultReusesExistingAutoLayerButProtectsUserLayer() {
        let auto = LocalAdjustmentLayer(
            id: UUID(), name: AutoRegionalPurpose.subjectLift.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 0.2), ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
        let user = LocalAdjustmentLayer(
            name: AutoRegionalPurpose.backgroundProtection.layerName,
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .background)))],
            adjustments: LocalAdjustments(highlights: -10)
        )
        var replacement = auto
        replacement.adjustments.exposure = 0.6
        let result = AutoEnhancementResult(
            proposedDocument: EditDocument(localAdjustments: [replacement]),
            changedControls: [.exposure],
            fingerprint: AutoRunFingerprint(sourceFingerprint: "s", documentHash: "h")
        )
        let applied = EditDocument.applyingAutoResult(
            result, to: EditDocument(localAdjustments: [auto, user])
        )
        XCTAssertEqual(applied.localAdjustments.count, 2)
        XCTAssertEqual(applied.localAdjustments[0].id, auto.id)
        XCTAssertEqual(applied.localAdjustments[0].adjustments.exposure, 0.6)
        XCTAssertEqual(applied.localAdjustments[1], user)
    }
}
