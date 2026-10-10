import AppKit
import CoreImage
import MetalKit
import SwiftUI
import XCTest
@testable import KromoraKit

@MainActor
final class EditorCanvasViewportTests: TempDirectoryTestCase {
    private struct Scene: View {
        var model: AppViewModel
        var inset: CGFloat
        var body: some View {
            EditorCanvasViewport(surfaceSize: CGSize(width: 900, height: 700), bottomInset: inset) { _ in
                PreviewView(viewModel: model, surfaceHeight: 700)
            }
            .frame(width: 900, height: 700, alignment: .top)
        }
    }

    func testIntermediateInsetsKeepTheDrawableMountedAndReportOnlyTheStableRenderSize() throws {
        let model = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(model.previewSurface.present(
            CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 800, height: 600)),
            quality: .preview))
        let hosting = NSHostingView(rootView: Scene(model: model, inset: 130))
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        hosting.layoutSubtreeIfNeeded()
        let original = try XCTUnwrap(findPreview(in: hosting))
        var renderSizes: [CGSize] = []
        let coordinator = try XCTUnwrap(original.delegate as? PreviewSurfaceView.Coordinator)
        coordinator.onDrawableSizeChange = { renderSizes.append($0) }

        for crop in [true, false] {
            if crop { model.canvasState.beginCrop(using: .neutral) } else { model.canvasState.finishCrop() }
            let insets = stride(from: CGFloat(0), through: 130, by: 10).map { crop ? 130 - $0 : $0 }
            for inset in insets {
                hosting.rootView = Scene(model: model, inset: inset)
                hosting.layoutSubtreeIfNeeded()
                let view = try XCTUnwrap(findPreview(in: hosting))
                XCTAssertTrue(view === original, "crop/edit must keep the same Metal destination")
                XCTAssertEqual(view.bounds.size, CGSize(width: 884, height: 684))
                XCTAssertEqual(view.effectiveViewportSize, CGSize(width: 884, height: 684 - inset))
                // Exercise the native size callback too: quality admission receives the full
                // drawable, while navigation reconciles the intermediate visible viewport.
                coordinator.onDrawableSizeChange = { renderSizes.append($0) }
                coordinator.mtkView(view, drawableSizeWillChange: view.drawableSize)
                XCTAssertEqual(view.ignoresHits, crop)
            }
        }
        XCTAssertFalse(renderSizes.isEmpty)
        XCTAssertTrue(renderSizes.allSatisfy { $0 == renderSizes.first },
                      "viewport animation must not drive render resolution")
    }

    func testReducedMotionLayoutUsesEndpointViewportAndKeepsChromeMeasuredWhenHidden() throws {
        let model = makeAppViewModel(engine: FakeRenderEngine())
        model.previewSurface.present(
            CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 800, height: 600)))
        func scene(hidden: Bool) -> some View {
            EditorCanvasLayout(isChromeHidden: hidden, reduceMotion: true) { size in
                PreviewView(viewModel: model, surfaceHeight: size.height)
            } chrome: {
                Color.gray.frame(height: 130)
            }
        }
        let hosting = NSHostingView(rootView: scene(hidden: false))
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(findPreview(in: hosting))
        XCTAssertEqual(view.effectiveViewportSize.height, 554, accuracy: 0.001)
        hosting.rootView = scene(hidden: true)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(findPreview(in: hosting) === view)
        XCTAssertEqual(view.effectiveViewportSize.height, 684, accuracy: 0.001)
        hosting.rootView = scene(hidden: false)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.effectiveViewportSize.height, 554, accuracy: 0.001)
    }

    private func findPreview(in view: NSView) -> PreviewMTKView? {
        if let preview = view as? PreviewMTKView { return preview }
        return view.subviews.compactMap { findPreview(in: $0) }.first
    }
}
