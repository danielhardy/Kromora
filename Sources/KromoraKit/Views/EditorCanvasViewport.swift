import SwiftUI

/// SwiftUI interpolates the viewport itself, rather than animating an AppKit layer's bounds.
/// The content receives every intermediate size; its Metal drawable remains the full surface.
struct EditorCanvasViewport<Content: View>: View, @MainActor Animatable {
    var surfaceSize: CGSize
    var bottomInset: CGFloat
    @ViewBuilder var content: (CGSize) -> Content

    var animatableData: CGFloat {
        get { bottomInset }
        set { bottomInset = newValue }
    }

    static func viewportSize(surfaceSize: CGSize, bottomInset: CGFloat) -> CGSize {
        CGSize(
            width: max(1, surfaceSize.width),
            height: max(1, surfaceSize.height - max(0, bottomInset))
        )
    }

    var body: some View {
        let viewport = Self.viewportSize(surfaceSize: surfaceSize, bottomInset: bottomInset)
        content(viewport)
            .frame(width: viewport.width, height: viewport.height, alignment: .top)
            .clipped()
            // Intermediate geometry is already interpolated. AppKit must apply it immediately.
            .transaction { $0.animation = nil }
    }
}

/// The strip stays mounted so its intrinsic height is available in crop mode too. Only its
/// presentation and the canvas viewport change; neither insertion nor removal drives layout.
struct EditorCanvasLayout<Canvas: View, Chrome: View>: View {
    var isChromeHidden: Bool
    /// Keeps the canvas at its with-chrome size while the chrome is hidden, so a handoff photo can
    /// fly to its final frame and the chrome arrives around it without resizing the canvas.
    var reservesChromeSpace = false
    var reduceMotion: Bool
    @ViewBuilder var canvas: (CGSize) -> Canvas
    @ViewBuilder var chrome: () -> Chrome
    @State private var chromeHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                EditorCanvasViewport(
                    surfaceSize: geometry.size,
                    bottomInset: isChromeHidden && !reservesChromeSpace ? 0 : chromeHeight
                ) { _ in
                    canvas(geometry.size)
                }
                .frame(maxHeight: .infinity, alignment: .top)

                chrome()
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        chromeHeight = $0
                    }
                    .offset(y: isChromeHidden && !reduceMotion ? chromeHeight : 0)
                    .opacity(isChromeHidden ? 0 : 1)
                    .allowsHitTesting(!isChromeHidden)
                    .accessibilityHidden(isChromeHidden)
                    .zIndex(1)
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isChromeHidden)
        }
    }
}
