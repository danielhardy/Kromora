/// The precompiled Core Image kernels a document needs in order to reproduce its saved edits.
///
/// A neutral document needs none, so a damaged kernel bundle never affects an unedited photo. Every
/// kernel listed here produces document pixels (a local mask, a tone curve, the colour mixer,
/// grading, retouching, vignette, grain, clarity's midtone mask), so an unavailable one fails the
/// render or export rather than leaving that edit out. The conditions mirror the gates in
/// `RenderPipeline` and `RetouchRenderer`; `RenderKernelRequirementsTests` keeps them in step.
enum RenderKernelRequirements {
    static func names(for document: EditDocument) -> Set<String> {
        var names = Set<String>()
        let light = document.light
        if !light.toneCurve.isIdentity || !light.redToneCurve.isIdentity
            || !light.greenToneCurve.isIdentity || !light.blueToneCurve.isIdentity
            || !light.parametricCurve.isIdentity {
            names.insert("applyToneCurve")
        }
        if !document.color.mixer.isIdentity { names.insert("hslMixer") }
        if !document.color.grading.isIdentity { names.insert("colorGrading") }
        if document.effects.clarity != 0 { names.insert("effectsMidtoneMask") }
        if !document.effects.vignette.isIdentity { names.insert("effectsVignette") }
        if !document.effects.grain.isIdentity { names.insert("effectsGrain") }

        for spot in document.retouch.spots where !spot.isIdentity {
            names.insert("retouchMembraneApply")
            if spot.mode == .heal {
                names.formUnion(["retouchPull", "retouchPush", "retouchApplyCorrection"])
            }
        }

        for layer in document.localAdjustments where layer.hasVisibleLook {
            if layer.adjustments.clarity != 0 { names.insert("effectsMidtoneMask") }
            names.insert("localCombineMask")
            if layer.isInverted { names.insert("localInvertMask") }
            for component in layer.components where component.isUsable {
                if component.isInverted { names.insert("localInvertMask") }
                switch component.source {
                case .linear, .radial: names.insert("localAnalyticMask")
                default: break
                }
            }
        }
        return names
    }
}
