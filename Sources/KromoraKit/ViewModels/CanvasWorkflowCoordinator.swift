import AppKit
import CoreGraphics
import Foundation

struct CropWorkflowPresentation {
    let isInspectorPresented: Bool
    let inspectorTab: String
    let isSourceBrowserPresented: Bool
}

enum CanvasNavigationChange {
    case zoom(from: CanvasNavigation)
    case pan(from: CanvasNavigation)
}

/// The editor-side effects required by crop and canvas commands. The coordinator never owns an
/// edit document: durable mutations are sent through the destination's ordinary history path.
@MainActor
protocol CanvasWorkflowDestination: AnyObject {
    var canvasWorkflowHasSource: Bool { get }
    var canvasWorkflowDocument: EditDocument { get }
    var canvasWorkflowSourceSize: CGSize { get }
    var canvasWorkflowImageExtent: CGRect? { get }
    var canvasWorkflowHasCropAdjustments: Bool { get }

    func updateCanvasWorkflowDocument(_ transform: (inout EditDocument) -> Void)
    func endCanvasWorkflowUndoGrouping()
    func setCanvasWorkflowStatus(_ message: String)
    func captureCropWorkflowPresentation() -> CropWorkflowPresentation
    func prepareCropWorkflowPresentation()
    func restoreCropWorkflowPresentation(_ presentation: CropWorkflowPresentation)
    func scheduleCanvasWorkflowPreview()
    func scheduleCanvasWorkflowCropEntryPreview()
    func scheduleCanvasWorkflowInteractivePreview()
    func canvasNavigationDidChange(_ change: CanvasNavigationChange)
    func setCanvasWorkflowOriginalVisible(_ visible: Bool)
}

/// Owns crop, rotation, and viewport commands while `AppViewModel` retains the durable document,
/// history, rendering, and persistence. Crop drafts stay in `CanvasInteractionState` so the canvas
/// can observe pointer-frequency changes without invalidating the application model.
@MainActor
final class CanvasWorkflowCoordinator {
    let interactionState: CanvasInteractionState
    weak var destination: (any CanvasWorkflowDestination)?
    private var cropPresentation: CropWorkflowPresentation?

    init(
        interactionState: CanvasInteractionState = CanvasInteractionState(),
        destination: (any CanvasWorkflowDestination)? = nil
    ) {
        self.interactionState = interactionState
        self.destination = destination
    }

    var cropSourceSize: CGSize {
        interactionState.cropImageSize(from: destination?.canvasWorkflowSourceSize ?? .zero)
    }

    func resetForSource() {
        cropPresentation = nil
        interactionState.resetForSource()
    }

    func discardCropForSourceChange() {
        guard interactionState.isCropToolActive else { return }
        interactionState.finishCrop()
        restoreCropPresentation()
    }

    func reseedCrop(using crop: CropAdjustments, sourceSize: CGSize) {
        interactionState.reseedCrop(using: crop, sourceSize: sourceSize)
    }

    func beginCrop() {
        guard let destination else { return }
        guard destination.canvasWorkflowHasSource else {
            destination.setCanvasWorkflowStatus("Open an image first")
            return
        }
        guard !interactionState.isCropToolActive else { return }
        destination.endCanvasWorkflowUndoGrouping()
        cropPresentation = destination.captureCropWorkflowPresentation()
        destination.prepareCropWorkflowPresentation()
        destination.setCanvasWorkflowOriginalVisible(false)
        interactionState.beginCrop(
            using: destination.canvasWorkflowDocument.crop,
            sourceSize: destination.canvasWorkflowSourceSize
        )
        destination.setCanvasWorkflowStatus("Adjust crop, then Save")
        destination.scheduleCanvasWorkflowCropEntryPreview()
    }

    func toggleCropTool() {
        if interactionState.isCropToolActive { cancelCrop() } else { beginCrop() }
    }

