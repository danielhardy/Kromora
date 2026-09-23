import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Thin forwarding surface for the masking workspace. `MaskingWorkflowCoordinator` owns selection,
/// transient creation, and smart-mask analysis lifecycle (`Sources/KromoraKit/ViewModels/
/// MaskingWorkflowCoordinator.swift`); AppViewModel keeps these entry points so existing call sites
/// in Views and KeyboardShortcuts do not need to know about the coordinator.
extension AppViewModel {
    func useInfoAnalysisMask(
        _ kind: SemanticMaskKind,
        demonstrated result: RegionMask,
        pixels: NormalizedMask
    ) {
        maskingWorkflow.useInfoAnalysisMask(kind, demonstrated: result, pixels: pixels)
    }

    func semanticMaskFailureMessage(for document: EditDocument) -> String? {
        maskingWorkflow.semanticMaskFailureMessage(for: document)
    }

    /// One narrow observation boundary owns selection, transient creation, and presentation state
    /// for the masking workspace. The document itself remains owned by AppViewModel.
    var maskingState: MaskInteractionState { maskingWorkflow.interactionState }

    func renderMaskOverlay(
        layers: [LocalAdjustmentLayer],
        selectedLayerID: UUID?,
        soloLayerID: UUID?,
        targetSize: PixelDimensions,
        style: MaskOverlayStyle,
        transform: LocalMaskRenderTransform = .identity,
        selectedComponentID: UUID? = nil,
        soloComponentID: UUID? = nil
    ) async -> sending CGImage? {
        await maskingWorkflow.renderMaskOverlay(
            layers: layers, selectedLayerID: selectedLayerID, soloLayerID: soloLayerID,
            targetSize: targetSize, style: style, transform: transform,
            selectedComponentID: selectedComponentID, soloComponentID: soloComponentID
        )
    }

    func openMaskingWorkspace() { maskingWorkflow.openMaskingWorkspace() }

    func selectMaskLayer(_ id: UUID?) { maskingWorkflow.selectMaskLayer(id) }

    func selectMaskComponent(_ componentID: UUID, in layerID: UUID) {
        maskingWorkflow.selectMaskComponent(componentID, in: layerID)
    }

    func createMask(_ kind: MaskCreationKind) { maskingWorkflow.createMask(kind) }

    func createSmartMask(_ kind: MaskCreationKind) { maskingWorkflow.createSmartMask(kind) }

    func retryMaskAnalysis() { maskingWorkflow.retryMaskAnalysis() }

    var selectedSemanticTarget: SemanticTarget? { maskingWorkflow.selectedSemanticTarget }

    func warmPersonSignals() async { await maskingWorkflow.warmPersonSignals() }

    func duplicateMask(_ id: UUID) { maskingWorkflow.duplicateMask(id) }

    func renameMask(_ id: UUID, name: String) { maskingWorkflow.renameMask(id, name: name) }

    func deleteMask(_ id: UUID) { maskingWorkflow.deleteMask(id) }

    func moveMask(_ id: UUID, by offset: Int) { maskingWorkflow.moveMask(id, by: offset) }

    func updateMask(
        _ id: UUID, debounced: Bool = false, _ transform: (inout LocalAdjustmentLayer) -> Void
    ) {
        maskingWorkflow.updateMask(id, debounced: debounced, transform)
    }

    func localAdjustmentValue(
        _ control: LocalAdjustmentControl, in layerID: UUID
    ) -> Double {
        maskingWorkflow.localAdjustmentValue(control, in: layerID)
    }

    func localAdjustmentBinding(
        _ control: LocalAdjustmentControl, in layerID: UUID
    ) -> Binding<Double> {
        maskingWorkflow.localAdjustmentBinding(control, in: layerID)
    }

    func resetMaskAdjustment(_ control: LocalAdjustmentControl, in layerID: UUID) {
        maskingWorkflow.resetMaskAdjustment(control, in: layerID)
    }

    func addMaskComponent(to layerID: UUID, source: MaskSource, mode: MaskCombineMode = .add) {
        maskingWorkflow.addMaskComponent(to: layerID, source: source, mode: mode)
    }

    func addMaskComponent(to layerID: UUID, kind: MaskCreationKind, mode: MaskCombineMode) {
        maskingWorkflow.addMaskComponent(to: layerID, kind: kind, mode: mode)
    }

    func addSmartMaskComponent(to layerID: UUID, kind: MaskCreationKind, mode: MaskCombineMode) {
        maskingWorkflow.addSmartMaskComponent(to: layerID, kind: kind, mode: mode)
    }

    func renameMaskComponent(_ componentID: UUID, in layerID: UUID, name: String) {
        maskingWorkflow.renameMaskComponent(componentID, in: layerID, name: name)
    }

    func moveMaskComponent(_ componentID: UUID, in layerID: UUID, by offset: Int) {
        maskingWorkflow.moveMaskComponent(componentID, in: layerID, by: offset)
    }

    func setMaskComponentMode(_ componentID: UUID, in layerID: UUID, mode: MaskCombineMode) {
        maskingWorkflow.setMaskComponentMode(componentID, in: layerID, mode: mode)
    }

    func deleteMaskComponent(_ componentID: UUID, from layerID: UUID) {
        maskingWorkflow.deleteMaskComponent(componentID, from: layerID)
    }

    func resetMask(_ id: UUID) { maskingWorkflow.resetMask(id) }

    func resetMaskComponent(_ componentID: UUID, in layerID: UUID) {
        maskingWorkflow.resetMaskComponent(componentID, in: layerID)
    }

    func resetSelectedMask() { maskingWorkflow.resetSelectedMask() }

    func updateMaskComponent(
        _ componentID: UUID, in layerID: UUID, _ transform: (inout MaskComponent) -> Void
    ) {
        maskingWorkflow.updateMaskComponent(componentID, in: layerID, transform)
    }

    @discardableResult
    func nudgeSelectedMask(dx: Double, dy: Double, accelerated: Bool = false) -> Bool {
        maskingWorkflow.nudgeSelectedMask(dx: dx, dy: dy, accelerated: accelerated)
    }

    func setMaskTool(_ tool: MaskInteractionState.Tool) { maskingWorkflow.setMaskTool(tool) }

    func beginMaskGesture(
        at point: CGPoint,
        linearHandle: MaskInteractionState.LinearHandle? = nil,
        radialHandle: MaskInteractionState.RadialHandle? = nil,
        sourceSize: CGSize = CGSize(width: 1, height: 1),
        pressure: Double? = nil,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        maskingWorkflow.beginMaskGesture(
            at: point, linearHandle: linearHandle, radialHandle: radialHandle,
            sourceSize: sourceSize, pressure: pressure, modifiers: modifiers
        )
    }

    func updateMaskGesture(
        to point: CGPoint, pressure: Double? = nil,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags,
        sourceDelta: CGPoint? = nil
    ) {
        maskingWorkflow.updateMaskGesture(
            to: point, pressure: pressure, modifiers: modifiers, sourceDelta: sourceDelta
        )
    }

    func endMaskGesture() { maskingWorkflow.endMaskGesture() }

    func cancelMaskGesture() { maskingWorkflow.cancelMaskGesture() }

    func restoreMaskSelection() { maskingWorkflow.restoreMaskSelection() }

    func closeMaskingWorkspace() { maskingWorkflow.closeMaskingWorkspace() }
}
