import AppKit
import Foundation

@testable import KromoraKit

actor CountingProvider: SemanticMaskProviding {
    private(set) var calls = 0
    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws
        -> RegionMask
    {
        calls += 1
        throw RegionMaskError.missingPixels
    }
}
@MainActor final class RetouchHost: RetouchWorkflowDestination {
    var document = EditDocument()
    var sourceSize = CGSize(width: 100, height: 100)
    var retouchAnalysisSource: ImageSource? { nil }
    var pick: CheckedContinuation<Void, Never>?
    var photo = "A"
    var endedOn: [String] = []
    func updateDocument(_ transform: (inout EditDocument) -> Void) { transform(&document) }
    func pickRetouchSource(spotID: UUID, rank: Int) async {
        await withCheckedContinuation { pick = $0 }
    }
    func setRetouchCanvasActive(_ active: Bool) {}
    func beginUndoGrouping() {}
    func endUndoGrouping() { endedOn.append(photo) }
    func retouchAnalysisProxy(source: ImageSource) async -> RetouchAnalysisProxy? { nil }
    func publishRetouchStatus(_ message: String) {}
}
@main struct AdditionalProbes {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kromora-additional-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = PhotoAnalysisCache(directory: root.appendingPathComponent("Analysis"))
        let source = ImageSource(
            data: Data([1, 2, 3]), nativeExtent: CGSize(width: 16, height: 16))
        let globalOnly = PhotoAnalysis(
            globalTone: .neutral, colorStatistics: .neutral, quality: .globalOnly)
        try await cache.store(
            globalOnly, for: .init(identity: source.cacheIdentity, analysisVersion: .current))
        let provider = CountingProvider()
        let masks = MaskStore(directory: root.appendingPathComponent("Masks"))
        let analysis = PhotoAnalysisCoordinator(
            maskStore: masks, cache: cache, maskProvider: provider)
        let detailed = try await analysis.analyze(
            assetID: .data(Data([1, 2, 3])), source: source, level: .detailed)
        print(
            "analysis: detailedRequestReturnedGlobalOnly=\(detailed.quality == .globalOnly) requestedMaskStages=\(await provider.calls)"
        )
        await analysis.shutdown()

        let host = RetouchHost()
        let workflow = RetouchWorkflowCoordinator(destination: host)
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.5, y: 0.5))
        workflow.endGesture()
        while host.pick == nil { await Task.yield() }
        host.photo = "B"
        await workflow.shutdown()
        let before = host.endedOn.count
        host.pick?.resume()
        host.pick = nil
        for _ in 0..<30 { await Task.yield() }
        print(
            "retouch: undoGroupEndsAtShutdown=\(before) undoGroupEndsAfterShutdown=\(host.endedOn)")

        let package = try PortableLibraryPackage.create(
            at: root.appendingPathComponent("Looks.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        let file = root.appendingPathComponent("source.jpg")
        try Data("disposable source".utf8).write(to: file)
        let result = try package.importSources([.init(url: file)], lease: lease)
        let asset = result.imported[0].assetID
        let reference = EditSourceReference(assetID: .init(rawValue: "portable:\(asset.raw)"))
        let cubeURL = root.appendingPathComponent("deleted.cube")
        let cubeBytes = Data(
            "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n".utf8)
        try cubeBytes.write(to: cubeURL)
        let cube = try CubeLUT(url: cubeURL, category: "Probe")
        let store = EditDocumentStore(package: package, lease: lease)
        await store.setEmbeddedLookBytes([cube.lutID.raw: cubeBytes])
        var document = EditDocument()
        document.lut = .init(lutID: cube.lutID)
        try await store.save(document, for: reference)
        let revision = try package.readEditRevision(for: asset)
        let embedded = try package.readEmbeddedLook(revision.lookReferences[0])
        try FileManager.default.removeItem(at: cubeURL)
        let preferences = UserDefaults(suiteName: "kromora-audit-\(UUID())")!
        let library = LUTLibrary(
            preferences: preferences, userLookFolderURL: root, includeBundled: false)
        let resolver = LookSelectionCoordinator(library: library)
        let reopenedStore = EditDocumentStore(package: package, lease: lease)
        let loaded = await reopenedStore.load(for: reference)
        print(
            "looks: embeddedBytesMatch=\(embedded == cubeBytes) freshLoadReady=\(loaded.status == .ready) runtimeResolverFoundLook=\(resolver.resolve(loaded.document.lut.lutID) != nil)"
        )
        var next = loaded.document
        next.light.exposure = 0.5
        try await reopenedStore.save(next, for: reference)
        print(
            "looks: embeddedReferencesAfterOrdinaryEdit=\(try package.readEditRevision(for: asset).lookReferences.count)"
        )
        await library.shutdown()
    }
}
