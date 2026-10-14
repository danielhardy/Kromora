import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

/// KRMA-972: records how many times each inspector/chrome view body re-evaluates when one
/// `AppViewModel` property changes. The numbers feed the Baseline table in
/// `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md`; counts are logical evaluations, not timings.
///
/// The test asserts only determinism and two positive controls. It deliberately does not assert
/// that unrelated views re-evaluate: that is the over-invalidation the migration removes.
@MainActor
final class ObservationBodyBaselineTests: TempDirectoryTestCase {
    enum Mutation: String, CaseIterable {
        case document, statusMessage, histogram, showPhotoNames

        @MainActor func apply(to viewModel: AppViewModel) {
            switch self {
            case .document:
                viewModel.updateDocument { $0.light.exposure = 0.5 }
            case .statusMessage:
                viewModel.statusMessage = "Baseline probe message"
            case .histogram:
                viewModel.info.histogram = HistogramData(
                    red: [1], green: [1], blue: [1], luma: [1])
            case .showPhotoNames:
                viewModel.settings.showPhotoNames.toggle()
            }
        }
    }

    enum Subject: String, CaseIterable {
        case statusBar = "StatusBar"
        case info = "InfoInspectorView"
        case light = "LightInspectorView"
        case color = "ColorInspectorView"
        case effects = "EffectsInspectorView"
        case preview = "PreviewView"

        var kind: String {
            switch self {
            case .statusBar, .info: "real"
            default: "mirror"
            }
        }
    }

    /// Body evaluations caused by one `mutation` on a fresh view model, after layout settled.
    private func delta(_ subject: Subject, _ mutation: Mutation) -> Int {
        delta(subject) { mutation.apply(to: $0) }
    }

    private func delta(_ subject: Subject, mutation: @MainActor (AppViewModel) -> Void) -> Int {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let counter = BodyCounter()
        let hosting: NSView
        switch subject {
        case .statusBar:
            hosting = host(StatusBar(
                viewModel: viewModel, photosImportCoordinator: viewModel.photosImportCoordinator,
                export: viewModel.export, collection: viewModel.collection))
        case .info:
            hosting = host(InfoInspectorView(
                viewModel: viewModel, inspectorState: viewModel.inspectorState))
        case .light:
            hosting = host(MirrorProbeView(
                viewModel: viewModel, counter: counter, reads: MirrorReadSet.light))
        case .color:
            hosting = host(MirrorProbeView(
                viewModel: viewModel, counter: counter, reads: MirrorReadSet.color))
        case .effects:
            hosting = host(MirrorProbeView(
                viewModel: viewModel, counter: counter, reads: MirrorReadSet.effects))
        case .preview:
            hosting = host(PreviewMirrorView(viewModel: viewModel, counter: counter))
        }
        let before = evaluations(subject, counter)
        mutation(viewModel)
        drainMainActor()
        let after = evaluations(subject, counter)
        withExtendedLifetime(hosting) {}
        return after - before
    }

    private func evaluations(_ subject: Subject, _ counter: BodyCounter) -> Int {
        switch subject {
        case .statusBar: RenderDiagnostics.snapshot.toolbarBodyEvaluations
        case .info: RenderDiagnostics.snapshot.inspectorBodyEvaluations
        default: counter.count
        }
    }

    private func measureAll() -> [String: Int] {
        var table: [String: Int] = [:]
        for subject in Subject.allCases {
            for mutation in Mutation.allCases {
                RenderDiagnostics.reset()
                table["\(subject.rawValue) (\(subject.kind)) / \(mutation.rawValue)"] =
                    delta(subject, mutation)
            }
        }
        return table
    }

    func testBaselineIsDeterministicAndPrintsTable() {
        let first = measureAll()
        let second = measureAll()
        XCTAssertEqual(first.count, Subject.allCases.count * Mutation.allCases.count)
        XCTAssertEqual(first, second, "body counts must be identical across fresh view models")
        for key in first.keys.sorted() {
            print("BODY-BASELINE | \(key) | \(first[key] ?? -1)")
        }
    }

