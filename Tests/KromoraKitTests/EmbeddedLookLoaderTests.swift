import Foundation
import Synchronization
import XCTest
@testable import KromoraKit

/// KRMA-898: embedded Look bytes load off the main actor and reach the durable edit write in order.
final class EmbeddedLookLoaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddedLookLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Holds a worker read open until the test releases it.
    private final class Gate: Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        func waitUntilEntered() { entered.wait() }
        func wait() { entered.signal(); semaphore.wait() }
        func open() { semaphore.signal() }
    }

    private struct Harness {
        let store: EditDocumentStore
        let reference: EditSourceReference
        let lease: PortablePackageLease
        let package: PortableLibraryPackage
    }

    private func makeHarness() async throws -> Harness {
        let packageURL = tempDirectory.appendingPathComponent("Looks.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("loader source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID, sourceFingerprint: .data(Data("loader source".utf8), decoderVersion: "test"))
        let reference = EditSourceReference(assetID: .file(sourceURL), portableIdentity: identity, url: sourceURL)
        return Harness(
            store: EditDocumentStore(package: package, lease: lease), reference: reference,
            lease: lease, package: package)
    }

    private func bytes(_ tag: String) -> Data { Data((tag + Fixtures.identityCubeText(size: 2)).utf8) }

    private func hash(_ data: Data) -> String { PortablePackageLookReference(data: data).contentHash }

    func testReadsRunOffMainAndDoNotBlockTheMainActor() async throws {
        let gate = Gate()
        let onMain = Mutex(false)
        let url = tempDirectory.appendingPathComponent("A.cube")
        let task = Task { @MainActor in
            await EmbeddedLookLoader.load([.init(id: "A", url: url)], retaining: []) { _ in
                if Thread.isMainThread { onMain.withLock { $0 = true } }
                gate.wait()
                return Data("a".utf8)
            }
        }
        await Task.detached { gate.waitUntilEntered() }.value
        // The read is in flight; an independent main-actor job still runs.
        let sentinel = await MainActor.run { true }
        XCTAssertTrue(sentinel)
        gate.open()
        let values = await task.value
        XCTAssertEqual(values["A"], Data("a".utf8))
        XCTAssertFalse(onMain.withLock { $0 })
    }

    func testSlowSnapshotCannotOverwriteNewerSnapshot() async throws {
        let h = try await makeHarness()
        defer { try? h.lease.release() }
        let gate = Gate()
        let aBytes = bytes("A"), bBytes = bytes("B")
        let aURL = tempDirectory.appendingPathComponent("A.cube")
        let bURL = tempDirectory.appendingPathComponent("B.cube")
        await h.store.loadEmbeddedLooks([.init(id: "look", url: aURL)], retaining: []) { _ in
            gate.wait(); return aBytes
        }
        await Task.detached { gate.waitUntilEntered() }.value
        await h.store.loadEmbeddedLooks([.init(id: "look", url: bURL)], retaining: []) { _ in bBytes }
        await h.store.awaitEmbeddedLooks()
        gate.open()
        try await Task.sleep(for: .milliseconds(50))

        let id = LUTID(raw: "look")
        try await h.store.save(EditDocument(lut: LUTSettings(lutID: id, intensity: 1)), for: h.reference)
        let loaded = await h.store.load(for: h.reference)
        XCTAssertEqual(loaded.lookSignature, .resolved(id: id, contentHash: hash(bBytes)))
    }

    func testSaveWaitsForPendingLoadAndPackageOutlivesTheExternalFile() async throws {
        let h = try await makeHarness()
        defer { try? h.lease.release() }
        let gate = Gate()
        let lookBytes = bytes("X")
        let url = tempDirectory.appendingPathComponent("X.cube")
        try lookBytes.write(to: url)
        await h.store.loadEmbeddedLooks([.init(id: "x", url: url)], retaining: []) {
            gate.wait(); return try? Data(contentsOf: $0)
        }
        await Task.detached { gate.waitUntilEntered() }.value
        let id = LUTID(raw: "x")
        let saving = Task {
            try await h.store.save(EditDocument(lut: LUTSettings(lutID: id, intensity: 1)), for: h.reference)
        }
        gate.open()
        try await saving.value
        try FileManager.default.removeItem(at: url)

        let reopened = EditDocumentStore(package: h.package, lease: h.lease)
        let loaded = await reopened.load(for: h.reference)
        XCTAssertEqual(loaded.lookSignature, .resolved(id: id, contentHash: hash(lookBytes)))
    }

    func testUnreadableLookDoesNotBlockOthers() async throws {
        let h = try await makeHarness()
        defer { try? h.lease.release() }
        let good = bytes("G")
        let goodURL = tempDirectory.appendingPathComponent("good.cube")
        let badURL = tempDirectory.appendingPathComponent("missing.cube")
        await h.store.loadEmbeddedLooks(
            [.init(id: "bad", url: badURL), .init(id: "good", url: goodURL)], retaining: []
        ) { $0 == goodURL ? good : nil }
        await h.store.awaitEmbeddedLooks()

        let goodID = LUTID(raw: "good"), badID = LUTID(raw: "bad")
        try await h.store.save(EditDocument(lut: LUTSettings(lutID: goodID, intensity: 1)), for: h.reference)
        let goodLoaded = await h.store.load(for: h.reference)
        XCTAssertEqual(goodLoaded.lookSignature, .resolved(id: goodID, contentHash: hash(good)))
        try await h.store.save(EditDocument(lut: LUTSettings(lutID: badID, intensity: 1)), for: h.reference)
        let badLoaded = await h.store.load(for: h.reference)
        XCTAssertEqual(badLoaded.lookSignature, .unresolved(id: badID))
    }

    func testCancelledLoadNeverPublishes() async throws {
        let h = try await makeHarness()
        defer { try? h.lease.release() }
        let gate = Gate()
        let data = bytes("C")
        await h.store.loadEmbeddedLooks([.init(id: "c", url: tempDirectory)], retaining: []) { _ in
            gate.wait(); return data
        }
        await Task.detached { gate.waitUntilEntered() }.value
        await h.store.cancelEmbeddedLookLoading()
        gate.open()
        try await Task.sleep(for: .milliseconds(50))

        let id = LUTID(raw: "c")
        try await h.store.save(EditDocument(lut: LUTSettings(lutID: id, intensity: 1)), for: h.reference)
        let loaded = await h.store.load(for: h.reference)
        XCTAssertEqual(loaded.lookSignature, .unresolved(id: id))
    }
}
