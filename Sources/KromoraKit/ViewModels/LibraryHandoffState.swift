import AppKit
import Observation
import SwiftUI

/// Presentation state for the Library-to-Edit photo handoff.
///
/// The handoff is a foreground "flight" image drawn above the window while the workspace
/// underneath switches. It owns no selection, navigation, or loading state: opening is still
/// asynchronous and asset-ID based, and the flight only decorates the change.
@MainActor @Observable
final class LibraryHandoffState {
    /// One in-flight photo, positioned in SwiftUI global (window) coordinates.
    struct Flight: Equatable {
        var image: NSImage
        var frame: CGRect
        var cornerRadius: CGFloat
        var opacity: Double
    }

    /// The photo currently crossing between the Library cell and the Edit canvas.
    var flight: Flight?
    /// True from the start of an entrance until the photo has reached the canvas. The editor
    /// holds its inspector and filmstrip back for this window, then brings them in as stage two.
    var isEntering = false
    /// The asset whose Library cell the return flight should land on. Only that cell reports its
    /// frame, so the grid pays nothing while it scrolls.
    var returnTargetID: PhotoAssetID?

    /// Frames below are bookkeeping read at gesture time; views never observe them.
    @ObservationIgnored private(set) var canvasFrame: CGRect = .zero
    @ObservationIgnored private(set) var canvasFrameRevision = 0
    @ObservationIgnored var pendingOpenFrame: CGRect?
    @ObservationIgnored private(set) var returnCellFrame: CGRect?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Every report bumps the revision, even an unchanged frame, so an entrance can tell the
    /// freshly mounted canvas from the one the last editing session left behind.
    func updateCanvasFrame(_ frame: CGRect) {
        canvasFrame = frame
        canvasFrameRevision &+= 1
    }

    func updateReturnCellFrame(_ frame: CGRect, for id: PhotoAssetID) {
        guard id == returnTargetID else { return }
        returnCellFrame = frame
    }

    func beginReturnTarget(_ id: PhotoAssetID) {
        returnCellFrame = nil
        returnTargetID = id
    }

    /// Grows `image` from its Library cell to the Edit canvas, then lets the inspector and
    /// filmstrip follow. The caller has already started the (asynchronous) open.
    func runEntrance(image: NSImage, from cell: CGRect) {
        task?.cancel()
        flight = Flight(image: image, frame: cell, cornerRadius: 6, opacity: 1)
        isEntering = true
        let revision = canvasFrameRevision
        task = Task { @MainActor [self] in
            for _ in 0..<25 where canvasFrameRevision == revision {
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            if canvasFrame.width > 0 {
                let target = Self.fittedRect(imageSize: image.size, in: canvasFrame)
                await animate(.smooth(duration: 0.4)) {
                    self.flight?.frame = target
                    self.flight?.cornerRadius = 0
                }
            }
            guard !Task.isCancelled else { return }
            // Stage two: the photo is on the canvas, so the chrome slides in as it dissolves.
            await animate(.smooth(duration: 0.35)) {
                self.flight?.opacity = 0
                self.isEntering = false
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// Contracts `image` from the canvas toward the Library cell for `assetID` once the grid has
    /// laid it out. Without a usable cell the photo dissolves in place: no jump, no scrolling.
    func runReturn(image: NSImage, assetID: PhotoAssetID) {
        task?.cancel()
        isEntering = false
        guard canvasFrame.width > 0 else { finish(); return }
        flight = Flight(
            image: image, frame: Self.fittedRect(imageSize: image.size, in: canvasFrame),
            cornerRadius: 0, opacity: 1)
        beginReturnTarget(assetID)
        task = Task { @MainActor [self] in
            for _ in 0..<20 where returnCellFrame == nil {
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            if let cell = returnCellFrame {
                await animate(.smooth(duration: 0.4)) {
                    self.flight?.frame = cell
                    self.flight?.cornerRadius = 6
                }
                guard !Task.isCancelled else { return }
                await animate(.easeOut(duration: 0.12)) { self.flight?.opacity = 0 }
            } else {
                await animate(.easeOut(duration: 0.25)) { self.flight?.opacity = 0 }
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func animate(_ animation: Animation, _ changes: @escaping @MainActor () -> Void) async {
        await withCheckedContinuation { continuation in
            withAnimation(animation, completionCriteria: .logicallyComplete) {
                changes()
            } completion: {
                continuation.resume()
            }
        }
    }

    func finish() {
        task?.cancel()
        task = nil
        flight = nil
        returnTargetID = nil
        returnCellFrame = nil
        pendingOpenFrame = nil
        isEntering = false
    }

    /// The rectangle `image` occupies when aspect-fit inside `bounds`.
    static func fittedRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height)
    }
}
