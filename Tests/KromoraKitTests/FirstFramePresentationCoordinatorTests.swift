import CoreImage
import XCTest

@testable import KromoraKit

@MainActor
final class FirstFramePresentationCoordinatorTests: TempDirectoryTestCase {
    private let assetID = PhotoAssetID.imported(UUID())
    private let identity = FrameFixtures.identity()

    private func makeParts(
        budget: Duration = .milliseconds(20), holdsLookup: Bool = false
    ) -> (PreviewPresentationCoordinator, FirstFramePresentationCoordinator) {
        let directory = tempDirectory.appendingPathComponent("first-frame-\(UUID().uuidString)")
        let presentation = PreviewPresentationCoordinator(
            store: LatestPreviewFrameStore(directory: directory, capBytes: 10_000_000),
            storedFrameReader: holdsLookup
                ? Self.neverFinishingReader : PreviewPresentationCoordinator.readStoredFrame
        )
        return (presentation, FirstFramePresentationCoordinator(
            presentation: presentation, fallbackBudget: budget))
    }

    private static let neverFinishingReader: PreviewPresentationCoordinator.StoredFrameReader = {
        _, _ in
        try? await Task.sleep(for: .seconds(30))
        return (hit: nil, corrupt: false)
    }

    private func thumbnail(
        source: PreviewPresentationCoordinator.CandidateSource = .originalThumbnail,
        generation: UInt64 = 1
    ) -> FirstFramePresentationCoordinator.DeferredThumbnail {
        .init(
            image: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)),
            source: source, assetID: assetID, identity: identity,
            generation: generation, nativeExtent: CGSize(width: 4, height: 4))
    }

    func testStaleGenerationThumbnailIsNeverReleased() {
        let (presentation, first) = makeParts()
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 2, allowsSourceGeometry: true)
        first.stage(thumbnail: thumbnail(generation: 1))
        XCTAssertNil(first.takeDeferredThumbnail(for: 1))
        XCTAssertNil(first.takeDeferredThumbnail(for: 2))
    }

    func testOriginalThumbnailWaitsForSourceGeometryButEditedDoesNot() {
        let (presentation, first) = makeParts()
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1, allowsSourceGeometry: false)
        first.stage(thumbnail: thumbnail(source: .originalThumbnail))
        XCTAssertNil(first.takeDeferredThumbnail(for: 1))
        first.stage(thumbnail: thumbnail(source: .editedThumbnail))
        XCTAssertEqual(first.takeDeferredThumbnail(for: 1)?.source, .editedThumbnail)
        XCTAssertNil(first.deferredThumbnail)
    }

    func testStoredFrameHitDiscardsDeferredCandidates() {
        let (presentation, first) = makeParts()
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1, allowsSourceGeometry: true)
        first.stage(thumbnail: thumbnail())
        let release = first.storedFrameLookupFinished(generation: 1, hit: true)
        XCTAssertNil(release.thumbnail)
        XCTAssertNil(release.embedded)
        XCTAssertNil(first.deferredThumbnail)
    }

    func testStoredFrameMissReleasesThumbnail() {
        let (presentation, first) = makeParts()
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1, allowsSourceGeometry: true)
        first.stage(thumbnail: thumbnail())
        let release = first.storedFrameLookupFinished(generation: 1, hit: false)
        XCTAssertEqual(release.thumbnail?.generation, 1)
    }

    func testCroppedDocumentDiscardsSourceOnlyCandidates() {
        let (presentation, first) = makeParts()
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1, allowsSourceGeometry: true)
        first.stage(thumbnail: thumbnail(source: .originalThumbnail))
        var document = EditDocument()
        document.rotation = .clockwise90
        let release = first.sourceGeometryResolved(document: document, generation: 1)
        XCTAssertNil(release.thumbnail)
        XCTAssertNil(first.deferredThumbnail)
    }

    func testIdentityGeometryReleasesThumbnail() {
        let (presentation, first) = makeParts()
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1)
        first.stage(thumbnail: thumbnail(source: .originalThumbnail))
        let release = first.sourceGeometryResolved(document: EditDocument(), generation: 1)
        XCTAssertEqual(release.thumbnail?.source, .originalThumbnail)
    }

    func testFallbackExpiresOnlyWhileLookupLoading() async throws {
        let (presentation, first) = makeParts(budget: .milliseconds(10), holdsLookup: true)
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1, allowsSourceGeometry: true)
        presentation.beginStoredFrameLookup(
            assetID: assetID, identity: identity, generation: 1) { _ in }
        first.stage(thumbnail: thumbnail())
        let expired = expectation(description: "fallback released thumbnail")
        first.armFallback(generation: 1) { release in
            if release.thumbnail != nil { expired.fulfill() }
        }
        await fulfillment(of: [expired], timeout: 5)
    }

    func testCancelledFallbackNeverFires() async throws {
        let (presentation, first) = makeParts(budget: .milliseconds(10))
        presentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: 1, allowsSourceGeometry: true)
        first.stage(thumbnail: thumbnail())
        let fired = expectation(description: "must not fire")
        fired.isInverted = true
        first.armFallback(generation: 1) { _ in fired.fulfill() }
        first.resetForSource()
        await fulfillment(of: [fired], timeout: 0.2)
        XCTAssertNil(first.deferredThumbnail)
    }

    func testAlignedEmbeddedFirstFrameRotatesOnlyOnAxisMismatch() {
        let landscape = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 200))
        let portrait = PreviewSurface.alignedEmbeddedFirstFrame(
            landscape, to: CGSize(width: 200, height: 300))
        XCTAssertEqual(portrait.extent.size, CGSize(width: 200, height: 300))
        let same = PreviewSurface.alignedEmbeddedFirstFrame(
            landscape, to: CGSize(width: 600, height: 400))
        XCTAssertEqual(same.extent.size, landscape.extent.size)
    }
}
