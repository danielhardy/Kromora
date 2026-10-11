import Foundation
import XCTest

@testable import KromoraKit

final class MaskOverlayIdentityTests: XCTestCase {
    func testAdjustmentValuesDoNotChangeOverlayIdentity() {
        let layer = Self.layer()
        let cases: [(String, WritableKeyPath<LocalAdjustments, Double>, Double)] = [
            ("exposure", \.exposure, 1),
            ("contrast", \.contrast, 1),
            ("highlights", \.highlights, 1),
            ("shadows", \.shadows, 1),
            ("whites", \.whites, 1),
            ("blacks", \.blacks, 1),
            ("temperature", \.temperature, 7000),
            ("tint", \.tint, 1),
            ("saturation", \.saturation, 1),
            ("vibrance", \.vibrance, 1),
            ("texture", \.texture, 1),
            ("clarity", \.clarity, 1),
            ("dehaze", \.dehaze, 1),
            ("sharpness", \.sharpness, 1),
            ("noiseReduction", \.noiseReduction, 1),
            ("moireReduction", \.moireReduction, 1)
        ]

        for (name, keyPath, value) in cases {
            var changed = layer
            changed.adjustments[keyPath: keyPath] = value
            XCTAssertEqual(
                changed.overlayIdentity, layer.overlayIdentity,
                "Changing the local adjustment \(name) must not restart mask overlay resolution."
            )
        }
    }

    func testNameAndAutoProvenanceDoNotChangeOverlayIdentity() {
        let layer = Self.layer()

        var renamed = layer
        renamed.name = "Sky"
        XCTAssertEqual(renamed.overlayIdentity, layer.overlayIdentity)

        var provenanceAdded = layer
        provenanceAdded.autoProvenance = AutoLayerProvenance(purpose: .subjectLift)
        XCTAssertEqual(provenanceAdded.overlayIdentity, layer.overlayIdentity)

        var provenanceChanged = provenanceAdded
        provenanceChanged.autoProvenance = AutoLayerProvenance(
            purpose: .backgroundProtection, algorithmVersion: 2, generationID: "next-run"
        )
        XCTAssertEqual(provenanceChanged.overlayIdentity, layer.overlayIdentity)

        var autoOwned = provenanceAdded
        autoOwned.ownership = .auto
        var manuallyOwned = autoOwned
        manuallyOwned.ownership = .user
        XCTAssertEqual(manuallyOwned.overlayIdentity, autoOwned.overlayIdentity)
    }

    func testMaskRecipeChangesChangeOverlayIdentity() {
        let layer = Self.layer()

        assertOverlayIdentityChanges("adding a component", from: layer) {
            $0.components.append(Self.extraComponent())
        }
        assertOverlayIdentityChanges("removing a component", from: layer) {
            $0.components.removeLast()
        }
        assertOverlayIdentityChanges("reordering components", from: layer) {
            $0.components.reverse()
        }
        assertOverlayIdentityChanges("editing component geometry", from: layer) { changed in
            guard case .radial(var definition) = changed.components[1].source else {
                XCTFail("Fixture component should be radial")
                return
            }
            definition.center = CGPoint(x: 0.35, y: 0.5)
            changed.components[1].source = .radial(definition)
        }
        assertOverlayIdentityChanges("changing component mode", from: layer) {
            $0.components[0].mode = .subtract
        }
        assertOverlayIdentityChanges("inverting a component", from: layer) {
            $0.components[0].isInverted = true
        }
        assertOverlayIdentityChanges("changing the layer identity", from: layer) {
            $0.id = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        }
        assertOverlayIdentityChanges("disabling the layer", from: layer) {
            $0.isEnabled = false
        }
        assertOverlayIdentityChanges("inverting the layer", from: layer) {
            $0.isInverted = true
        }
        assertOverlayIdentityChanges("changing layer amount", from: layer) {
            $0.amount = 0.5
        }
    }

    func testCodableKeysStayReviewedAgainstOverlayIdentity() throws {
        let layer = LocalAdjustmentLayer(
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
        let encoded = try JSONEncoder().encode(layer)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actualKeys = Set(object.keys)
        let storedFieldNames = Set(Mirror(reflecting: layer).children.compactMap(\.label))
        let expectedKeys: Set<String> = [
            "id", "name", "isEnabled", "isInverted", "amount", "components",
            "adjustments", "ownership", "autoProvenance"
        ]

        XCTAssertEqual(
            storedFieldNames, expectedKeys,
            "Review every new LocalAdjustmentLayer field and decide whether overlayIdentity must include it."
        )
        XCTAssertEqual(
            actualKeys, expectedKeys,
            "Review new LocalAdjustmentLayer Codable keys and decide whether overlayIdentity must include them."
        )
    }

    private func assertOverlayIdentityChanges(
        _ change: String,
        from layer: LocalAdjustmentLayer,
        mutate: (inout LocalAdjustmentLayer) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var changed = layer
        mutate(&changed)
        XCTAssertNotEqual(
            changed.overlayIdentity, layer.overlayIdentity,
            "Changing \(change) must refresh mask overlay resolution.",
            file: file, line: line
        )
    }

    private static func layer() -> LocalAdjustmentLayer {
        LocalAdjustmentLayer(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            components: [
                MaskComponent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    source: .linear(LinearGradientDefinition())
                ),
                MaskComponent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    mode: .add,
                    source: .radial(RadialGradientDefinition())
                )
            ]
        )
    }

    private static func extraComponent() -> MaskComponent {
        MaskComponent(source: .radial(RadialGradientDefinition(center: CGPoint(x: 0.25, y: 0.5))))
    }
}
