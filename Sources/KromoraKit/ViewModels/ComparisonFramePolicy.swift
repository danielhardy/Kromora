import Foundation

/// Pure comparison-frame rules shared by the editor orchestration and its tests.
///
/// A comparison baseline represents the developed/cropped source frame, not every edit. Look
/// changes and RAW white-balance Temperature/Tint are evaluated against the existing baseline;
/// other RAW-develop, crop, local-adjustment, and rotation changes establish a new one.
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
        explicitlyInvalidated
            || rawDevelopChangesFrame(from: old.rawDevelop, to: new.rawDevelop)
            || new.crop != old.crop
            || new.localAdjustments != old.localAdjustments
            || new.rotation != old.rotation
    }
}
