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
    /// holds its inspector and filmstrip contents back for this window, then brings them in as
    /// stage two. Their space stays reserved, so the canvas has its final frame throughout.
    var isEntering = false
    /// The filmstrip and culling bar stay hidden, their height reserved, until the photo has landed.
    var isChromeHeld = false
    /// Dark canvas tone laid over the Library while the photo is in the air. Fades in on entry and
    /// out on return, and hides any inspector-driven grid reflow behind it.
    var libraryScrim = 0.0
    /// The inspector was open when Edit was left. It stays open until the swap, so the canvas the
    /// photo contracts from keeps the size the user was looking at.
    var inspectorHeldOpen = false
    /// The editor's canvas stays invisible from the start of an entrance until the photo lands, so
    /// the flight is the only copy of the image on screen instead of growing over an identical one.
    var isCanvasHeld = false
    /// The whole editor layer is invisible while the photo flies; it appears at stage two so the
    /// inspector and filmstrip can be seen arriving, with the canvas itself still held.
    var isEditorHeld = false
    /// The editor stays mounted over the Library after navigation leaves Edit, so its chrome can
    /// slide away before the photo flies back. Set synchronously with the navigation change.
    var isLeaving = false
    /// The editor's filmstrip and culling bar are retracting ahead of the return flight.
    var isRetractingChrome = false
    /// The asset whose Library cell the return flight should land on. Only that cell reports its
    /// frame, so the grid pays nothing while it scrolls.
    var returnTargetID: PhotoAssetID?

    /// Frames below are bookkeeping read at gesture time; views never observe them.
    @ObservationIgnored private(set) var canvasFrame: CGRect = .zero
    @ObservationIgnored private(set) var canvasFrameRevision = 0
    @ObservationIgnored var pendingOpenFrame: CGRect?
    /// The inspector column's last measured width, used to predict the canvas's final frame.
    @ObservationIgnored var inspectorWidth: CGFloat = 280
    @ObservationIgnored private(set) var returnCellFrame: CGRect?

    @ObservationIgnored private var isTrackingCanvas = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Every report bumps the revision, even an unchanged frame, so an entrance can tell the
    /// freshly mounted canvas from the one the last editing session left behind.
    func updateCanvasFrame(_ frame: CGRect) {
        canvasFrame = frame
        canvasFrameRevision &+= 1
        // The chrome's space is reserved from the start, so the canvas normally holds still; if it
        // does move while the flight dissolves, the flight follows so the two copies stay registered.
        guard isTrackingCanvas, let flight, frame.width > 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.flight?.frame = Self.canvasFittedRect(imageSize: flight.image.size, in: frame)
        }
    }

    func updateReturnCellFrame(_ frame: CGRect, for id: PhotoAssetID) {
        guard id == returnTargetID, frame != returnCellFrame else { return }
        returnCellFrame = frame
    }

    func beginReturnTarget(_ id: PhotoAssetID) {
        returnCellFrame = nil
        returnTargetID = id
    }

    func prepareForReturn(isEditing: Bool, inspectorIsPresented: Bool) {
        guard isEditing else { return }
        inspectorHeldOpen = inspectorIsPresented
        isLeaving = true
    }

    /// Grows `image` from its Library cell to where it will sit in the finished editor while the
    /// Library fades to the canvas tone, then brings the inspector and filmstrip in around it. The
    /// photo never moves again after it lands: the canvas takes over at the same frame. The
    /// caller has already started the (asynchronous) open.
    func runEntrance(image: NSImage, from cell: CGRect, inspectorWidth: CGFloat) {
        task?.cancel()
        flight = Flight(image: image, frame: cell, cornerRadius: 6, opacity: 1)
        isEntering = true
        isChromeHeld = true
        isCanvasHeld = true
        isEditorHeld = true
        isTrackingCanvas = false
        let revision = canvasFrameRevision
        task = Task { @MainActor [self] in
            for _ in 0..<25 where canvasFrameRevision == revision {
                try? await Task.sleep(for: .milliseconds(20))
            }
            await settleCanvasFrame(polls: 1)
            guard !Task.isCancelled else { return }
            if canvasFrame.width > 0 {
                // The canvas is still full width (the inspector is held back) and already has its
                // final height (the filmstrip's space is reserved); take the inspector's share off.
                let final = Self.finalCanvasFrame(held: canvasFrame, inspectorWidth: inspectorWidth)
                let target = Self.canvasFittedRect(imageSize: image.size, in: final)
                await animate(.smooth(duration: 0.28)) {
                    self.flight?.frame = target
                    self.flight?.cornerRadius = 0
                    self.libraryScrim = 1
                }
            }
            guard !Task.isCancelled else { return }
            // Stage two, still under the scrim: the inspector and filmstrip arrive together while
            // the photo holds its frame. The canvas then takes over at that same frame.
            isEditorHeld = false
            await animate(.smooth(duration: 0.22)) {
                self.isEntering = false
                self.isChromeHeld = false
            }
            await settleCanvasFrame(polls: 2)
            guard !Task.isCancelled else { return }
            isTrackingCanvas = true
            if canvasFrame.width > 0 {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.flight?.frame = Self.canvasFittedRect(
                        imageSize: image.size, in: self.canvasFrame)
                }
            }
            await animate(.easeOut(duration: 0.12)) {
                self.flight?.opacity = 0
                self.isCanvasHeld = false
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// Waits, bounded, until the canvas frame has held still for `polls` consecutive checks.
    private func settleCanvasFrame(polls: Int) async {
        var previous = canvasFrame
        var stable = 0
        for _ in 0..<30 where stable < polls {
            try? await Task.sleep(for: .milliseconds(20))
            if canvasFrame == previous { stable += 1 } else { stable = 0; previous = canvasFrame }
        }
    }

    /// Contracts `image` from the canvas toward the Library cell for `assetID` once the grid has
    /// laid it out, as the Library fades back up from the canvas tone. Without a usable cell the
    /// photo dissolves in place: no jump, no scrolling.
    func runReturn(image: NSImage, assetID: PhotoAssetID) {
        task?.cancel()
        isEntering = false
        isChromeHeld = false
        // Read before anything below can change it: the canvas as the user last saw it.
        let startFrame = canvasFrame
        guard startFrame.width > 0 else {
            finish()
            return
        }
        beginReturnTarget(assetID)
        task = Task { @MainActor [self] in
            // Stage one: the chrome slides away. Its space and the inspector stay, so the photo
            // does not change size before it starts moving.
            if isLeaving {
                await animate(.easeInOut(duration: 0.17)) { self.isRetractingChrome = true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            // Stage two: swap the editor for a flight over a dark Library, with no transition. The
            // inspector closes now and the grid re-lays out under the scrim, out of sight.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.flight = Flight(
                    image: image, frame: Self.canvasFittedRect(imageSize: image.size, in: startFrame),
                    cornerRadius: 0, opacity: 1)
                self.libraryScrim = 1
                self.isCanvasHeld = true
                self.isLeaving = false
                self.isRetractingChrome = false
                self.inspectorHeldOpen = false
            }
            // Wait for the grid to settle at its final width, then for its cell; a cell the grid
            // has not laid out dissolves in place without scrolling.
            for _ in 0..<12 where returnCellFrame == nil {
                try? await Task.sleep(for: .milliseconds(20))
            }
            var lastCell = returnCellFrame
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(25))
                if returnCellFrame == lastCell { break }
                lastCell = returnCellFrame
            }
            guard !Task.isCancelled else { return }
            if let cell = returnCellFrame {
                await animate(.smooth(duration: 0.27)) {
                    self.flight?.frame = cell
                    self.flight?.cornerRadius = 6
                    self.libraryScrim = 0
                }
                guard !Task.isCancelled else { return }
                await animate(.easeOut(duration: 0.12)) { self.flight?.opacity = 0 }
            } else {
                await animate(.easeOut(duration: 0.3)) {
                    self.flight?.opacity = 0
                    self.libraryScrim = 0
                }
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
        isChromeHeld = false
        libraryScrim = 0
        inspectorHeldOpen = false
        isCanvasHeld = false
        isEditorHeld = false
        isLeaving = false
        isRetractingChrome = false
        isTrackingCanvas = false
    }

    /// Reduce Motion, a missing thumbnail, or an unknown cell frame opens immediately.
    static func entranceFlies(reduceMotion: Bool, hasCell: Bool, hasImage: Bool) -> Bool {
        !reduceMotion && hasCell && hasImage
    }

    /// Reduce Motion or a missing thumbnail leaves Edit immediately, with no chrome retraction.
    static func returnFlies(reduceMotion: Bool, hasImage: Bool) -> Bool {
        !reduceMotion && hasImage
    }

    /// The padding `PreviewView` draws around the single-image canvas. The handoff photo must sit
    /// where the canvas will draw it, so both read this one value.
    static let canvasContentInset: CGFloat = 8

    /// Where the canvas draws `imageSize` inside the frame reported for the preview view.
    static func canvasFittedRect(imageSize: CGSize, in canvas: CGRect) -> CGRect {
        fittedRect(
            imageSize: imageSize,
            in: canvas.insetBy(dx: canvasContentInset, dy: canvasContentInset))
    }

    /// The canvas frame once the inspector arrives. The held canvas already has its final height
    /// (the filmstrip's space is reserved); the inspector takes its width from the trailing edge.
    static func finalCanvasFrame(held: CGRect, inspectorWidth: CGFloat) -> CGRect {
        var frame = held
        frame.size.width = max(1, held.width - max(0, inspectorWidth))
        return frame
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
