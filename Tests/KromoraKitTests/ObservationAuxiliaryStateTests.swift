import SwiftUI
import XCTest

@testable import KromoraKit

/// KRMA-979: white-balance sampler, RAW capability and Auto/Look status state live in their own
/// `@Observable` objects, so their writes do not invalidate unrelated views.
@MainActor
final class ObservationAuxiliaryStateTests: TempDirectoryTestCase {
    private func makeColorAndLoupeAndStatus(
        _ viewModel: AppViewModel
    ) -> (color: BodyCounter, loupe: BodyCounter, preview: BodyCounter, views: [NSView]) {
        let color = BodyCounter(), loupe = BodyCounter(), preview = BodyCounter()
        let views: [NSView] = [
            host(MirrorProbeView(viewModel: viewModel, counter: color, reads: MirrorReadSet.color)),
            host(MirrorProbeView(viewModel: viewModel, counter: loupe, reads: MirrorReadSet.loupe)),
            host(PreviewMirrorView(viewModel: viewModel, counter: preview)),
        ]
        return (color, loupe, preview, views)
    }

    func testSamplerPointReEvaluatesOnlyTheLoupe() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        RenderDiagnostics.reset()
        let status = host(StatusBar(
            viewModel: viewModel, photosImportCoordinator: viewModel.photosImportCoordinator,
            export: viewModel.export, collection: viewModel.collection))
        let probes = makeColorAndLoupeAndStatus(viewModel)
        let colorBefore = probes.color.count, loupeBefore = probes.loupe.count
        let previewBefore = probes.preview.count
        let statusBefore = RenderDiagnostics.snapshot.toolbarBodyEvaluations

        viewModel.whiteBalance.samplerPoint = CGPoint(x: 10, y: 20)
        drainMainActor()

        XCTAssertEqual(probes.loupe.count - loupeBefore, 1)
        XCTAssertEqual(probes.color.count, colorBefore)
        XCTAssertEqual(probes.preview.count, previewBefore)
        XCTAssertEqual(RenderDiagnostics.snapshot.toolbarBodyEvaluations, statusBefore)
        withExtendedLifetime((status, probes.views)) {}
    }

    func testAutoProgressReEvaluatesStatusBarOnly() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        RenderDiagnostics.reset()
        let status = host(StatusBar(
            viewModel: viewModel, photosImportCoordinator: viewModel.photosImportCoordinator,
            export: viewModel.export, collection: viewModel.collection))
        let probes = makeColorAndLoupeAndStatus(viewModel)
        let colorBefore = probes.color.count, loupeBefore = probes.loupe.count
        let statusBefore = RenderDiagnostics.snapshot.toolbarBodyEvaluations

        viewModel.autoLook.publishAuto(.analyzing, progress: 0.4)
        drainMainActor()

        XCTAssertEqual(RenderDiagnostics.snapshot.toolbarBodyEvaluations, statusBefore + 1)
        XCTAssertEqual(probes.color.count, colorBefore)
        XCTAssertEqual(probes.loupe.count, loupeBefore)
        withExtendedLifetime((status, probes.views)) {}
    }

    func testAutoStateClampsProgress() {
        let state = AutoLookStatusState()
        state.publishAuto(.analyzing, progress: 2)
        XCTAssertEqual(state.autoAdjustmentProgress, 1)
        state.publishAuto(.cancelled, progress: nil)
        XCTAssertNil(state.autoAdjustmentProgress)
    }

    func testSamplerBeginAndEndClearThePointerState() {
        let state = WhiteBalanceSamplerState()
        state.begin()
        state.samplerPoint = .zero
        XCTAssertTrue(state.isSampling)
        state.end()
        XCTAssertFalse(state.isSampling)
        XCTAssertNil(state.samplerPoint)
        XCTAssertNil(state.loupeImage)
    }

    /// KRMA-980: the root is `@Observable`; no `@Published` declaration or `ObservableObject`
    /// conformance remains. Declaration scan only, so comment mentions do not count.
    func testAppViewModelHasNoPublishedOrObservableObject() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/KromoraKit/ViewModels/AppViewModel.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let published = try NSRegularExpression(pattern: #"^\s*@Published\b"#, options: .anchorsMatchLines)
        let range = NSRange(source.startIndex..., in: source)
        XCTAssertEqual(published.numberOfMatches(in: source, range: range), 0)
        let declaration = try NSRegularExpression(
            pattern: #"^@MainActor @Observable\s*\npublic final class AppViewModel: (?!ObservableObject)"#,
            options: .anchorsMatchLines)
        XCTAssertEqual(declaration.numberOfMatches(in: source, range: range), 1)
    }
}
