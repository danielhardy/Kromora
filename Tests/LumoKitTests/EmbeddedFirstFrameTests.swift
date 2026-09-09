import CoreGraphics
import AppKit
import Metal
import XCTest

@testable import LumoKit

/// Holds one embedded-frame extraction at a real suspension point. The stale-drop test releases
/// this gate only after the next source has installed its own provisional frame, so it models a
/// late extraction completion without depending on wall-clock ordering.
private actor EmbeddedFirstFrameGate {
    private let firstImage: NSImage
    private let images: [String: NSImage]
    private var hasGatedFirstExtraction = false
    private var parkedExtraction: CheckedContinuation<NSImage?, Never>?
    private(set) var requestedURLs: [URL] = []
    private(set) var completedURLs: [URL] = []

    init(firstImage: NSImage, images: [String: NSImage]) {
        self.firstImage = firstImage
        self.images = images
    }

    func extract(_ url: URL) async -> NSImage? {
        requestedURLs.append(url)
        if !hasGatedFirstExtraction {
            hasGatedFirstExtraction = true
            let image = await withCheckedContinuation { continuation in
                parkedExtraction = continuation
            }
            completedURLs.append(url)
            return image
        }
        completedURLs.append(url)
        return images[url.lastPathComponent]
    }

    func releaseGatedExtraction() {
        parkedExtraction?.resume(returning: firstImage)
        parkedExtraction = nil
    }

    func hasCompleted(named name: String) -> Bool {
        completedURLs.contains { $0.lastPathComponent == name }
    }
}

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

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "published state did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func embeddedImage(
        width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat
    ) throws -> NSImage {
        let cgImage = try Fixtures.makeCGImage(
            width: width, height: height, red: red, green: green, blue: blue
        )
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
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

    func testEmbeddedFirstFrameStaleDropOnNavigation() async throws {
        let first = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "first.ARW", in: tempDirectory
        )
        let second = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "second.ARW", in: tempDirectory
        )
        let firstImage = try embeddedImage(width: 3, height: 2, red: 0.9, green: 0.1, blue: 0.1)
        let secondImage = try embeddedImage(width: 5, height: 2, red: 0.1, green: 0.1, blue: 0.9)
        let gate = EmbeddedFirstFrameGate(
            firstImage: firstImage,
            images: [first.lastPathComponent: firstImage, second.lastPathComponent: secondImage]
        )
        let fake = FakeRenderEngine(previewResult: try Fixtures.makeCGImage(
            width: 2, height: 2, red: 0.2, green: 0.8, blue: 0.2
        ))
        await fake.gatePreviews()
        let viewModel = makeAppViewModel(
            engine: fake,
            embeddedFirstFrameProvider: { url in await gate.extract(url) }
        )
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let firstIndex = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.url == first }
        )
        let secondIndex = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.url == second }
        )

        viewModel.selectCollectionImage(at: firstIndex)
        try await waitUntil("the first extraction to be gated") {
            await gate.requestedURLs.count == 1
        }

        // A is still extracting when navigation selects B. B's own frame must be the only
        // provisional publication that reaches the surface during this transition.
        viewModel.selectCollectionImage(at: secondIndex)
        try await waitUntil("the second extraction") {
            await gate.hasCompleted(named: second.lastPathComponent)
        }
        try await waitUntil("the second source to install") {
            viewModel.sourceURL?.lastPathComponent == second.lastPathComponent
        }
        try await waitUntil("the second provisional frame") {
            viewModel.previewState == .loading && viewModel.previewSurface.image?.extent.width == 5
        }
        let secondProvisionalRevision = viewModel.previewSurface.revision

        // Complete A after B is visible. The cancelled extraction still returns its late JPEG,
        // which exercises the main-actor stale guards rather than a timing-dependent race.
        await gate.releaseGatedExtraction()
        try await waitUntil("the stale first extraction to complete") {
            await gate.hasCompleted(named: first.lastPathComponent)
        }

        await fake.releasePreviews()
        try await waitUntil("the second settled preview") {
            viewModel.sourceURL?.lastPathComponent == second.lastPathComponent
                && viewModel.previewState == .ready
        }

        XCTAssertEqual(
            viewModel.previewSurface.revision, secondProvisionalRevision + 1,
            "the late first-photo JPEG must not publish an extra surface frame"
        )
        let secondPreviewRequests = await fake.previewRequests.filter {
            guard case .url(let url) = $0.source?.backing else { return false }
            return url.lastPathComponent == second.lastPathComponent
        }
        XCTAssertEqual(secondPreviewRequests.count, 1, "B's normal settled open still proceeds")
    }

    /// Opt-in hardware timing for a real ARW. This reports both milestones without imposing a
    /// machine-specific threshold: the deterministic gate above owns the race regression, while
    /// this lane records the actual provisional-to-settled behavior on a local camera fixture.
    func testOptInRealEngineEmbeddedFirstFrameTiming() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_RAW_FIXTURE_DIR"] != nil,
            "set LUMO_RAW_FIXTURE_DIR to run the real-ARW embedded-frame timing test"
        )
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable")
        }
        guard let source = Fixtures.localRAWURLs.first(where: {
            $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("DSC01172") == .orderedSame
        }) else {
            throw XCTSkip("DSC01172.ARW is not present in LUMO_RAW_FIXTURE_DIR")
        }

        let viewModel = makeAppViewModel(engine: RenderEngine())
        let start = DispatchTime.now().uptimeNanoseconds
        viewModel.openImage(url: source)

        var provisionalMS: Double?
        let provisionalDeadline = Date().addingTimeInterval(60)
        while provisionalMS == nil && viewModel.previewState != .ready {
            if viewModel.previewState == .loading, viewModel.previewSurface.image != nil {
                provisionalMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            } else {
                if Date() > provisionalDeadline {
                    throw TestSynchronizationError.timedOut(
                        "the real embedded first frame", "no provisional pixels were presented"
                    )
                }
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        try await waitUntil("the real settled RAW preview", timeout: 60) {
            viewModel.previewState == .ready
        }
        let settledMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertNotNil(provisionalMS, "the real ARW should present its embedded JPEG while loading")
        print(
            String(
                format: "\n=== LUMO-330 real ARW embedded first frame timing ===\nprovisional_ms=%@ settled_ms=%.2f provisional_to_settled_ms=%.2f",
                provisionalMS.map { String(format: "%.2f", $0) } ?? "unobserved",
                settledMS, settledMS - (provisionalMS ?? settledMS)
            )
        )
    }
}
