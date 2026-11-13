import CoreImage
import Metal
import ObjectiveC

/// The completed, GPU-backed texture behind an engine-produced `CIImage`.
///
/// `RenderEngine.makeCIImage` already renders into a texture and wraps it; Core Image offers no
/// way to get that texture back out. The engine therefore attaches it to the image it returns, so
/// the presentation surface can draw the very texture the engine wrote instead of rendering the
/// image into a second one. The association is retained by the image, so the texture lives exactly
/// as long as any holder of that image object. Derived images (`transformed`, `cropped`) are new
/// objects and carry no texture, which routes them through the Core Image fallback.
enum CompletedFrameTexture {
    private final class Marker: Sendable {}
    private static let marker = Marker()

    private static var key: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(marker).toOpaque())
    }

    /// Attach `texture` to `image`. The texture must be complete: no command buffer may still be
    /// writing it.
    static func attach(_ texture: MTLTexture, to image: CIImage) {
        objc_setAssociatedObject(image, key, texture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func texture(of image: CIImage) -> MTLTexture? {
        objc_getAssociatedObject(image, key) as? MTLTexture
    }
}
