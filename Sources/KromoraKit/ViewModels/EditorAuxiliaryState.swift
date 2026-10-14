import CoreGraphics
import Foundation

/// White-balance sampler UI state. The point and loupe image change at pointer rate, so they live
/// apart from `AppViewModel`: only the canvas loupe subtree reads them.
@MainActor
@Observable
final class WhiteBalanceSamplerState {
    var isSampling = false
    var samplerPoint: CGPoint?
    var loupeImage: CGImage?

    func begin() {
        isSampling = true
        clearSample()
    }

    func end() {
        isSampling = false
        clearSample()
    }

    func clearSample() {
        samplerPoint = nil
        loupeImage = nil
    }
}

/// What the open image's RAW decoder can do, plus the storage/probe status that travels with it.
@MainActor
@Observable
final class EditorCapabilityState {
    /// `nil` for a standard image and also while the probe is still running on a RAW; use
    /// `probeCompleted` (or `AppViewModel.developPanelState`) to tell those apart.
    private(set) var rawCapabilities: RAWCapabilities?
    /// Whether the capability answer belongs to the currently selected source.
    private(set) var probeCompleted = false
    /// The most recent persistence warning. A damaged edit catalog must not prevent the source
    /// image from opening, but it should remain visible to the user.
    private(set) var editStoreStatus: String?

    func publish(_ capabilities: RAWCapabilities?) {
        rawCapabilities = capabilities
        probeCompleted = true
    }

    func reset() {
        rawCapabilities = nil
        probeCompleted = false
    }

    func setEditStoreStatus(_ status: String?) { editStoreStatus = status }
}

/// Auto-adjustment lifecycle and the Look-resolution warning. Auto has its own lifecycle rather
/// than borrowing the Info histogram's loading flag.
@MainActor
@Observable
final class AutoLookStatusState {
    private(set) var autoAdjustmentState: AutoAdjustmentState = .unavailable(
        "Open a supported photo to enable Auto."
    )
    /// Determinate progress for the active Auto invocation; `nil` means Auto is settled.
    private(set) var autoAdjustmentProgress: Double?
    /// A missing LUT never prevents the source image from rendering. Kept separate from the
    /// transient image status so the stored `LUTID` remains visible and recoverable.
    private(set) var lutResolutionStatus: String?

    func publishAuto(_ state: AutoAdjustmentState, progress: Double?) {
        autoAdjustmentState = state
        autoAdjustmentProgress = progress.map { min(max($0, 0), 1) }
    }

    func setLUTResolutionStatus(_ status: String?) { lutResolutionStatus = status }
}
