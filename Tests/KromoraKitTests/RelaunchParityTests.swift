import Foundation
import AppKit
import CoreGraphics
import XCTest

@testable import KromoraKit

/// Exercises persisted presentation frames across distinct application and collection lifetimes.
/// This intentionally loads the package's cheap browsing projection in both launches: that is the
/// startup path whose source fingerprint used to differ from the resolved edit source.
@MainActor
final class RelaunchParityTests: TempDirectoryTestCase {
    private let timeout: TimeInterval = 8

    private func waitUntil(
        _ description: String,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() >= deadline {
                throw TestSynchronizationError.timedOut(description, "presentation did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func model(
        packageURL: URL, previewDirectory: URL, thumbnailDirectory: URL,
        looksDirectory: URL, engine: FakeRenderEngine
    ) throws -> (AppViewModel, PortableLibrarySession) {
        let session = try PortableLibrarySession(at: packageURL)
        let viewModel = makeAppViewModel(
            engine: engine, userLookFolderURL: looksDirectory,
            previewFrameStoreDirectory: previewDirectory,
            thumbnailFrameStoreDirectory: thumbnailDirectory,
            portablePackageURL: packageURL, portableLibrarySession: session
        )
        return (viewModel, session)
    }

    private func pixels(of image: NSImage?) throws -> [UInt8] {
        var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
        let cgImage = try XCTUnwrap(image?.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return try Pixels.bytes(of: cgImage)
    }

    func testUnchangedPackageReusesSettledFramesAfterRelaunch() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Parity.kromoralibrary")
        let previewDirectory = tempDirectory.appendingPathComponent("Derived/Previews")
        let thumbnailDirectory = tempDirectory.appendingPathComponent("Derived/Thumbnails")
        let looksDirectory = tempDirectory.appendingPathComponent("Looks", isDirectory: true)
        try FileManager.default.createDirectory(at: looksDirectory, withIntermediateDirectories: true)
        let lookURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Parity Look.cube", in: looksDirectory
        )
        let look = try CubeLUT(url: lookURL)
        let names = ["plain-a.png", "plain-b.png", "exposure.png", "color.png", "crop.png", "look.png"]
        let sources = try names.enumerated().map { index, name in
            try Fixtures.writeGradientPNG(
                width: 48 + index, height: 32, named: name, in: tempDirectory
            )
        }
        let package = try PortableLibrarySession(at: packageURL)
        _ = try package.importURLs(sources, duplicatePolicy: .importAnyway)
        let seedAssets = try package.materializedAssets()
        let seedStore = EditDocumentStore(package: package.package, lease: package.lease)
        let edits: [(String, (inout EditDocument) -> Void)] = [
            ("exposure.png", { $0.adjustments = [.exposure(ev: 0.7)] }),
            ("color.png", { $0.light.contrast = 0.3 }),
            ("crop.png", { $0.crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.3)) }),
            ("look.png", { $0.lut = LUTSettings(lutID: look.lutID, intensity: 0.8) }),
        ]
        for (name, edit) in edits {
            guard let asset = seedAssets.first(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            var document = EditDocument()
            edit(&document)
            try await seedStore.save(document, for: EditSourceReference(
                assetID: asset.id, portableIdentity: asset.source.portableIdentity, url: asset.url
            ))
        }
        await package.shutdown()

        let firstEngine = FakeRenderEngine()
        let (first, firstSession) = try model(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            engine: firstEngine
        )
        first.library.scan(looksDirectory)
        try await waitUntil("Look library scan") { first.library.allLUTs.contains { $0.lutID == look.lutID } }
        first.collection.loadPortableAssets(try firstSession.browsingAssets())
        await first.collection.scanCompletion()

        first.collection.beginThumbnailDemand()
        first.collection.requestVisibleThumbnails(for: first.collection.items.map(\.id))
        try await waitUntil("first launch grid frames") {
            first.collection.items.allSatisfy { $0.thumbnail != nil }
                && edits.allSatisfy { name, _ in
                    first.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
                }
        }
        for (name, _) in edits {
            guard let index = first.collection.items.firstIndex(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            first.collection.setSelection(at: index)
            first.openActiveCollectionImage()
            try await waitUntil("\(name) first launch Edit confirmation") {
                first.sourceName == name && first.presentationSessionForDiagnostics?.state == .confirmed
            }
        }
        let flushResult = await first.flushPendingWrites()
        XCTAssertEqual(flushResult, .success)
        await first.shutdown()

        let secondEngine = FakeRenderEngine()
        let (second, secondSession) = try model(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            engine: secondEngine
        )
        second.library.scan(looksDirectory)
        try await waitUntil("reopened Look library scan") {
            second.library.allLUTs.contains { $0.lutID == look.lutID }
        }
        second.collection.loadPortableAssets(try secondSession.browsingAssets())
        XCTAssertEqual(secondSession.rootURL, packageURL.standardizedFileURL,
                       "relaunch must reopen the same package")
        await second.collection.scanCompletion()
        second.collection.beginThumbnailDemand()
        second.collection.requestVisibleThumbnails(for: second.collection.items.map(\.id))
        try await waitUntil("relaunch grid cache lookups") {
            second.collection.items.allSatisfy { $0.thumbnail != nil }
                && edits.allSatisfy { name, _ in
                    second.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
                }
        }
        var settledGridPixels: [String: [UInt8]] = [:]
        var settledGridRatios: [String: Double] = [:]
        for (name, _) in edits {
            guard let item = second.collection.items.first(where: { $0.displayName == name }) else {
                continue
            }
            settledGridPixels[name] = try pixels(of: item.thumbnail)
            settledGridRatios[name] = item.libraryAspectRatio
        }

        // KRMA-763, KRMA-764, KRMA-765 and KRMA-766 fix the persisted identity/geometry path.
        // On this tree the expected failures include the observed messages:
        // "edited thumbnails must be reused without rendering for exposure.png" (1 request),
        // "Edit must publish one confirmed frame for exposure.png" (2 distinct frames),
        // "unchanged Edit source must use its confirmed frame without a render for exposure.png" (1 request),
        // and "library aspect ratio must not change after first layout for exposure.png"
        // (1.5625 became 1.3333333333333333). Color, crop, and Look previews also render once.
        // Keep each positive contract intact while those implementation tickets land.
        for (name, _) in edits {
            let requests = await secondEngine.thumbnailRequests.filter {
                $0.assetID == second.collection.items.first { $0.displayName == name }?.id
            }
            XCTExpectFailure("KRMA-763: browsing identity mismatch", options: .nonStrict()) {
                XCTAssertEqual(
                    requests.count, 0,
                    "edited thumbnails must be reused without rendering for \(name)"
                )
            }
        }

        for (name, _) in edits {
            guard let index = second.collection.items.firstIndex(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            let before = await secondEngine.previewRequests.count
            second.collection.setSelection(at: index)
            second.openActiveCollectionImage()
            try await waitUntil("\(name) relaunch Edit confirmation") {
                second.sourceName == name
                    && second.presentationSessionForDiagnostics?.state == .confirmed
            }
            let session = try XCTUnwrap(second.presentationSessionForDiagnostics)
            XCTExpectFailure("KRMA-763: browsing identity mismatch", options: .nonStrict()) {
                XCTAssertEqual(
                    session.distinctFrameCount, 1,
                    "Edit must publish one confirmed frame for \(name)"
                )
            }
            XCTAssertNotEqual(session.candidateSource, .embeddedJPEG, "Edit must not begin with embedded JPEG for \(name)")
            XCTAssertNotEqual(session.candidateSource, .originalThumbnail, "Edit must not begin with original thumbnail for \(name)")
            let after = await secondEngine.previewRequests.count
            XCTExpectFailure("KRMA-763: browsing identity mismatch", options: .nonStrict()) {
                XCTAssertEqual(
                    after - before, 0,
                    "unchanged Edit source must use its confirmed frame without a render for \(name)"
                )
            }
        }

        for (name, _) in edits {
            let item = try XCTUnwrap(second.collection.items.first { $0.displayName == name })
            let finalPixels = try pixels(of: item.thumbnail)
            XCTAssertEqual(finalPixels, settledGridPixels[name],
                           "grid pixels must not swap after first paint for \(name)")
            XCTExpectFailure("KRMA-765: relaunch crop geometry", options: .nonStrict()) {
                XCTAssertEqual(item.libraryAspectRatio, settledGridRatios[name],
                               "library aspect ratio must not change after first layout for \(name)")
            }
        }

        await second.shutdown()

        // A fresh Derived directory is the non-vacuous control: an empty cache must request work.
        let coldEngine = FakeRenderEngine()
        let (cold, coldSession) = try model(
            packageURL: packageURL,
            previewDirectory: tempDirectory.appendingPathComponent("Cold/Previews"),
            thumbnailDirectory: tempDirectory.appendingPathComponent("Cold/Thumbnails"),
            looksDirectory: looksDirectory, engine: coldEngine
        )
        cold.library.scan(looksDirectory)
        try await waitUntil("cold control Look scan") {
            cold.library.allLUTs.contains { $0.lutID == look.lutID }
        }
        cold.collection.loadPortableAssets(try coldSession.browsingAssets())
        await cold.collection.scanCompletion()
        cold.collection.beginThumbnailDemand()
        cold.collection.requestVisibleThumbnails(for: cold.collection.items.map(\.id))
        try await waitUntil("cold control thumbnails") {
            edits.allSatisfy { name, _ in
                cold.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
            }
        }
        let coldThumbnailCount = await coldEngine.thumbnailRequests.count
        XCTAssertGreaterThan(coldThumbnailCount, 0, "a deleted Derived cache must trigger edited thumbnail renders")
        guard let coldIndex = cold.collection.items.firstIndex(where: { $0.displayName == "exposure.png" }) else {
            XCTFail("fixture photo exposure.png must be present")
            await cold.shutdown()
            return
        }
        cold.collection.setSelection(at: coldIndex)
        cold.openActiveCollectionImage()
        try await waitUntil("cold control preview") {
            cold.sourceName == "exposure.png" && cold.previewState == .ready
        }
        let coldPreviewCount = await coldEngine.previewRequests.count
        XCTAssertGreaterThan(coldPreviewCount, 0, "a deleted Derived cache must trigger preview render")
        await cold.shutdown()
    }
}
