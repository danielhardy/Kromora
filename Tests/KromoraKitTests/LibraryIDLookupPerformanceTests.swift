import Foundation
import XCTest

@testable import KromoraKit

/// Release comparison for KRMA-1162. The baseline reproduces the pre-change linear lookup and
/// successive-page open paths against the same generated package and process as the indexed path.
@MainActor
final class LibraryIDLookupPerformanceTests: TempDirectoryTestCase {
    private static let assetCount = 10_000
    private static let pageSize = 500
    private static let warmPageSize = 24
    private static let sampleCount = 3

    func testReleaseIdleWarmAndActiveOpenComparison() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_LIBRARY_ID_LOOKUP_BENCHMARK"] != nil,
            "set KROMORA_LIBRARY_ID_LOOKUP_BENCHMARK=1 for the KRMA-1162 Release comparison"
        )

        let generated = try await SyntheticLibraryGenerator.generate(
            scale: .tenThousand, seed: SyntheticLibraryGenerator.defaultSeed,
            in: tempDirectory, yieldEvery: 256
        )
        defer { try? generated.cleanup() }

        let packageURL = tempDirectory.appendingPathComponent("IDLookup.kromoralibrary")
        let generatedPackage = try generated.makePortableLibraryPackage(at: packageURL)
        let projection = try LibraryIndexProjection(package: generatedPackage.package)
        let indexURL = tempDirectory.appendingPathComponent("IDLookup-index/LibraryIndex.store")
        try projection.write(to: indexURL)

        let ids = generatedPackage.assetIDs
        let activeID = try XCTUnwrap(ids.last)
        let activeAsset = try XCTUnwrap(generated.assets.last)
        let activeFilename = activeAsset.filename
        let activeOriginalURL = try generatedPackage.package.browsingOriginalURL(
            for: activeID, displayName: activeAsset.filename
        )
        try FileManager.default.createDirectory(
            at: activeOriginalURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: activeAsset.url, to: activeOriginalURL)

        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, pageSize: Self.pageSize
        )
        do {
            // Seed the same warm first-page state available during ordinary navigation.
            XCTAssertEqual(session.page(at: 0).totalCount, Self.assetCount)
            let activePageIndex = try XCTUnwrap(session.pageIndex(of: activeID))
            XCTAssertGreaterThan(activePageIndex, 0, "the measured open must fault an off-page asset")

            var indexedWarmSamples: [Double] = []
            var linearWarmSamples: [Double] = []
            for _ in 0..<Self.sampleCount {
                indexedWarmSamples.append(try await measureWarmPass(
                    ids: ids, projection: projection, session: session, indexed: true
                ))
                linearWarmSamples.append(try await measureWarmPass(
                    ids: ids, projection: projection, session: session, indexed: false
                ))
            }

            // Both routes begin with the same warm query ordering. The baseline reproduces the
            // previous open loop: build pages in order until one contains the active asset.
            var indexedOpenSamples: [Double] = []
            var pageWalkOpenSamples: [Double] = []
            for _ in 0..<Self.sampleCount {
                indexedOpenSamples.append(try measureIndexedOpen(
                    session: session, assetID: activeID, filename: activeFilename
                ))
                pageWalkOpenSamples.append(try measurePageWalkOpen(
                    session: session, assetID: activeID, filename: activeFilename
                ))
            }

            let machine = Self.command("/usr/sbin/sysctl", arguments: ["-n", "hw.model"])
            let macOS = Self.command("/usr/bin/sw_vers", arguments: ["-productVersion"])
            print(
                "KRMA_1162_RELEASE_COMPARISON "
                    + "assets=\(Self.assetCount) page_size=\(Self.pageSize) "
                    + "active_page=\(activePageIndex) "
                    + "warm_batch_size=\(Self.warmPageSize) samples=\(Self.sampleCount) "
                    + "machine=\(machine) macOS=\(macOS) "
                    + "idle_warm_linear_ms=\(Self.median(linearWarmSamples)) "
                    + "idle_warm_indexed_ms=\(Self.median(indexedWarmSamples)) "
                    + "active_open_page_walk_ms=\(Self.median(pageWalkOpenSamples)) "
                    + "active_open_indexed_ms=\(Self.median(indexedOpenSamples))"
            )
            await session.shutdown()
        } catch {
            await session.shutdown()
            throw error
        }
    }

    private func measureWarmPass(
        ids: [PortablePhotoAssetID], projection: LibraryIndexProjection,
        session: PortableLibrarySession, indexed: Bool
    ) async throws -> Double {
        let controller = LibraryQueryController(index: projection, pageSize: Self.pageSize)
        let input = IdleFrameWarmPlanInput(
            controller: controller,
            anchorIDs: [ids[ids.count / 2]],
            fallbackSelection: ids.count / 2,
            recencyOrder: Array(ids.suffix(64).reversed()),
            generation: 1
        )

        let start = DispatchTime.now().uptimeNanoseconds
        let plan = await IdleFrameWarmPlanner.detached(input)
        var materializedCount = 0
        for pageStart in stride(from: 0, to: plan.count, by: Self.warmPageSize) {
            let page = plan[pageStart..<min(plan.count, pageStart + Self.warmPageSize)]
            let pageIDs = page.map(\.assetID)
            let assets: [PhotoAsset]
            if indexed {
                assets = try session.browsingAssets(forIDs: pageIDs)
            } else {
                // This is the pre-KRMA-1162 implementation of browsingAssets(forIDs:):
                // resolve each ID with Array.first, then use the same asset materializer.
                let items = pageIDs.compactMap { assetID -> LibraryQueryItem? in
                    guard let entry = projection.entries.first(where: { $0.assetID == assetID }),
                          entry.deletedRevision == nil else { return nil }
                    return LibraryQueryItem(
                        assetID: assetID, recordPath: entry.recordPath, summary: entry.summary,
                        isSelected: controller.selectedIDs.contains(assetID)
                    )
                }
                assets = try session.browsingAssets(for: items)
            }
            materializedCount += assets.count
        }
        let end = DispatchTime.now().uptimeNanoseconds
        XCTAssertEqual(materializedCount, ids.count)
        return Self.milliseconds(from: start, to: end)
    }

    private func measureIndexedOpen(
        session: PortableLibrarySession, assetID: PortablePhotoAssetID, filename: String
    ) throws -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        let pageIndex = try XCTUnwrap(session.pageIndex(of: assetID))
        let window = try session.browsingWindow(pageIndex: pageIndex)
        XCTAssertTrue(window.assets.contains { $0.source.portableIdentity.assetID == assetID })
        XCTAssertEqual(try session.resolveEmbeddedSourceURL(for: assetID).lastPathComponent, filename)
        let end = DispatchTime.now().uptimeNanoseconds
        return Self.milliseconds(from: start, to: end)
    }

    private func measurePageWalkOpen(
        session: PortableLibrarySession, assetID: PortablePhotoAssetID, filename: String
    ) throws -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        var pageIndex = 0
        while true {
            let page = session.page(at: pageIndex)
            if page.items.contains(where: { $0.assetID == assetID }) { break }
            guard page.hasNextPage else {
                XCTFail("active asset was not found by the baseline page walk")
                return 0
            }
            pageIndex += 1
        }
        let window = try session.browsingWindow(pageIndex: pageIndex)
        XCTAssertTrue(window.assets.contains { $0.source.portableIdentity.assetID == assetID })
        XCTAssertEqual(try session.resolveEmbeddedSourceURL(for: assetID).lastPathComponent, filename)
        let end = DispatchTime.now().uptimeNanoseconds
        return Self.milliseconds(from: start, to: end)
    }

    private static func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    private static func command(_ path: String, arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ) else { return "unavailable" }
            return value
        } catch {
            return "unavailable"
        }
    }
}