    func testMirrorReadingDocumentReEvaluatesWhenDocumentChanges() {
        XCTAssertGreaterThan(delta(.light, .document), 0)
    }

    func testStatusBarReEvaluatesWhenStatusMessageChanges() {
        XCTAssertGreaterThan(delta(.statusBar, .statusMessage), 0)
    }

    /// KRMA-978: status text and the portable query invalidate only views that read those values.
    func testStatusAndLibraryQueryInvalidateOnlyTheirReaders() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        RenderDiagnostics.reset()

        let statusHosting = host(StatusBar(
            viewModel: viewModel, photosImportCoordinator: viewModel.photosImportCoordinator,
            export: viewModel.export, collection: viewModel.collection))

        let cullingCounter = BodyCounter()
        let cullingHosting = host(MirrorProbeView(
            viewModel: viewModel,
            counter: cullingCounter,
            reads: [MirrorRead("portableQuery") { _ = $0.libraryPresentation.query }]))
        let facetCounter = BodyCounter()
        let facetHosting = host(MirrorProbeView(
            viewModel: viewModel,
            counter: facetCounter,
            reads: [MirrorRead("portableQuery") { _ = $0.libraryPresentation.query }]))
        let lightCounter = BodyCounter()
        let lightHosting = host(MirrorProbeView(
            viewModel: viewModel, counter: lightCounter, reads: MirrorReadSet.light))
        let colorCounter = BodyCounter()
        let colorHosting = host(MirrorProbeView(
            viewModel: viewModel, counter: colorCounter, reads: MirrorReadSet.color))
        let effectsCounter = BodyCounter()
        let effectsHosting = host(MirrorProbeView(
            viewModel: viewModel, counter: effectsCounter, reads: MirrorReadSet.effects))
        let previewCounter = BodyCounter()
        let previewHosting = host(PreviewMirrorView(
            viewModel: viewModel, counter: previewCounter))

        let statusBefore = RenderDiagnostics.snapshot.toolbarBodyEvaluations
        let cullingBefore = cullingCounter.count
        let facetBefore = facetCounter.count
        let lightBefore = lightCounter.count
        let colorBefore = colorCounter.count
        let effectsBefore = effectsCounter.count
        let previewBefore = previewCounter.count

        viewModel.statusMessage = "Status changed"
        drainMainActor()

        XCTAssertEqual(RenderDiagnostics.snapshot.toolbarBodyEvaluations - statusBefore, 1)
        XCTAssertEqual(cullingCounter.count - cullingBefore, 0)
        XCTAssertEqual(facetCounter.count - facetBefore, 0)
        XCTAssertEqual(lightCounter.count - lightBefore, 0)
        XCTAssertEqual(colorCounter.count - colorBefore, 0)
        XCTAssertEqual(effectsCounter.count - effectsBefore, 0)
        XCTAssertEqual(previewCounter.count - previewBefore, 1)

        let toolbarAfterStatus = RenderDiagnostics.snapshot.toolbarBodyEvaluations
        viewModel.portableQuery.searchText = "query"
        drainMainActor()

        XCTAssertEqual(
            RenderDiagnostics.snapshot.toolbarBodyEvaluations, toolbarAfterStatus,
            "a library query change must not re-evaluate the status bar")
        XCTAssertEqual(cullingCounter.count - cullingBefore, 1)
        XCTAssertEqual(facetCounter.count - facetBefore, 1)

