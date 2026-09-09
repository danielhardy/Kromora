import CoreGraphics
import XCTest

@testable import LumoKit

/// The embedded-JPEG first frame is a presentation seam, not a render publication. These tests
/// keep the settled renderer gated long enough to observe that distinction deterministically.
@MainActor
final class EmbeddedFirstFrameTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "published state did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testEmbeddedFirstFrameProvisionalThenSettled() async throws {
        let raw = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "first.ARW", in: tempDirectory
        )
        let fake = FakeRenderEngine(previewResult: try Fixtures.makeCGImage(
            width: 2, height: 2, red: 0.1, green: 0.8, blue: 0.2
        ))
        await fake.gatePreviews()
        let viewModel = makeAppViewModel(engine: fake)

        viewModel.openImage(url: raw)
        try await waitUntil("the embedded first frame") {
            viewModel.previewState == .loading && viewModel.previewSurface.image != nil
        }

        XCTAssertEqual(viewModel.statusMessage, "Loading first.ARW...")
        XCTAssertNotNil(viewModel.sourceImage, "the transparent source marker remains authoritative")
        XCTAssertNil(viewModel.histogram, "supporting work must wait for the settled confirmation")
        let thumbnailRequestCount = await fake.thumbnailRequests.count
        XCTAssertEqual(thumbnailRequestCount, 0,
                       "the provisional frame must not admit an edited-thumbnail render")
        let provisionalRevision = viewModel.previewSurface.revision

        await fake.releasePreviews()
        try await waitUntil("the settled RAW preview") {
            viewModel.previewState == .ready
        }
        XCTAssertGreaterThan(viewModel.previewSurface.revision, provisionalRevision)
        XCTAssertEqual(
            viewModel.statusMessage,
            "first.ARW  4000\u{00D7}3000",
            "the settled frame restores the normal RAW status text"
        )
    }

    func testStandardOpenDoesNotPresentAnEmbeddedFirstFrame() async throws {
        let standard = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "standard.jpg", in: tempDirectory
        )
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)

        viewModel.openImage(url: standard)
        try await waitUntil("the standard preview") {
            viewModel.previewState == .ready
        }

        XCTAssertEqual(viewModel.statusMessage, "standard.jpg  16\u{00D7}12")
        let previewRequestCount = await fake.previewRequests.count
        XCTAssertEqual(previewRequestCount, 1)
    }
}
