import AppKit
import Metal

@testable import KromoraKit

extension PreviewSurfaceView.Coordinator {
    /// Renders a retained texture offscreen and blocks until the GPU finishes. The wait lives in
    /// the test target so production code never blocks on GPU completion.
    func renderRetainedTexture(
        surface: PreviewSurface, navigation: CanvasNavigation, destinationSize: CGSize,
        viewSpaceRotationAngle: Double = 0,
        appearance: NSAppearance? = nil,
        viewportSize: CGSize? = nil
    ) -> MTLTexture? {
        guard
            let render = commitRetainedTextureRender(
                surface: surface, navigation: navigation, destinationSize: destinationSize,
                viewSpaceRotationAngle: viewSpaceRotationAngle, appearance: appearance,
                viewportSize: viewportSize)
        else { return nil }
        render.commandBuffer.waitUntilCompleted()
        return render.commandBuffer.status == .completed ? render.texture : nil
    }
}