        withExtendedLifetime((statusHosting, cullingHosting, facetHosting, lightHosting,
                              colorHosting, effectsHosting, previewHosting)) {}
    }

    /// KRMA-973: the mask and retouch interaction states are `@Observable` children. Pointer-rate
    /// changes to them must not re-evaluate the inspector mirrors or Info inspector.
    func testInteractionStateChangesDoNotReEvaluateInspectors() {
        let mutations: [(String, @MainActor (AppViewModel) -> Void)] = [
            ("maskInteractionState.hoverPoint", {
                $0.maskInteractionState.updateHoverPoint(CGPoint(x: 0.4, y: 0.4))
            }),
            ("maskInteractionState.brushRadius", { $0.maskInteractionState.brushRadius = 0.2 }),
            ("retouchInteractionState.radius", { $0.retouchInteractionState.radius = 0.05 }),
            ("retouchInteractionState.hover", {
                $0.retouchInteractionState.hover(UUID(), at: CGPoint(x: 0.1, y: 0.1))
            }),
        ]
        for subject in [Subject.info, .light, .color, .effects] {
            for (name, mutation) in mutations {
                RenderDiagnostics.reset()
                let count = delta(subject, mutation: mutation)
                print("BODY-BASELINE | \(subject.rawValue) (\(subject.kind)) / \(name) | \(count)")
                XCTAssertEqual(count, 0, "\(subject.rawValue) re-evaluated for \(name)")
            }
        }
    }

    /// KRMA-977: `info.histogram` is read only by the Info inspector (and the preview overlay),
    /// so a histogram refresh no longer re-evaluates the toolbar or the editor inspectors.
    func testHistogramRefreshReEvaluatesInfoInspectorOnly() {
        RenderDiagnostics.reset()
        XCTAssertGreaterThan(delta(.info, .histogram), 0)
        for subject in [Subject.statusBar, .light, .color, .effects] {
            RenderDiagnostics.reset()
            XCTAssertEqual(delta(subject, .histogram), 0, "\(subject.rawValue)")
        }
    }

    /// KRMA-975: `KromoraSettings` is `@Observable`, so a photo-name toggle reaches only views
    /// that read it.
    func testPhotoNamesToggleReEvaluatesOnlyItsReaders() {
        for subject in Subject.allCases {
            RenderDiagnostics.reset()
            XCTAssertEqual(delta(subject, .showPhotoNames), 0, "\(subject.rawValue)")
        }
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let counter = BodyCounter()
        let hosting = host(PhotoNamesMirrorView(settings: viewModel.settings, counter: counter))
        let before = counter.count
        viewModel.settings.showPhotoNames.toggle()
        drainMainActor()
        XCTAssertGreaterThan(counter.count - before, 0)
        withExtendedLifetime(hosting) {}
    }

    /// KRMA-981: with a photo open and the Light tab selected, the real inspector shell does not
    /// read `document`, so Light, Color and Effects mutations leave its body count unchanged. The
    /// mounted tab itself still re-evaluates (all sections live in the one `document` property).
    func testInspectorShellDoesNotReadDocumentWithAPhotoOpen() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "shell-probe.png", in: tempDirectory)
        viewModel.openImage(url: image)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceImage == nil || viewModel.previewSurface.image == nil {
            XCTAssertLessThan(Date(), deadline, "timed out opening the photo")
            if Date() > deadline { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.inspectorTab = .light

        let hosting = host(InfoInspectorView(
            viewModel: viewModel, inspectorState: viewModel.inspectorState))
        let mutations: [(String, @MainActor (AppViewModel) -> Void)] = [
            ("light", { vm in vm.updateDocument { $0.light.exposure += 0.25 } }),
            ("color", { vm in vm.updateDocument { $0.color.saturation += 0.1 } }),
            ("effects", { vm in vm.updateDocument { $0.effects.clarity += 10 } }),
        ]
        for (name, mutate) in mutations {
            drainMainActor(seconds: 0.5)
            let before = RenderDiagnostics.snapshot.inspectorBodyEvaluations
            mutate(viewModel)
            drainMainActor(seconds: 0.5)
            let delta = RenderDiagnostics.snapshot.inspectorBodyEvaluations - before
            print("BODY-BASELINE | InfoInspectorView (real, Light tab) / \(name) | \(delta)")
            XCTAssertEqual(delta, 0, "shell re-evaluated for a \(name) mutation")
        }
        withExtendedLifetime(hosting) {}
    }
}
