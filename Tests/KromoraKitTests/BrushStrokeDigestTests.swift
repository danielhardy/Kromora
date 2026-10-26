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
}
