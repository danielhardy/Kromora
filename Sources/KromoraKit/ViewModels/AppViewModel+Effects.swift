import SwiftUI

/// Bindings for the photographer-facing Effects inspector.
extension AppViewModel {
    func detailBinding(for control: DetailControl) -> Binding<Double> {
        Binding(
            get: { control.value(in: self.document.effects.detail) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    control.setting(value, in: &document.effects.detail)
                }
            }
        )
    }

    func resetDetail(_ control: DetailControl) {
        endUndoGrouping()
        updateDocument { control.setting(control.neutral, in: &$0.effects.detail) }
    }

    func resetAllDetail() {
        endUndoGrouping()
        updateDocument { $0.effects.detail = .neutral }
    }

    func resetAllSharpening() {
        endUndoGrouping()
        updateDocument { document in
            for control in [DetailControl.sharpeningRadius, .sharpeningAmount, .sharpeningDetail, .sharpeningMasking] {
                control.setting(control.neutral, in: &document.effects.detail)
            }
        }
    }

    func resetAllNoiseReduction() {
        endUndoGrouping()
        updateDocument { document in
            for control in [DetailControl.luminanceNoise, .luminanceDetail, .luminanceContrast, .colorNoise, .colorDetail, .colorContrast] {
                control.setting(control.neutral, in: &document.effects.detail)
            }
        }
    }

    func resetAllTextureClarityDehaze() {
        endUndoGrouping()
        updateDocument { document in
            for control in EffectsControl.allCases {
                document.effects = control.setting(control.neutral, in: document.effects)
            }
        }
    }

    func effectsValue(for control: EffectsControl) -> Double {
        control.value(in: document.effects)
    }

    func effectsBinding(for control: EffectsControl) -> Binding<Double> {
        Binding(
            get: { self.effectsValue(for: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    document.effects = control.setting(value, in: document.effects)
                }
            }
        )
    }

    func resetEffects(_ control: EffectsControl) {
        endUndoGrouping()
        updateDocument { document in
            document.effects = control.setting(control.neutral, in: document.effects)
        }
    }

    func vignetteValue(for control: VignetteControl) -> Double {
        control.value(in: document.effects.vignette)
    }

    func vignetteBinding(for control: VignetteControl) -> Binding<Double> {
        Binding(
            get: { self.vignetteValue(for: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    document.effects.vignette = control.setting(value, in: document.effects.vignette)
                }
            }
        )
    }

    func resetVignette(_ control: VignetteControl) {
        endUndoGrouping()
        updateDocument { document in
            document.effects.vignette = control.setting(control.neutral, in: document.effects.vignette)
        }
    }

    func resetAllVignette() {
        endUndoGrouping()
        updateDocument { $0.effects.vignette = .neutral }
    }

    func grainValue(for control: GrainControl) -> Double {
        control.value(in: document.effects.grain)
    }

    func grainBinding(for control: GrainControl) -> Binding<Double> {
        Binding(
            get: { self.grainValue(for: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    document.effects.grain = control.setting(value, in: document.effects.grain)
                }
            }
        )
    }

    func resetGrain(_ control: GrainControl) {
        endUndoGrouping()
        updateDocument { document in
            document.effects.grain = control.setting(control.neutral, in: document.effects.grain)
        }
    }

    func resetAllGrain() {
        endUndoGrouping()
        updateDocument { $0.effects.grain = .neutral }
    }

    func resetAllEffects() {
        endUndoGrouping()
        updateDocument { $0.effects = .neutral }
    }

    /// Includes retained subordinate values even while Vignette/Grain Amount is zero. Those values
    /// are intentionally persisted so turning a group back on restores its previous shape.
    var hasTextureClarityDehazeAdjustments: Bool {
        EffectsControl.allCases.contains { $0.value(in: document.effects) != $0.neutral }
    }

    var hasSharpeningAdjustments: Bool {
        [DetailControl.sharpeningRadius, .sharpeningAmount, .sharpeningDetail, .sharpeningMasking]
            .contains { $0.value(in: document.effects.detail) != $0.neutral }
    }

    var hasNoiseAdjustments: Bool {
        [DetailControl.luminanceNoise, .luminanceDetail, .luminanceContrast, .colorNoise, .colorDetail, .colorContrast]
            .contains { $0.value(in: document.effects.detail) != $0.neutral }
    }

    var hasDetailEffects: Bool {
        hasTextureClarityDehazeAdjustments || hasSharpeningAdjustments || hasNoiseAdjustments
    }

    var hasVignetteAdjustments: Bool { document.effects.vignette != .neutral }
    var hasGrainAdjustments: Bool { document.effects.grain != .neutral }
    var hasEffects: Bool { hasDetailEffects || hasVignetteAdjustments || hasGrainAdjustments }
}
