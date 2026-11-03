import Foundation
import XCTest

@testable import KromoraKit

/// Retention and deletion behavior of the analysis and mask disposable caches. Assertions count
/// decoded documents and removed entries rather than timing, so they are deterministic.
final class DiskCacheBudgetTests: TempDirectoryTestCase {
    private let day: TimeInterval = 24 * 3600

    // MARK: - Deletion

    func testBatchDeleteNeverDecodesRecords() async throws {
        let masks = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let analyses = PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("analysis"))
        var keys: [MaskCacheKey] = []
        for index in 0..<120 {
            let key = makeMaskKey(asset: index)
            keys.append(key)
            try await masks.store(try makeMask(side: 4), for: key, quality: .preview)
            try await analyses.store(
                makeAnalysis(), for: AnalysisCacheKey(identity: key.identity, analysisVersion: .current)
            )
        }

        let doomed = keys.prefix(100).map(\.identity.assetID)
        try await masks.remove(for: doomed)
        try await analyses.remove(for: doomed)

        let maskDecodes = await masks.metadataDecodeCount
        let analysisDecodes = await analyses.decodeCount
        XCTAssertEqual(maskDecodes, 0, "deleting must not decode any mask record")
        XCTAssertEqual(analysisDecodes, 0, "deleting must not decode any analysis record")
        for key in keys.prefix(100) {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: MaskStoreTestSupport.assetDirectory(in: tempDirectory.appendingPathComponent("masks"), for: key).path
            ))
        }
        for key in keys.suffix(20) {
            let survivor = await masks.mask(for: key, quality: .preview)
            XCTAssertNotNil(survivor)
        }
        // Removing an already-removed asset is a no-op, not an error.
        try await masks.remove(for: doomed)
    }

    // MARK: - Caps

    func testByteCapEvictsLeastRecentlyUsedFirst() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let keys = (0..<5).map { makeMaskKey(asset: $0) }
        for (index, key) in keys.enumerated() {
            try await store.store(try makeMask(side: 100), for: key, quality: .preview)
            // Oldest first: asset 0 is the stalest.
            try setModified(clock.now.addingTimeInterval(-Double(5 - index) * 60), for: key, in: directory)
        }
        let entryBytes: Int64 = 100 * 100 * 4
        let budget = DiskCacheBudget(maxBytes: entryBytes * 5 / 2 + 4096, maxAge: 30 * day)

        let report = try await store.trim(budget: budget)

        XCTAssertEqual(report.removed(.overBudget), 3)
        XCTAssertLessThanOrEqual(report.remainingBytes, budget.maxBytes)
        XCTAssertEqual(report.remainingEntries, 2)
        for (index, key) in keys.enumerated() {
            let present = await store.mask(for: key, quality: .preview) != nil
            XCTAssertEqual(present, index >= 3, "asset \(index)")
        }
    }

    func testAgeCapRemovesIdleEntriesButNotRecentOnes() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let old = makeMaskKey(asset: 1)
        let recent = makeMaskKey(asset: 2)
        try await store.store(try makeMask(side: 4), for: old, quality: .preview)
        try await store.store(try makeMask(side: 4), for: recent, quality: .preview)
        try setModified(clock.now.addingTimeInterval(-40 * day), for: old, in: directory)

        let report = try await store.trim(budget: DiskCacheBudget(maxBytes: 1 << 30, maxAge: 30 * day))

        XCTAssertEqual(report.removed(.expired), 1)
        let oldHit = await store.mask(for: old, quality: .preview)
        let recentHit = await store.mask(for: recent, quality: .preview)
        XCTAssertNil(oldHit)
        XCTAssertNotNil(recentHit)
        // The now-empty asset directory is reclaimed as well.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: MaskStoreTestSupport.assetDirectory(in: directory, for: old).path
        ))
    }

    func testReadsRefreshRecencySoUsedEntriesSurviveTheAgeCap() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let key = makeMaskKey(asset: 1)
        try await store.store(try makeMask(side: 4), for: key, quality: .preview)
        try setModified(clock.now.addingTimeInterval(-40 * day), for: key, in: directory)

        let hit = await store.mask(for: key, quality: .preview)
        XCTAssertNotNil(hit)
        let report = try await store.trim(budget: DiskCacheBudget(maxBytes: 1 << 30, maxAge: 30 * day))

        XCTAssertEqual(report.removedCount, 0)
    }

    // MARK: - Stale and superseded variants

    func testTrimDropsAnalysisEntriesFromOtherVersions() async throws {
        let directory = tempDirectory.appendingPathComponent("analysis")
        let cache = PhotoAnalysisCache(directory: directory)
        let identity = makeMaskKey(asset: 3).identity
        let current = AnalysisCacheKey(identity: identity, analysisVersion: .current)
        let future = AnalysisCacheKey(
            identity: identity, analysisVersion: AnalysisVersion(rawValue: AnalysisVersion.current.rawValue + 1)
        )
        try await cache.store(makeAnalysis(version: current.analysisVersion), for: current)
        try await cache.store(makeAnalysis(version: future.analysisVersion), for: future)

        let report = try await cache.trim()

        XCTAssertEqual(report.removed(.staleVersion), 1)
        let kept = try await cache.analysis(for: current)
        let dropped = try await cache.analysis(for: future)
        XCTAssertNotNil(kept)
        XCTAssertNil(dropped)
    }

    func testSupersededProviderVariantIsRemovedOnlyAfterGraceAndWhenUnused() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let base = makeMaskKey(asset: 4)
        let oldProvider = MaskCacheKey(
            identity: base.identity, kind: base.kind, quality: base.quality, providerVersion: "vision-old"
        )
        let newProvider = MaskCacheKey(
            identity: base.identity, kind: base.kind, quality: base.quality, providerVersion: "vision-new"
        )
        try await store.store(try makeMask(side: 4), for: oldProvider, quality: .preview)
        try await store.store(try makeMask(side: 4), for: newProvider, quality: .preview)
        let budget = DiskCacheBudget(maxBytes: 1 << 30, maxAge: 365 * day)

        // Within the grace window an alternating identity is left alone.
        try setModified(clock.now.addingTimeInterval(-3600), for: oldProvider, in: directory)
        var report = try await store.trim(budget: budget)
        XCTAssertEqual(report.removedCount, 0)

        try setModified(clock.now.addingTimeInterval(-2 * day), for: oldProvider, in: directory)
        report = try await store.trim(budget: budget)
        XCTAssertEqual(report.removed(.superseded), 1)
        let oldHit = await store.mask(for: oldProvider, quality: .preview)
        let newHit = await store.mask(for: newProvider, quality: .preview)
        XCTAssertNil(oldHit)
        XCTAssertNotNil(newHit)
    }

    func testDifferentKindsAndQualitiesAreNotSupersededByEachOther() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let base = makeMaskKey(asset: 5)
        let face = base.with(kind: .face)
        try await store.store(try makeMask(side: 4), for: base, quality: .preview)
        try await store.store(try makeMask(side: 4), for: base, quality: .render)
        try await store.store(try makeMask(side: 4), for: face, quality: .preview)
        for key in [base, face] {
            for quality in [MaskQuality.preview, .render] {
                try? setModified(clock.now.addingTimeInterval(-3 * day), for: key.with(quality: quality), in: directory)
            }
        }
        try setModified(clock.now.addingTimeInterval(-1), for: face, in: directory)

        let report = try await store.trim(budget: DiskCacheBudget(maxBytes: 1 << 30, maxAge: 365 * day))

        XCTAssertEqual(report.removedCount, 0)
    }

    // MARK: - Corrupt, legacy, interrupted

    func testInterruptedTwoFileWritesAreMissesAndReclaimedAfterGrace() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let sidecarOnly = makeMaskKey(asset: 6)
        let metadataOnly = makeMaskKey(asset: 7)
        try await store.store(try makeMask(side: 4), for: sidecarOnly, quality: .preview)
        try await store.store(try makeMask(side: 4), for: metadataOnly, quality: .preview)
        try FileManager.default.removeItem(
            at: MaskStoreTestSupport.metadataURL(in: directory, for: sidecarOnly.with(quality: .preview))
        )
        try FileManager.default.removeItem(
            at: MaskStoreTestSupport.sidecarURL(in: directory, for: metadataOnly.with(quality: .preview))
        )
        let strayTemp = MaskStoreTestSupport.assetDirectory(in: directory, for: sidecarOnly)
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        try Data(repeating: 1, count: 64).write(to: strayTemp)

        let sidecarHit = await store.mask(for: sidecarOnly, quality: .preview)
        let metadataHit = await store.mask(for: metadataOnly, quality: .preview)
        XCTAssertNil(sidecarHit)
        XCTAssertNil(metadataHit)

        // A concurrent writer may still be finishing: young partial entries are left alone.
        var report = try await store.trim()
        XCTAssertEqual(report.removedCount, 0)

        clock.now = clock.now.addingTimeInterval(2 * 3600)
        report = try await store.trim()
        XCTAssertEqual(report.removed(.interrupted), 3)
        XCTAssertEqual(report.remainingEntries, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayTemp.path))
    }

    func testCorruptAndOversizedMetadataAreMissesWithoutDecoding() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let store = MaskStore(directory: directory)
        let key = makeMaskKey(asset: 8).with(quality: .preview)
        try FileManager.default.createDirectory(
            at: MaskStoreTestSupport.assetDirectory(in: directory, for: key), withIntermediateDirectories: true
        )
        // Larger than any real metadata: must be rejected from its size, never read.
        try Data(repeating: 0x20, count: 200_000).write(
            to: MaskStoreTestSupport.metadataURL(in: directory, for: key)
        )
        let oversized = await store.mask(for: key, quality: .preview)
        let decodedOversized = await store.metadataDecodeCount
        XCTAssertNil(oversized)
        XCTAssertEqual(decodedOversized, 0)

        try Data("{not json".utf8).write(to: MaskStoreTestSupport.metadataURL(in: directory, for: key))
        let corrupt = await store.mask(for: key, quality: .preview)
        XCTAssertNil(corrupt)
    }

    func testAbsurdDimensionsAndTruncatedSidecarsAreMisses() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let store = MaskStore(directory: directory)
        let key = makeMaskKey(asset: 9)
        let reference = try await store.store(try makeMask(side: 8), for: key, quality: .preview)

        // Truncate the sidecar: existence and pixel reads both reject it.
        let sidecar = MaskStoreTestSupport.sidecarURL(in: directory, for: reference.cacheKey)
        let handle = try FileHandle(forWritingTo: sidecar)
        try handle.truncate(atOffset: 10)
        try handle.close()
        let truncatedHit = await store.mask(for: key, quality: .preview)
        let truncatedPixels = await store.pixels(for: reference)
        XCTAssertNil(truncatedHit)
        XCTAssertNil(truncatedPixels)

        // Metadata claiming a gigantic raster is rejected before any allocation is sized from it.
        let huge = RegionMaskReference(
            cacheKey: reference.cacheKey, size: PixelDimensions(width: 1 << 20, height: 1 << 20),
            quality: .preview
        )
        let hugePixels = await store.pixels(for: huge)
        XCTAssertNil(hugePixels)
    }

    func testTrimLeavesUnrecognizedFilesAlone() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let key = makeMaskKey(asset: 10)
        try await store.store(try makeMask(side: 4), for: key, quality: .preview)
        let foreign = directory.appendingPathComponent("recipe.json")
        try Data("saved recipe".utf8).write(to: foreign)
        try setModified(clock.now.addingTimeInterval(-400 * day), url: foreign)

        _ = try await store.trim(budget: DiskCacheBudget(maxBytes: 0, maxAge: 1))

        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    // MARK: - Session plateau and latency

    /// Models a repeated export-quality masking session across many photos with a small budget:
    /// disk use must plateau at the budget instead of growing with the number of photos masked.
    func testRepeatedMaskingSessionPlateausAtTheBudget() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let clock = Clock(Date())
        let store = MaskStore(directory: directory, now: { clock.now })
        let side = 256
        let entryBytes = Int64(side * side * 4)
        let budget = DiskCacheBudget(maxBytes: entryBytes * 40, maxAge: 30 * day)
        let clockStart = ContinuousClock.now
        var peak: Int64 = 0
        var trims = 0
        var unboundedBytes: Int64 = 0

        for index in 0..<400 {
            let key = makeMaskKey(asset: index)
            try await store.store(try makeMask(side: side), for: key, quality: .render)
            unboundedBytes += entryBytes
            clock.now = clock.now.addingTimeInterval(60)
            try setModified(clock.now, for: key, in: directory, quality: .render)
            peak = max(peak, try directoryBytes(directory))
            if await store.isTrimDue(budget: budget) {
                try await store.trim(budget: budget)
                trims += 1
            }
        }
        let report = try await store.trim(budget: budget)
        let elapsed = clockStart.duration(to: .now)

        XCTAssertLessThanOrEqual(report.remainingBytes, budget.maxBytes)
        XCTAssertLessThanOrEqual(try directoryBytes(directory), budget.maxBytes + 64 * 1024)
        XCTAssertLessThan(peak, budget.maxBytes * 2, "peak must stay near the budget")
        XCTAssertLessThan(peak, unboundedBytes / 2)
        print("KRMA-1167 plateau: photos=400 entry=\(entryBytes)B budget=\(budget.maxBytes)B "
              + "peak=\(peak)B final=\(report.remainingBytes)B unbounded=\(unboundedBytes)B "
              + "trims=\(trims) session=\(elapsed)")
    }

    func testBatchDeleteAndTrimLatencyOnALargeCache() async throws {
        let directory = tempDirectory.appendingPathComponent("masks")
        let store = MaskStore(directory: directory)
        let keys = (0..<1500).map { makeMaskKey(asset: $0) }
        for key in keys {
            try await store.store(try makeMask(side: 8), for: key, quality: .preview)
        }
        let clock = ContinuousClock()

        let trimReport = try await store.trim()
        let deleteStart = clock.now
        try await store.remove(for: keys.prefix(1000).map(\.identity.assetID))
        let deleteTime = deleteStart.duration(to: clock.now)

        let decodes = await store.metadataDecodeCount
        XCTAssertEqual(decodes, 0)
        XCTAssertEqual(trimReport.remainingEntries, 1500)
        print("KRMA-1167 latency: trim(1500 assets)=\(trimReport.duration) "
              + "batch-delete(1000 of 1500)=\(deleteTime)")
    }

    // MARK: - Helpers

    private final class Clock: @unchecked Sendable {
        // Test-only mutable clock; each test drives it from one task.
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func makeMaskKey(asset index: Int) -> MaskCacheKey {
        let identity = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(uuid: UUID(uuidString: String(
                format: "00000000-0000-4000-8000-%012d", index
            ))!),
            sourceFingerprint: .data(
                Data("source-\(index)".utf8), sourceRevision: 1, decoderVersion: "d1",
                geometry: PhotoPixelDimensions(width: 40, height: 30)
            )
        )
        return MaskCacheKey(
            identity: identity, kind: .subject, quality: .preview, providerVersion: "vision-test"
        )
    }

    private func makeMask(side: Int) throws -> NormalizedMask {
        try NormalizedMask(
            size: PixelDimensions(width: side, height: side),
            values: (0..<(side * side)).map { Float($0 % 7) / 6 }
        )
    }

    private func makeAnalysis(version: AnalysisVersion = .current) -> PhotoAnalysis {
        PhotoAnalysis(
            version: version, globalTone: ToneStatistics(variant: .perceptual, mean: 0.4),
            colorStatistics: .neutral, quality: .globalOnly
        )
    }

    private func setModified(
        _ date: Date, for key: MaskCacheKey, in directory: URL, quality: MaskQuality = .preview
    ) throws {
        let exact = key.with(quality: quality)
        for url in [MaskStoreTestSupport.metadataURL(in: directory, for: exact),
                    MaskStoreTestSupport.sidecarURL(in: directory, for: exact)] {
            try setModified(date, url: url)
        }
    }

    private func setModified(_ date: Date, url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func directoryBytes(_ directory: URL) throws -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        )
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            total += Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        }
        return total
    }
}
