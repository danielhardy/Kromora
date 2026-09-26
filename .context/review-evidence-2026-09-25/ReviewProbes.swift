import Foundation
import CoreImage
@testable import KromoraKit

@main
@MainActor
struct ReviewProbes {
    static let fm = FileManager.default
    static func main() async throws {
        let base = fm.temporaryDirectory.appendingPathComponent("kromora-review-\(UUID())")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try recoveryProbe(base, relocate: true)
        try recoveryProbe(base, relocate: false)
        try staleIndexProbe(base)
        try maintenanceProbe(base)
        try staleCatalogProbe(base)
        try leaseProbe(base)
        try await exportProbe(base)
        lutCacheProbe(base)
        if !CommandLine.arguments.contains("--skip-performance") { try performanceProbe(base) }
    }
    static func recoveryProbe(_ base: URL, relocate: Bool) throws {
        let root = base.appendingPathComponent(relocate ? "relocate" : "retry")
        try fm.createDirectory(at: root.appendingPathComponent("State"), withIntermediateDirectories: true)
        let target = root.appendingPathComponent("State/value.txt")
        try Data("old".utf8).write(to: target)
        let lease = try PortablePackageLease.acquire(at: root)
        var transaction = try PortablePackageTransaction.begin(at: root, lease: lease,
            faultInjector: PortablePackageFaultInjector(failingAt: .publish))
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        do { try transaction.commit() } catch { }
        try lease.release()
        let journalURL = root.appendingPathComponent("Recovery/Transactions/\(transaction.transactionID).json")
        let journal = try PackageJSONCoder.decode(PortablePackageTransactionJournal.self, from: Data(contentsOf: journalURL))
        let recoveryRoot: URL
        if relocate {
            recoveryRoot = base.appendingPathComponent("moved")
            try fm.moveItem(at: root, to: recoveryRoot)
        } else {
            // Exact filesystem state after rollback restored a backup but before its journal was removed.
            try fm.removeItem(at: target)
            try fm.moveItem(at: URL(fileURLWithPath: journal.files[0].backupPath!), to: target)
            recoveryRoot = root
        }
        _ = try PortablePackageTransaction.recover(at: recoveryRoot)
        let result = try? String(contentsOf: recoveryRoot.appendingPathComponent("State/value.txt"), encoding: .utf8)
        print("\(relocate ? "relocated recovery" : "interrupted rollback replay"): expected old, actual \(result ?? "MISSING")")
    }
    static func staleIndexProbe(_ base: URL) throws {
        let package = try PortableLibraryPackage.create(at: base.appendingPathComponent("index.kromoralibrary"))
        let old = try LibraryIndexProjection(package: package)
        let id = PortablePhotoAssetID()
        let shardName = PortableLibraryPackage.shard(for: id)
        var shard = try package.readMembershipShard(shardName)
        shard.entries.append(.init(assetID: id, recordPath: "Assets/\(shardName)/\(id.raw)/asset.json", summary: .init(displayName: "new.jpg")))
        try package.writeMembershipShard(shard)
        let accepted = try old.validated(for: package)
        print("stale index: canonical count \(try LibraryIndexProjection(package: package).count), accepted old index count \(accepted.count)")
    }
    static func maintenanceProbe(_ base: URL) throws {
        let package = try PortableLibraryPackage.create(at: base.appendingPathComponent("maintenance.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        var tx = try package.beginTransaction(lease: lease)
        try tx.stage(data: Data("pending".utf8), at: "State/active.txt")
        _ = try PortablePackageMaintenance.run(at: package.rootURL, lease: lease)
        do { try tx.commit(); print("live transaction after maintenance: committed") }
        catch { print("live transaction after maintenance: failed \(error)") }
        try lease.release()
    }
    static func staleCatalogProbe(_ base: URL) throws {
        let package = try PortableLibraryPackage.create(at: base.appendingPathComponent("catalog.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        let catalog = try PortablePackageImportCatalog(package: package)
        // Model a catalog update after import captured its shard snapshots. Populate each shard
        // so the generated import UUID deterministically collides with one changed shard.
        for shardName in PortableLibraryPackage.allShards {
            let id = PortablePhotoAssetID(uuid: UUID(uuidString: shardName + "000000-0000-0000-0000-000000000000")!)
            var shard = try package.readMembershipShard(shardName)
            shard.entries.append(.init(assetID: id, recordPath: "Assets/\(shardName)/\(id.raw)/asset.json", summary: .init(displayName: "existing.jpg")))
            try package.writeMembershipShard(shard)
        }
        let imported = try package.importSources([.init(data: Data("import".utf8), name: "new.jpg")], lease: lease, catalog: catalog)
        let chosenShard = PortableLibraryPackage.shard(for: imported.imported[0].assetID)
        let count = try package.readMembershipShard(chosenShard).entries.count
        print("stale import catalog: expected changed shard entries 2, actual \(count)")
        try lease.release()
    }
    static func lutCacheProbe(_ base: URL) {
        let url = base.appendingPathComponent("same.cube")
        let black = CubeLUT(cube: Array(repeating: SIMD3<Float>(repeating: 0), count: 8), size: 2, name: "Same", sourceURL: url)
        let white = CubeLUT(cube: Array(repeating: SIMD3<Float>(repeating: 1), count: 8), size: 2, name: "Same", sourceURL: url)
        let cache = LUTFilterCache()
        let first = cache.filter(for: black)
        let before = first?.value(forKey: "inputCubeData") as? Data
        let second = cache.filter(for: white)
        let after = second?.value(forKey: "inputCubeData") as? Data
        print("changed LUT at same ID: fingerprints differ=\(black.cacheFingerprint != white.cacheFingerprint), reused filter=\(first === second), cube bytes unchanged=\(before == after)")
    }
    static func performanceProbe(_ base: URL) throws {
        let clock = ContinuousClock()
        for count in [1_000, 10_000, 100_000] {
            let entries = (0..<count).map { i in
                let id = PortablePhotoAssetID()
                return LibraryIndexEntry(assetID: id, recordPath: "Assets/\(PortableLibraryPackage.shard(for: id))/\(id.raw)/asset.json", summary: .init(displayName: "Photo-\(count - i).jpg"))
            }
            let controller = LibraryQueryController(index: try LibraryIndexProjection(libraryID: UUID(), entries: entries))
            var samples = [Double]()
            var total = 0
            for pageIndex in 0..<10 {
                let start = clock.now
                total += controller.page(at: pageIndex).items.count
                let d = start.duration(to: clock.now).components
                samples.append(Double(d.seconds)*1000 + Double(d.attoseconds)/1e15)
            }
            samples.sort()
            print("query probe n=\(count), 10 page calls, median_ms=\(samples[5]), max_ms=\(samples.last!), items=\(total)")
        }
        let file = base.appendingPathComponent("fingerprint.bin")
        try Data(repeating: 41, count: 32 * 1024 * 1024).write(to: file)
        let begin = clock.now
        let source = ImageSource(url: file, nativeExtent: .zero)
        let duration = begin.duration(to: clock.now)
        let start = clock.now
        var chars = 0
        for _ in 0..<1000 { chars += source.cacheFingerprint.count }
        print("32MiB source init=\(duration), 1000 fingerprint accesses=\(start.duration(to: clock.now)), chars=\(chars)")
    }
    static func leaseProbe(_ base: URL) throws {
        let start = Date()
        let lease = try PortablePackageLease.acquire(at: base.appendingPathComponent("lease"), now: start)
        do {
            try lease.renew(now: start.addingTimeInterval(181))
            print("wake lease renewal: success")
        } catch {
            print("wake lease renewal after 181s, owner unchanged: \(error)")
        }
        try lease.release()
    }
    @MainActor
    static func exportProbe(_ base: URL) async throws {
        let root = base.appendingPathComponent("export.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: root)
        let lease = try PortablePackageLease.acquire(at: root)
        let result = try package.importSources([.init(data: Data("placeholder".utf8), name: "unopened.jpg")], lease: lease)
        let id = result.imported[0].assetID
        let record = try package.readAssetRecord(for: id)
        let store = EditDocumentStore(package: package, lease: lease)
        let engine = ProbeRenderer()
        let export = ExportCoordinator(engine: engine, editStore: store, photosDelivery: nil)
        var activeDocument = EditDocument()
        activeDocument.light.exposure = 2
        let folder = base.appendingPathComponent("exports")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let outcome = await export.performBatchExport([
            .init(url: try package.embeddedSourceURL(for: record), data: nil, name: "unopened", assetID: PhotoAssetID(rawValue: "portable:\(id.raw)"), portableIdentity: record.identity)
        ], document: activeDocument, lut: nil, format: .jpeg, to: folder)
        print("unedited batch item: expected exposure 0, actual \(await engine.exposure), exported \(outcome.exported)")
        let target = folder.appendingPathComponent("replace.jpg")
        try Data("old output".utf8).write(to: target)
        let failure = MessageBox()
        export.onError = { failure.value = $0 }
        export.performExport(source: ImageSource(data: Data("input".utf8), nativeExtent: .zero), document: activeDocument, lut: nil, format: .jpeg, to: target)
        while export.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        print("single export to existing file: \(failure.value ?? "success")")
        try lease.release()
    }
}
@MainActor final class MessageBox { var value: String? }
actor ProbeRenderer: RenderEngining {
    var exposure: Double = -999
    func render(_ request: RenderRequest) async throws -> RenderResult {
        exposure = request.document.light.exposure
        return RenderResult(data: Data("fake render".utf8), extent: .init(width: 1, height: 1), colorSpace: request.space, quality: request.quality, output: request.output)
    }
    func histogram(source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale, space: WorkingSpace, maxDimension: Int) async -> HistogramData? { nil }
    func invalidateLUTCache() async {}
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }
}
