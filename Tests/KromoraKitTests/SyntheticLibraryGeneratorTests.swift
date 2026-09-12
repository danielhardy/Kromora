import Foundation
import ImageIO
import XCTest

@testable import KromoraKit

final class SyntheticLibraryGeneratorTests: XCTestCase {

    func testSameScaleAndSeedProducesIdenticalValuesAndFileLayout() async throws {
        let parent = try Fixtures.makeTempDirectory("SyntheticDeterminism")
        defer { try? FileManager.default.removeItem(at: parent) }

        let first = try await SyntheticLibraryGenerator.generate(
            scale: .oneThousand, seed: 0x1234, in: parent
        )
        let second = try await SyntheticLibraryGenerator.generate(
            scale: .oneThousand, seed: 0x1234, in: parent
        )
        defer {
            try? first.cleanup()
            try? second.cleanup()
        }

        XCTAssertEqual(first.assets, second.assets)
        XCTAssertEqual(try fileManifest(at: first.rootURL), try fileManifest(at: second.rootURL))
        XCTAssertEqual(first.assets.count, 1_000)
    }

    func testSupportedFastScalesGenerateExpectedFileCountsAndTearDown() async throws {
        let parent = try Fixtures.makeTempDirectory("SyntheticScales")
        defer { try? FileManager.default.removeItem(at: parent) }

        for scale in [SyntheticLibraryGenerator.Scale.oneThousand, .tenThousand] {
            let library = try await SyntheticLibraryGenerator.generate(scale: scale, in: parent)
            XCTAssertTrue(library.existsOnDisk)
            XCTAssertEqual(library.assetCount, scale.assetCount)
            XCTAssertEqual(try regularFileCount(at: library.rootURL), scale.assetCount)

            let root = library.rootURL
            try library.cleanup()
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testGeneratedAssetsCarryVariedMetadataEditsAndThumbnailDemand() async throws {
        let parent = try Fixtures.makeTempDirectory("SyntheticShape")
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = try await SyntheticLibraryGenerator.generate(scale: .oneThousand, in: parent)
        defer { try? library.cleanup() }

        let assets = library.assets
        XCTAssertGreaterThan(Set(assets.map(\.metadata.cameraModel)).count, 1)
        XCTAssertGreaterThan(Set(assets.map(\.metadata.captureDate)).count, 1)
        XCTAssertGreaterThan(Set(assets.map(\.metadata.orientation)).count, 1)
        XCTAssertTrue(assets.allSatisfy { [1, 3, 6, 8].contains($0.metadata.orientation) })

        let edited = assets.filter { $0.editSummary.hasEdits }
        let developed = assets.filter { $0.editSummary.hasNonDefaultDevelopSettings }
        let thumbnailDemand = assets.filter(\.needsThumbnailGeneration)
        XCTAssertGreaterThan(edited.count, 0)
        XCTAssertLessThan(edited.count, assets.count)
        XCTAssertGreaterThan(developed.count, 0)
        XCTAssertLessThan(developed.count, assets.count)
        XCTAssertGreaterThan(thumbnailDemand.count, 0)
        XCTAssertLessThan(thumbnailDemand.count, assets.count)

        let first = try XCTUnwrap(assets.first)
        let readMetadata = ImageMetadata.read(from: first.url)
        XCTAssertEqual(readMetadata.make, first.metadata.cameraMake)
        XCTAssertEqual(readMetadata.model, first.metadata.cameraModel)
        XCTAssertEqual(readMetadata.lens, first.metadata.lens)
        XCTAssertNotNil(readMetadata.dateTaken)
        XCTAssertEqual(
            ImageDecoder.exifOrientation(at: first.url).rawValue,
            UInt32(first.metadata.orientation)
        )
        XCTAssertEqual(first.photoAsset.thumbnailState, first.needsThumbnailGeneration ? .notRequested : .ready)
    }

    func testWithLibraryCleansUpAfterTheOperation() async throws {
        let parent = try Fixtures.makeTempDirectory("SyntheticWith")
        defer { try? FileManager.default.removeItem(at: parent) }

        var generatedRoot: URL?
        let count = try await SyntheticLibraryGenerator.withLibrary(
            scale: .oneThousand,
            in: parent
        ) { library in
            generatedRoot = library.rootURL
            XCTAssertTrue(library.existsOnDisk)
            return library.assetCount
        }

        XCTAssertEqual(count, 1_000)
        XCTAssertNotNil(generatedRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: generatedRoot!.path))
    }

    func testCancellationRemovesPartialLibrary() async throws {
        let parent = try Fixtures.makeTempDirectory("SyntheticCancellation")
        defer { try? FileManager.default.removeItem(at: parent) }

        let generation = Task {
            try await SyntheticLibraryGenerator.generate(
                scale: .tenThousand,
                seed: 0xCA11,
                in: parent,
                yieldEvery: 1
            )
        }
        await Task.yield()
        generation.cancel()

        do {
            _ = try await generation.value
            XCTFail("cancelled generation should not return a library")
        } catch is CancellationError {
            // Expected: the generator checks cancellation and removes its owned root.
        } catch {
            XCTFail("unexpected cancellation error: \(error)")
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil, options: []
        )
        XCTAssertTrue(children.isEmpty, "cancellation left generated state behind: \(children)")
    }

    private func regularFileCount(at root: URL) throws -> Int {
        try fileManifest(at: root).count
    }

    private func fileManifest(at root: URL) throws -> [String: Data] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let rootMarker = "/\(root.lastPathComponent)/"
            guard let markerRange = url.path.range(of: rootMarker) else {
                XCTFail("generated file escaped its root: \(url.path)")
                continue
            }
            let relative = String(url.path[markerRange.upperBound...])
            result[relative] = try Data(contentsOf: url)
        }
        return result
    }
}

final class SyntheticLibraryGeneratorPerformanceTests: XCTestCase {

    func testAllSupportedScalesIncludingOneHundredThousandGenerateAndTearDown() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_SYNTHETIC_LIBRARY_BENCHMARK"] != nil,
            "set KROMORA_SYNTHETIC_LIBRARY_BENCHMARK=1 to run the 100k generator lane"
        )

        let parent = try Fixtures.makeTempDirectory("Synthetic100K")
        defer { try? FileManager.default.removeItem(at: parent) }

        for scale in SyntheticLibraryGenerator.Scale.allCases {
            let start = DispatchTime.now().uptimeNanoseconds
            let library = try await SyntheticLibraryGenerator.generate(scale: scale, in: parent)
            let generated = DispatchTime.now().uptimeNanoseconds

            XCTAssertEqual(library.assetCount, scale.assetCount)
            XCTAssertEqual(try regularFileCount(at: library.rootURL), scale.assetCount)
            print(String(
                format: "SYNTHETIC_LIBRARY_PROFILE items=%d generation_ms=%.1f",
                library.assetCount,
                Double(generated - start) / 1_000_000
            ))

            let root = library.rootURL
            try library.cleanup()
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    private func regularFileCount(at root: URL) throws -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                count += 1
            }
        }
        return count
    }
}