    func updateCropDraft(_ rect: CGRect) {
        interactionState.updateCropDraft(rect, sourceSize: destination?.canvasWorkflowSourceSize ?? .zero)
    }

    func selectCropAspectRatio(
        _ ratio: CropAspectRatio, orientation: CropAspectRatioOrientation = .automatic
    ) {
        guard let destination, destination.canvasWorkflowSourceSize != .zero else { return }
        interactionState.selectCropAspectRatio(
            ratio, orientation: orientation, imageSize: cropSourceSize,
            sourceSize: destination.canvasWorkflowSourceSize
        )
    }

    func setCropStraightenAngle(_ angle: Double) {
        interactionState.setCropStraightenAngle(
            angle, sourceSize: destination?.canvasWorkflowSourceSize ?? .zero
        )
        destination?.scheduleCanvasWorkflowInteractivePreview()
    }

    func setCropVerticalPerspective(_ value: Double) {
        interactionState.setCropVerticalPerspective(value)
        destination?.scheduleCanvasWorkflowInteractivePreview()
    }

    func setCropHorizontalPerspective(_ value: Double) {
        interactionState.setCropHorizontalPerspective(value)
        destination?.scheduleCanvasWorkflowInteractivePreview()
    }

    func runCropAuto() {
        guard interactionState.isCropToolActive else { return }
        destination?.setCanvasWorkflowStatus("Auto crop: no reliable horizon detected")
    }

    func toggleCropFlip(horizontal: Bool) {
        interactionState.toggleCropFlip(horizontal: horizontal)
        destination?.scheduleCanvasWorkflowPreview()
    }

    func commitCrop() {
        guard let destination, interactionState.isCropToolActive else { return }
        let committed = interactionState.cropDraft ?? CropAdjustments.unitRect
        let aspectRatio = interactionState.cropAspectRatio
        let orientation = interactionState.cropOrientation
        let cropRotation = interactionState.cropRotation
        let straightenAngle = interactionState.cropStraightenAngle
        let flipHorizontal = interactionState.cropFlipHorizontal
        let flipVertical = interactionState.cropFlipVertical
        let verticalPerspective = interactionState.cropVerticalPerspective
        let horizontalPerspective = interactionState.cropHorizontalPerspective
        interactionState.finishCrop()
        restoreCropPresentation()
        let previousDocument = destination.canvasWorkflowDocument
        destination.updateCanvasWorkflowDocument {
            $0.rotation = $0.rotation.addingClockwiseQuarterTurns(cropRotation.rawValue / 90)
            $0.crop = CropAdjustments(
                normalizedRect: committed, aspectRatio: aspectRatio, orientation: orientation,
                straightenAngle: straightenAngle, flipHorizontal: flipHorizontal,
                flipVertical: flipVertical, verticalPerspective: verticalPerspective,
                horizontalPerspective: horizontalPerspective
            )
        }
        interactionState.fit()
        if destination.canvasWorkflowDocument == previousDocument {
            destination.scheduleCanvasWorkflowPreview()
        }
        destination.setCanvasWorkflowStatus("Crop applied")
    }

    func cancelCrop() {
        guard let destination, interactionState.isCropToolActive else { return }
        interactionState.finishCrop()
        restoreCropPresentation()
        interactionState.fit()
        destination.scheduleCanvasWorkflowPreview()
        destination.setCanvasWorkflowStatus(
            destination.canvasWorkflowHasCropAdjustments ? "Crop unchanged" : "Crop cancelled"
        )
    }

    private func restoreCropPresentation() {
        guard let presentation = cropPresentation else { return }
        cropPresentation = nil
        destination?.restoreCropWorkflowPresentation(presentation)
    }

    func resetCrop() {
        guard let destination else { return }
        if interactionState.isCropToolActive {
            interactionState.resetCropDraft()
            destination.setCanvasWorkflowStatus("Crop reset")
        } else {
            destination.endCanvasWorkflowUndoGrouping()
            destination.updateCanvasWorkflowDocument { $0.crop = .neutral }
            interactionState.fit()
        }
    }

