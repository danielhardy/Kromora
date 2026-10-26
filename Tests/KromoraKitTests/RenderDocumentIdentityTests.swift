import CoreGraphics
import XCTest

@testable import KromoraKit

final class RenderDocumentIdentityTests: XCTestCase {
    private static func brushDocument() -> EditDocument {
        var document = EditDocument()
        document.light.exposure = 0.3
        let samples = (0..<16).map {
            BrushSample(point: CGPoint(x: 0.1 + Double($0) * 0.05, y: 0.5), pressure: 0.8)
        }
        document.localAdjustments = [
            LocalAdjustmentLayer(
                name: "Brush",
                components: [MaskComponent(
                    name: "Brush",
                    source: .brush(BrushMaskDefinition(strokes: [
                        BrushStroke(samples: samples, radius: 0.04, feather: 0.5, flow: 0.8, density: 1)
                    ])))],
                adjustments: LocalAdjustments(exposure: 0.4))
        ]
        return document
    }

    private static func identity(_ content: String) -> PortablePhotoIdentity {
        PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(),
            sourceFingerprint: .data(Data(content.utf8), decoderVersion: "test"))
    }

    private let source = RenderSourceFingerprint(identity: RenderDocumentIdentityTests.identity("a"))

    func testEqualDocumentsGiveEqualIdentitiesIncludingDecodedCopy() throws {
        let document = Self.brushDocument()
        let decoded = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(RenderDocumentIdentity(document), RenderDocumentIdentity(decoded))
        var memo = RenderDocumentIdentityMemo()
        let first = memo.identity(for: document, source: source)
        XCTAssertEqual(first, memo.identity(for: decoded, source: source))
    }

    func testEachComponentEditChangesOnlyItsDigestAndSessionKey() {
        let base = Self.brushDocument()
        let baseID = RenderDocumentIdentity(base)

        var raw = base
        raw.rawDevelop.exposure = (raw.rawDevelop.exposure ?? 0) + 0.5
        var light = base
        light.light.exposure += 0.5
        var white = base
        white.adjustments = [.temperatureTint(temp: 5000, tint: 3)]
        var local = base
        local.localAdjustments[0].adjustments.exposure += 0.2
        var mask = base
        mask.localAdjustments[0].components[0].isInverted.toggle()
        var crop = base
        crop.rotation = .clockwise90

        let rawID = RenderDocumentIdentity(raw)
        XCTAssertNotEqual(rawID.rawDevelop, baseID.rawDevelop)
        XCTAssertEqual(rawID.prefixUpstream, baseID.prefixUpstream)
        XCTAssertEqual(rawID.localAdjustments, baseID.localAdjustments)
        XCTAssertNotEqual(rawID.sessionKey, baseID.sessionKey)

        let lightID = RenderDocumentIdentity(light)
        XCTAssertNotEqual(lightID.prefixUpstream, baseID.prefixUpstream)
        XCTAssertNotEqual(lightID.prefixUpstreamWithoutWhiteBalance, baseID.prefixUpstreamWithoutWhiteBalance)
        XCTAssertEqual(lightID.rawDevelop, baseID.rawDevelop)
        XCTAssertEqual(lightID.localAdjustments, baseID.localAdjustments)
        XCTAssertEqual(lightID.maskComponents, baseID.maskComponents)
        XCTAssertNotEqual(lightID.sessionKey, baseID.sessionKey)

        let whiteID = RenderDocumentIdentity(white)
        XCTAssertNotEqual(whiteID.prefixUpstream, baseID.prefixUpstream)
        XCTAssertEqual(whiteID.prefixUpstreamWithoutWhiteBalance, baseID.prefixUpstreamWithoutWhiteBalance)
        XCTAssertNotEqual(whiteID.sessionKey, baseID.sessionKey)

        let localID = RenderDocumentIdentity(local)
        XCTAssertNotEqual(localID.localAdjustments, baseID.localAdjustments)
        XCTAssertEqual(localID.maskRecipe, baseID.maskRecipe)
        XCTAssertEqual(localID.maskComponents, baseID.maskComponents)
        XCTAssertEqual(localID.prefixUpstream, baseID.prefixUpstream)
        XCTAssertNotEqual(localID.sessionKey, baseID.sessionKey)

        let maskID = RenderDocumentIdentity(mask)
        XCTAssertNotEqual(maskID.maskRecipe, baseID.maskRecipe)
        XCTAssertNotEqual(maskID.localAdjustments, baseID.localAdjustments)
        XCTAssertNotEqual(maskID.sessionKey, baseID.sessionKey)

        let remainderID = RenderDocumentIdentity(crop)
        XCTAssertNotEqual(remainderID.sessionKey, baseID.sessionKey)
        XCTAssertEqual(remainderID.prefixUpstream, baseID.prefixUpstream)

        var brushEdit = base
        if case .brush(var definition) = brushEdit.localAdjustments[0].components[0].source {
            definition.strokes[0].radius += 0.01
            brushEdit.localAdjustments[0].components[0].source = .brush(definition)
        }
        let brushID = RenderDocumentIdentity(brushEdit)
        let baseComponent = base.localAdjustments[0].components[0]
        let editedComponent = brushEdit.localAdjustments[0].components[0]
        XCTAssertNotEqual(
            brushID.maskComponents.definitionHash(for: editedComponent),
            baseID.maskComponents.definitionHash(for: baseComponent)
        )
    }

    func testDuplicateComponentIDsKeepDistinctDefinitionDigests() {
        var document = Self.brushDocument()
        var second = document.localAdjustments[0].components[0]
        if case .brush(var definition) = second.source {
            definition.strokes[0].radius += 0.04
            second.source = .brush(definition)
        }
        document.localAdjustments.append(LocalAdjustmentLayer(components: [second]))

        let first = document.localAdjustments[0].components[0]
        let secondInDocument = document.localAdjustments[1].components[0]
        XCTAssertEqual(first.id, secondInDocument.id)

        var memo = RenderDocumentIdentityMemo()
        let identity = memo.identity(for: document, source: source)
        XCTAssertNotEqual(
            identity.maskComponents.definitionHash(for: first),
            identity.maskComponents.definitionHash(for: secondInDocument)
        )
        XCTAssertEqual(identity, memo.identity(for: document, source: source))
    }

    func testMemoMissMatchesColdBuildAndTickReusesUnchangedComponents() {
        var memo = RenderDocumentIdentityMemo()
        let base = Self.brushDocument()
        XCTAssertEqual(memo.identity(for: base, source: source), RenderDocumentIdentity(base))

        var ticked = base
        ticked.light.exposure += 0.1
        let warm = memo.identity(for: ticked, source: source)
        XCTAssertEqual(warm, RenderDocumentIdentity(ticked))

        // A different source has no remembered entries, so it is a full miss with the same result.
        let other = RenderSourceFingerprint(identity: Self.identity("b"))
        XCTAssertEqual(memo.identity(for: ticked, source: other), warm)
    }

    func testNaNFieldNeverReusesIdentity() {
        // Light clamps NaN away, so use a raw geometry field the model does not normalize.
        var document = Self.brushDocument()
        if case .brush(var definition) = document.localAdjustments[0].components[0].source {
            definition.strokes[0].samples[0].point.x = .nan
            document.localAdjustments[0].components[0].source = .brush(definition)
        }
        var memo = RenderDocumentIdentityMemo()
        let first = memo.identity(for: document, source: source)
        let second = memo.identity(for: document, source: source)
        XCTAssertNotNil(first.maskComponents.definitionHash(for: document.localAdjustments[0].components[0]))
        XCTAssertNotEqual(
            first.maskComponents.entries[0].definitionHash,
            second.maskComponents.entries[0].definitionHash
        )
        XCTAssertNotEqual(first.localAdjustments, second.localAdjustments)
        XCTAssertNotEqual(first.sessionKey, second.sessionKey)
    }

    func testMemoIsBounded() {
        var memo = RenderDocumentIdentityMemo()
        var document = EditDocument()
        for tick in 0..<(RenderDocumentIdentityMemo.entriesPerSource * 3) {
            document.light.exposure = Double(tick) / 10
            _ = memo.identity(for: document, source: source)
        }
        XCTAssertEqual(memo.entryCount(for: source), RenderDocumentIdentityMemo.entriesPerSource)
    }

    /// Reuse by `==` assumes no type reachable from `EditDocument` has a custom `==` that ignores a
    /// pixel-affecting field. Representative edits to every field must make documents unequal.
    func testEditDocumentEqualityObservesRepresentativeFieldEdits() {
        let base = Self.brushDocument()
        let edits: [(String, (inout EditDocument) -> Void)] = [
            ("rawDevelop", { $0.rawDevelop.exposure = ($0.rawDevelop.exposure ?? 0) + 1 }),
            ("light", { $0.light.exposure += 1 }),
            ("color", { $0.color.vibrance += 5 }),
            ("effects", { $0.effects.texture += 5 }),
            ("vignette", { $0.effects.vignette.amount += 5 }),
            ("crop", { $0.crop.straightenAngle += 2 }),
            ("rotation", { $0.rotation = .clockwise90 }),
            ("adjustments", { $0.adjustments = [.temperatureTint(temp: 4000, tint: 0)] }),
            ("lut", { $0.lut.intensity = 0.5 }),
            ("localAdjustments", { $0.localAdjustments[0].adjustments.exposure += 1 }),
            ("mask source", { $0.localAdjustments[0].components[0].isInverted.toggle() }),
        ]
        for (name, edit) in edits {
            var edited = base
            edit(&edited)
            XCTAssertNotEqual(edited, base, "== ignored a \(name) edit")
        }
    }

    func testIdentityIsNotCodable() {
        XCTAssertFalse((RenderDocumentIdentity.self as Any) is Encodable.Type)
        XCTAssertFalse((RenderDocumentIdentity.self as Any) is Decodable.Type)
    }
}
