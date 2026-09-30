import CryptoKit
import XCTest

@testable import KromoraKit

final class LookSignatureTests: TempDirectoryTestCase {
    private let id = LUTID(raw: "/Looks/A.cube")

    // MARK: - Values

    func testNoneAndUnresolvedAreDistinctValues() {
        XCTAssertNotEqual(LookSignature.none, LookSignature.unresolved(id: id))
        XCTAssertNotEqual(LookSignature.unresolved(id: id), LookSignature.resolved(id: id, contentHash: "h"))
        XCTAssertNotEqual(LookSignature.none, LookSignature.resolved(id: id, contentHash: "h"))
        XCTAssertNotEqual(
            LookSignature.unresolved(id: id).cacheComponent, LookSignature.none.cacheComponent
        )
    }

    func testAnUnresolvedSignatureNeverMatchesExactly() {
        let unresolved = LookSignature.unresolved(id: id)
        XCTAssertFalse(unresolved.permitsExactReuse)
        XCTAssertFalse(unresolved.isExactMatch(of: unresolved),
                       "two unresolved signatures say nothing about the missing bytes")
        XCTAssertFalse(unresolved.isExactMatch(of: .none))
        XCTAssertFalse(LookSignature.none.isExactMatch(of: unresolved))
    }

    func testResolvedMatchesOnlyTheSameIDAndContent() {
        let resolved = LookSignature.resolved(id: id, contentHash: "h1")
        XCTAssertTrue(resolved.isExactMatch(of: .resolved(id: id, contentHash: "h1")))
        XCTAssertFalse(resolved.isExactMatch(of: .resolved(id: id, contentHash: "h2")))
        XCTAssertFalse(resolved.isExactMatch(of: .resolved(id: LUTID(raw: "/B.cube"), contentHash: "h1")))
        XCTAssertFalse(resolved.isExactMatch(of: .unresolved(id: id)))
        XCTAssertTrue(LookSignature.none.isExactMatch(of: .none))
    }