    func rotateClockwise() { rotateImage(clockwise: true) }
    func rotateCounterClockwise() { rotateImage(clockwise: false) }

    func resetRotation() {
        guard let destination else { return }
        guard destination.canvasWorkflowHasSource else {
            destination.setCanvasWorkflowStatus("Open an image first")
            return
        }
        destination.endCanvasWorkflowUndoGrouping()
        destination.updateCanvasWorkflowDocument { document in
            let turns = document.rotation.rawValue / 90
            document.crop = document.crop.rotated(byClockwiseQuarterTurns: -turns)
            document.rotation = .zero
        }
        interactionState.fit()
        destination.setCanvasWorkflowStatus("Rotation reset")
    }

    private func rotateImage(clockwise: Bool) {
        guard let destination else { return }
        guard destination.canvasWorkflowHasSource else {
            destination.setCanvasWorkflowStatus("Open an image first")
            return
        }
        if interactionState.isCropToolActive {
            guard interactionState.rotateCrop(clockwise: clockwise) else { return }
            destination.scheduleCanvasWorkflowPreview()
            destination.setCanvasWorkflowStatus("Rotated \(clockwise ? "clockwise" : "counterclockwise")")
            return
        }
        destination.endCanvasWorkflowUndoGrouping()
        destination.updateCanvasWorkflowDocument { document in
            let turns = clockwise ? 1 : -1
            document.rotation = document.rotation.addingClockwiseQuarterTurns(turns)
            document.crop = document.crop.rotated(byClockwiseQuarterTurns: turns)
        }
        interactionState.fit()
        destination.setCanvasWorkflowStatus("Rotated \(clockwise ? "clockwise" : "counterclockwise")")
    }

    func fitCanvas() { applyNavigation { interactionState.fit() } }
    func fillCanvas() { applyNavigation { interactionState.fill() } }
    func resetCanvas() { applyNavigation { interactionState.reset() } }
    func toggleCanvasZoom() { applyNavigation { interactionState.toggleFitAndRememberedZoom() } }

    func toggleCanvasZoom(at point: CGPoint, viewportSize: CGSize) {
        guard let imageExtent = destination?.canvasWorkflowImageExtent else {
            toggleCanvasZoom()
            return
        }
        applyNavigation {
            interactionState.toggleFitAndRememberedZoom(
                at: point, imageExtent: imageExtent, viewportSize: viewportSize
            )
        }
    }

    private func applyNavigation(_ change: () -> Void) {
        change()
        destination?.scheduleCanvasWorkflowPreview()
    }

    func setCanvasZoom(_ value: CGFloat) {
        let old = interactionState.navigation
        interactionState.setZoom(value)
        guard interactionState.navigation != old else { return }
        destination?.canvasNavigationDidChange(.zoom(from: old))
    }

    func zoomCanvas(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        setCanvasZoom(interactionState.navigation.zoom * factor)
    }

    func zoomCanvas(by factor: CGFloat, at point: CGPoint, viewportSize: CGSize) {
        guard factor.isFinite, factor > 0,
              let imageExtent = destination?.canvasWorkflowImageExtent else { return }
        let old = interactionState.navigation
        interactionState.zoom(by: factor, at: point, imageExtent: imageExtent, viewportSize: viewportSize)
        guard interactionState.navigation != old else { return }
        destination?.canvasNavigationDidChange(.zoom(from: old))
    }

    func panCanvas(by delta: CGSize, viewportSize: CGSize) {
        guard let destination, let imageExtent = destination.canvasWorkflowImageExtent else { return }
        let old = interactionState.navigation
        interactionState.pan(by: delta, imageExtent: imageExtent, viewportSize: viewportSize)
        guard interactionState.navigation != old else { return }
        destination.canvasNavigationDidChange(.pan(from: old))
    }

    func shutdown() {
        if interactionState.isCropToolActive { interactionState.finishCrop() }
        restoreCropPresentation()
    }
}
