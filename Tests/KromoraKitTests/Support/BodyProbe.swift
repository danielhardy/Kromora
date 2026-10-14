import AppKit
import SwiftUI

@testable import KromoraKit

/// Window-independent view-body counting for the `@Observable` migration
/// (`docs/APP_VIEWMODEL_OBSERVATION_PLAN.md`).
///
/// A wrapper view's `body` does not count the evaluations of the view it wraps, so there is no
/// generic "probe around the real view". Views that already count themselves through
/// `RenderDiagnostics` are mounted for real; the rest are measured with a `MirrorProbeView` that
/// reads the same `AppViewModel` properties the real view's `body` reads.

/// Mutable evaluation count shared between a mirror view and the test that reads it.
@MainActor
final class BodyCounter {
    private(set) var count = 0
    func note() { count += 1 }
}

/// One property read a mirror performs, copied from the real view's `body`.
struct MirrorRead {
    let name: String
    let read: @MainActor (AppViewModel) -> Void

    init(_ name: String, _ read: @escaping @MainActor (AppViewModel) -> Void) {
        self.name = name
        self.read = read
    }
}

/// Test-only stand-in for a view that has no production counter. It reads `reads` from the
/// view model in `body` and increments `counter`, so it invalidates exactly when the real view
/// would. It is a mirror, never the production view; baseline rows label it as such.
struct MirrorProbeView: View {
    let viewModel: AppViewModel
    let counter: BodyCounter
    let reads: [MirrorRead]

    var body: some View {
        counter.note()
        for item in reads { item.read(viewModel) }
        return Color.clear
    }
}

/// Read sets of the mirrored views. Re-derive each from `grep 'viewModel\.' <View>.swift`
/// (including its same-file subviews) when the real view changes.
enum MirrorReadSet {
    /// `LightInspectorView.swift`, `ToneCurveEditor`, `ParametricToneCurveControls`.
    static let light: [MirrorRead] = [
        MirrorRead("document.light") { _ = $0.document.light },
        MirrorRead("hasLightAdjustments") { _ = $0.hasLightAdjustments },
    ]

    /// `ColorInspectorView.swift`.
    static let color: [MirrorRead] = [
        MirrorRead("document.color") { _ = $0.document.color },
        MirrorRead("whiteBalance.isSampling") { _ = $0.whiteBalance.isSampling },
        MirrorRead("sourceIsRAW") { _ = $0.sourceIsRAW },
        MirrorRead("rawCapabilities") { _ = $0.capabilities.rawCapabilities },
        MirrorRead("sourceImage") { _ = $0.sourceImage },
        MirrorRead("hasColorAdjustments") { _ = $0.hasColorAdjustments },
        MirrorRead("hasMixerAdjustments") { _ = $0.hasMixerAdjustments },
        MirrorRead("hasGradingAdjustments") { _ = $0.hasGradingAdjustments },
    ]

    /// `EffectsInspectorView.swift`.
    static let effects: [MirrorRead] = [
        MirrorRead("document.effects") { _ = $0.document.effects },
        MirrorRead("hasEffects") { _ = $0.hasEffects },
        MirrorRead("hasNoiseAdjustments") { _ = $0.hasNoiseAdjustments },
    ]

    /// `PreviewView.swift` (its `settings` read is added by `PreviewMirrorView`).
    static let preview: [MirrorRead] = [
        MirrorRead("isLoading") { _ = $0.isLoading },
        MirrorRead("previewState") { _ = $0.previewState },
        MirrorRead("isSideBySideVisible") { _ = $0.isSideBySideVisible },
        MirrorRead("isNavigationLoading") { _ = $0.isNavigationLoading },
        MirrorRead("metadata") { _ = $0.info.metadata },
        MirrorRead("histogram") { _ = $0.info.histogram },
        MirrorRead("statusMessage") { _ = $0.statusMessage },
        MirrorRead("selectedLook") { _ = $0.selectedLook },
        MirrorRead("isShowingOriginal") { _ = $0.isShowingOriginal },
        MirrorRead("isComparisonAvailable") { _ = $0.isComparisonAvailable },
        MirrorRead("whiteBalance.isSampling") { _ = $0.whiteBalance.isSampling },
        MirrorRead("sourceSize") { _ = $0.sourceSize },
        MirrorRead("document.rotation") { _ = $0.document.rotation },
    ]
}

extension MirrorReadSet {
    /// `WhiteBalanceLoupeOverlay` in `PreviewView.swift`: the only reader of the pointer-rate state.
    static let loupe: [MirrorRead] = [
        MirrorRead("whiteBalance.isSampling") { _ = $0.whiteBalance.isSampling },
        MirrorRead("whiteBalance.samplerPoint") { _ = $0.whiteBalance.samplerPoint },
        MirrorRead("whiteBalance.loupeImage") { _ = $0.whiteBalance.loupeImage },
    ]
}

/// Mirror of `PreviewView`, which also reads `settings.showClippingAlerts`.
struct PreviewMirrorView: View {
    let viewModel: AppViewModel
    let counter: BodyCounter

    var body: some View {
        PreviewMirrorBody(viewModel: viewModel, settings: viewModel.settings, counter: counter)
    }
}

private struct PreviewMirrorBody: View {
    let viewModel: AppViewModel
    let settings: KromoraSettings
    let counter: BodyCounter

    var body: some View {
        counter.note()
        for item in MirrorReadSet.preview { item.read(viewModel) }
        _ = settings.showClippingAlerts
        return Color.clear
    }
}

/// Hosts `view` in an `NSHostingView` that is laid out and drained but never shown. No window or
/// awake display is needed. Callers must keep the returned view alive while measuring.
@MainActor
func host<V: View>(
    _ view: V, size: CGSize = CGSize(width: 320, height: 600)
) -> NSHostingView<V> {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    drainMainActor()
    return hosting
}

/// Lets pending SwiftUI updates and main-queue work run.
@MainActor
func drainMainActor(seconds: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Positive control for settings reads: a view that reads `showPhotoNames`, like the filmstrip
/// and grid captions.
struct PhotoNamesMirrorView: View {
    let settings: KromoraSettings
    let counter: BodyCounter

    var body: some View {
        counter.note()
        _ = settings.showPhotoNames
        return Color.clear
    }
}

/// Counts invalidations of the root-owned stored state (`document`, source, navigation,
/// presentation and the comparison flags). `AppViewModel` is `@Observable`, so there is no
/// whole-model publisher; this tracks the properties a view could read from the root.
@MainActor
final class RootChangeProbe {
    private(set) var count = 0
    private let viewModel: AppViewModel

    init(_ viewModel: AppViewModel) {
        self.viewModel = viewModel
        arm()
    }

    func reset() { count = 0 }

    private func arm() {
        withObservationTracking {
            _ = viewModel.document
            _ = viewModel.sourceImage
            _ = viewModel.sourceName
            _ = viewModel.sourceSize
            _ = viewModel.sourceURL
            _ = viewModel.navigation
            _ = viewModel.presentation
            _ = viewModel.isShowingOriginal
            _ = viewModel.isSideBySide
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                self?.count += 1
                self?.arm()
            }
        }
    }
}
