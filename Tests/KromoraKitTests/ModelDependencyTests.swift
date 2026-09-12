import Foundation
import XCTest
@testable import KromoraKit

/// Source-level guardrails for the domain/application/platform split. SwiftPM's single target means
/// an import-only dependency graph cannot enforce this boundary by itself, so the durable file list
/// is checked directly and the platform owners are named explicitly.
final class ModelDependencyTests: XCTestCase {
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testDurableValueFilesDoNotAcquireUIFrameworks() throws {
        let durableFiles = [
            "Sources/KromoraKit/Models/PhotoAsset.swift",
            "Sources/KromoraKit/Models/EditDocument.swift",
            "Sources/KromoraKit/Models/AdjustmentNode.swift",
            "Sources/KromoraKit/Models/ColorAdjustments.swift",
            "Sources/KromoraKit/Models/LibrarySelection.swift",
            "Sources/KromoraKit/Models/RenderRequest.swift",
        ]
        for relativePath in durableFiles {
            let url = Self.packageRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(source.contains("import AppKit"), relativePath)
            XCTAssertFalse(source.contains("import SwiftUI"), relativePath)
            XCTAssertFalse(source.contains("import Combine"), relativePath)
        }
    }

    func testModelsDirectoryAllowsUIImportsOnlyForNamedPresentationOwners() throws {
        let modelsURL = Self.packageRoot.appendingPathComponent("Sources/KromoraKit/Models")
        let allowed = Set([
            "ImageCollection.swift",
            "Thumbnails.swift",
            "KromoraWindowAppearanceController.swift",
        ])
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: modelsURL, includingPropertiesForKeys: nil)
        )
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            let importsUI = source.contains("import AppKit") || source.contains("import SwiftUI")
            if importsUI {
                XCTAssertTrue(
                    allowed.contains(url.lastPathComponent),
                    "UI imports in Models must belong to an explicitly named presentation owner: " + url.path
                )
            }
        }
    }

    func testPlatformResponsibilitiesHaveExplicitOwners() throws {
        let expectedMarkers = [
            ("Sources/KromoraKit/Models/ImageCollection.swift", "ImageCollectionPresentationModel"),
            ("Sources/KromoraKit/Models/Thumbnails.swift", "PlatformThumbnailProvider"),
            ("Sources/KromoraKit/Models/KromoraWindowAppearanceController.swift", "AppKitWindowAppearanceController"),
            ("Sources/KromoraKit/Presentation/MaskInteractionPresentationBridge.swift", "extension MaskInteractionState"),
            ("Sources/KromoraKit/Platform/PhotoAssetImageMetadataAdapter.swift", "extension PhotoAsset"),
        ]
        for (relativePath, marker) in expectedMarkers {
            let url = Self.packageRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(source.contains(marker), relativePath + " should name " + marker)
        }
    }
}
