/// Shared evidence gate for rewarding or proposing a muted-color lift.
///
/// Keep the candidate scorer and policy proposal aligned on which frames can benefit from a
/// vibrance boost. The coordinator may apply additional scoring-only guardrails after this gate.
enum AutoMutedColorEligibility {
    static func allowsVibranceLift(facts: AutoEnhancementFacts) -> Bool {
        let color = facts.color
        let scene = facts.scene
        let confidence = facts.signalConfidence

        return !color.isMixed
            && scene.monochromeLikelihood <= 0.5
            && scene.sunsetWarmLikelihood <= 0.6
            && (scene.nightLikelihood <= 0.6 || facts.hasDarkChromaticEvidence)
            && confidence.colorNeutral >= 0.6
            && color.colorfulness < 0.35
            && Double(color.saturationP95 - color.saturationMedian) < 0.5
    }
}