    func testSignatureRoundTripsThroughCodable() throws {
        for value in [
            LookSignature.none, .resolved(id: id, contentHash: "abc"), .unresolved(id: id),
        ] {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(LookSignature.self, from: data), value)
        }
    }

    func testReferencesMatchesResolvedAndUnresolvedButNotNone() {
        let ids: Set = [id]
        XCTAssertTrue(LookSignature.resolved(id: id, contentHash: "h").references(anyOf: ids))
        XCTAssertTrue(LookSignature.unresolved(id: id).references(anyOf: ids))
        XCTAssertFalse(LookSignature.none.references(anyOf: ids))
        XCTAssertFalse(LookSignature.unresolved(id: LUTID(raw: "/B.cube")).references(anyOf: ids))
    }

    // MARK: - Derivation from a render

    func testSettingsWithoutAResolvedTableAreUnresolvedNotNone() throws {
        let cube = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "A.cube", in: tempDirectory)
        let lut = try CubeLUT(url: cube)

        let settings = LUTSettings(lutID: lut.lutID, intensity: 1)
        XCTAssertEqual(
            LookSignature(settings: settings, resolved: nil), .unresolved(id: lut.lutID))
        XCTAssertEqual(
            LookSignature(settings: settings, resolved: lut),
            .resolved(id: lut.lutID, contentHash: lut.contentHash))
        XCTAssertEqual(LookSignature(settings: .none, resolved: nil), .none)
        XCTAssertEqual(
            LookSignature(settings: LUTSettings(lutID: lut.lutID, intensity: 0), resolved: nil),
            .none, "a Look at zero strength contributes nothing, so it cannot be unresolved")
    }

    func testRenderRequestUsesTheSameDerivation() throws {
        let cube = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "A.cube", in: tempDirectory)
        let lut = try CubeLUT(url: cube)
        let source = ImageSource(
            backing: .data(Data("look-signature".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 8, height: 8))
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        XCTAssertEqual(
            RenderRequest(source: source, document: document, lut: lut, quality: .preview).lookSignature,
            lut.lookSignature)
        XCTAssertEqual(
            RenderRequest(source: source, document: document, quality: .preview).lookSignature,
            .unresolved(id: lut.lutID))
        XCTAssertEqual(
            RenderRequest(source: source, document: EditDocument(), quality: .preview).lookSignature, .none)
    }

    // MARK: - Live content identity

    func testLiveSignatureChangesWhenTableBytesChangeAtTheSameLUTID() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Look.cube", in: tempDirectory)
        let first = try CubeLUT(url: url)

        try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 3), named: "Look.cube", in: tempDirectory)
        let replaced = try CubeLUT(url: url)

        XCTAssertEqual(first.lutID, replaced.lutID, "precondition: same path, same identity")
        XCTAssertNotEqual(first.lookSignature, replaced.lookSignature)
        XCTAssertNotEqual(first.cacheFingerprint, replaced.cacheFingerprint)
    }

    func testRescanningIdenticalBytesYieldsAnEqualSignature() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Look.cube", in: tempDirectory)
        let first = try CubeLUT(url: url)
        let second = try CubeLUT(url: url)
        XCTAssertEqual(first.lookSignature, second.lookSignature)
        XCTAssertTrue(first.lookSignature.isExactMatch(of: second.lookSignature))
    }

    func testLiveHashIsTheSHA256OfTheFileBytesAndMatchesAPackageReference() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Look.cube", in: tempDirectory)
        let bytes = try Data(contentsOf: url)
        let lut = try CubeLUT(url: url)

        XCTAssertEqual(lut.contentHash, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(
            lut.contentHash, PortablePackageLookReference(data: bytes).contentHash,
            "a live Look and a package blob of the same file must share one identity")
    }

    func testSavedCommentsChangeTheHashEvenWhenTheTableIsUnchanged() throws {
        // Content-addressing is by file bytes, matching the package blob. A comment-only edit is a
        // (harmless) new identity, never a stale hit.
        let text = Fixtures.identityCubeText(size: 2)
        let url = try Fixtures.writeCube(text, named: "Look.cube", in: tempDirectory)
        let first = try CubeLUT(url: url)
        try Fixtures.writeCube("# note\n" + text, named: "Look.cube", in: tempDirectory)
        XCTAssertNotEqual(first.contentHash, try CubeLUT(url: url).contentHash)
    }

    // MARK: - Package revision

    func testPackageRevisionResolvesItsSignatureFromTheStoredReference() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Looks.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("look signature source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID,
            sourceFingerprint: .data(Data("look signature source".utf8), decoderVersion: "test"))
        let reference = EditSourceReference(
            assetID: .file(sourceURL), portableIdentity: identity, url: sourceURL)

        let lookBytes = Data(Fixtures.identityCubeText(size: 2).utf8)
        let lookID = LUTID(raw: "/Looks/Embedded.cube")
        let store = EditDocumentStore(package: package, lease: lease)
        await store.setEmbeddedLookBytes([lookID.raw: lookBytes])

        // A revision that embeds its Look.
        let withLook = EditDocument(lut: LUTSettings(lutID: lookID, intensity: 1))
        try await store.save(withLook, for: reference)
        let loaded = await store.load(for: reference)
        XCTAssertEqual(
            loaded.lookSignature,
            .resolved(id: lookID, contentHash: PortablePackageLookReference(data: lookBytes).contentHash))
        XCTAssertEqual(loaded.document, withLook, "no digest is added to the document")

        // A revision naming a Look whose bytes were never available has nothing to resolve.
        let missingID = LUTID(raw: "/Looks/Missing.cube")
        try await store.save(EditDocument(lut: LUTSettings(lutID: missingID, intensity: 1)), for: reference)
        let unresolved = await store.load(for: reference)
        XCTAssertEqual(unresolved.lookSignature, .unresolved(id: missingID))

        // And one with no Look is `.none`, not `.unresolved`.
        try await store.save(EditDocument(adjustments: [.exposure(ev: 0.3)]), for: reference)
        let none = await store.load(for: reference)
        XCTAssertEqual(none.lookSignature, .none)
    }

    // MARK: - Durable preview cache

    @MainActor
    func testAnUnresolvedRequestHasNoCacheKeyAndAnUnresolvedKeyNeverHits() throws {
        let cache = PreviewDiskCache(
            directory: tempDirectory.appendingPathComponent("previews"), capBytes: 10_000_000)
        let coordinator = PreviewPresentationCoordinator(cache: cache)
        let source = ImageSource(
            backing: .data(Data("cache-source".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24))
        let document = EditDocument(lut: LUTSettings(lutID: id, intensity: 1))

        let unresolvedRequest = RenderRequest(source: source, document: document, quality: .preview)
        XCTAssertNil(coordinator.cacheKey(for: unresolvedRequest))

        let forced = PreviewDiskCache.Key(
            identity: source.cacheIdentity, documentHash: document.editHash,
            look: .unresolved(id: id))
        let image = try Fixtures.makeCGImage(width: 32, height: 24)
        cache.write(image, for: forced)
        XCTAssertFalse(cache.contains(forced))
        XCTAssertNil(cache.read(for: forced))
    }

    func testNoneAndUnresolvedDoNotShareACacheEntry() throws {
        let cache = PreviewDiskCache(
            directory: tempDirectory.appendingPathComponent("previews"), capBytes: 10_000_000)
        let source = ImageSource(
            backing: .data(Data("cache-source-2".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24))
        func key(_ look: LookSignature) -> PreviewDiskCache.Key {
            PreviewDiskCache.Key(identity: source.cacheIdentity, documentHash: "d", look: look)
        }
        cache.write(try Fixtures.makeCGImage(width: 32, height: 24), for: key(.none))
        XCTAssertTrue(cache.contains(key(.none)))
        XCTAssertFalse(cache.contains(key(.unresolved(id: id))))
        XCTAssertNotEqual(
            key(.none).canonicalKeyString, key(.unresolved(id: id)).canonicalKeyString)
    }

    func testAResolvedKeyChangesWhenTheLookBytesChange() {
        let source = ImageSource(
            backing: .data(Data("cache-source-3".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24))
        func key(_ hash: String) -> PreviewDiskCache.Key {
            PreviewDiskCache.Key(
                identity: source.cacheIdentity, documentHash: "d",
                look: .resolved(id: id, contentHash: hash))
        }
        XCTAssertEqual(key("h1").canonicalKeyString, key("h1").canonicalKeyString)
        XCTAssertNotEqual(key("h1").canonicalKeyString, key("h2").canonicalKeyString)
    }
}
