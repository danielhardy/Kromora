import Foundation

/// Pure comparison-frame rules shared by the editor orchestration and its tests.
///
/// A comparison baseline represents the developed/cropped source frame, not every edit. Look,
/// local-mask, and RAW white-balance Temperature/Tint edits are evaluated against the existing
/// baseline; other baseline-document changes establish a new one.
enum ComparisonFramePolicy {
    static func rawDevelopChangesFrame(
        from old: RAWDevelopSettings,
        to new: RAWDevelopSettings
    ) -> Bool {
        var oldFrame = old
        var newFrame = new
        oldFrame.neutralTemperature = nil
        newFrame.neutralTemperature = nil
        oldFrame.neutralTint = nil
        newFrame.neutralTint = nil
        return oldFrame != newFrame
    }

    static func changesBaseline(
        from old: EditDocument,
        to new: EditDocument,
        explicitlyInvalidated: Bool = false
    ) -> Bool {
        var oldBaseline = old.comparisonBaseline
        var newBaseline = new.comparisonBaseline
        // White balance is deliberately evaluated against the current comparison frame. Keep
        // those two RAW fields out of the baseline identity just as rawDevelopChangesFrame does.
        oldBaseline.rawDevelop.neutralTemperature = nil
        newBaseline.rawDevelop.neutralTemperature = nil
        oldBaseline.rawDevelop.neutralTint = nil
        newBaseline.rawDevelop.neutralTint = nil
        return explicitlyInvalidated || oldBaseline != newBaseline
    }
}
