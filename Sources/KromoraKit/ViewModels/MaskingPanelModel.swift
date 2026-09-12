import Foundation
import Combine

/// Presentation state and intent handling for the legacy semantic-result masking panel. The
/// editor workflow uses `MaskingWorkspace`; this model remains a coordinator-backed compatibility
/// surface and deliberately delegates policy and inversion to shared services.
@MainActor
final class MaskingPanelModel: ObservableObject {
    struct Selection: Identifiable, Hashable {
        let kind: SemanticMaskKind

        var id: SemanticMaskKind { kind }

        var title: String {
            switch kind {
            case .foreground: return "Foreground"
            case .subject: return "Subject"
            case .person: return "Person"
            case .background: return "Background"
            case .face: return "Face"
            case .faceInstance(let index): return "Face \(index + 1)"
            case .foregroundInstance(let index): return "Foreground \(index + 1)"
            case .unknown(let name): return name
            }
        }
    }

    @Published private(set) var availableSelections: [Selection] = []
    @Published private(set) var selectedKind: SemanticMaskKind?
    @Published private(set) var selectedMask: RegionMask?
    @Published private(set) var selectedPixels: NormalizedMask?
    @Published private(set) var appliedMask: RegionMask?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadWarningMessage: String?
    @Published private(set) var unavailableTargetMessages: [String] = []
    @Published var isInverted = false {
        didSet {
            guard isInverted != oldValue else { return }
            appliedMask = nil
            refreshDisplayedPixels()
        }
    }

    private let coordinator: PhotoAnalysisCoordinator
    private let assetID: PhotoAssetID
    private let source: ImageSource
    /// Optional until the local-adjustment model can own a RegionMask. Keeping the hook explicit
    /// lets tests prove the full select/invert/apply handoff without shipping a button that only
    /// dismisses this sheet.
    private let onApply: (@MainActor (PhotoAssetID, RegionMask) -> Void)?
    private var masks: [SemanticMaskKind: RegionMask] = [:]
    private var pixels: [SemanticMaskKind: NormalizedMask] = [:]
    private var loadTask: Task<Void, Never>?

    init(
        coordinator: PhotoAnalysisCoordinator,
        assetID: PhotoAssetID,
        source: ImageSource,
        onApply: (@MainActor (PhotoAssetID, RegionMask) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.assetID = assetID
        self.source = source
        self.onApply = onApply
    }

    deinit { loadTask?.cancel() }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func load() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadWarningMessage = nil
        unavailableTargetMessages = []
        appliedMask = nil
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let candidates: [SemanticMaskKind] = [.subject, .person, .background, .face]
            var found: [SemanticMaskKind: RegionMask] = [:]
            var payloads: [SemanticMaskKind: NormalizedMask] = [:]
            var failures: [SemanticMaskKind: String] = [:]
            await withTaskGroup(of: (SemanticMaskKind, RegionMask?, NormalizedMask?, String?)?.self) { group in
                for kind in candidates {
                    group.addTask { [coordinator, assetID, source] in
                        do {
                            let mask = try await coordinator.mask(
                                assetID: assetID, source: source, kind: kind, quality: .preview
                            )
                            guard let pixels = await coordinator.pixels(for: mask.reference) else {
                                return (kind, mask, NormalizedMask?.none, "Mask pixels were unavailable")
                            }
                            return (kind, mask, pixels, nil)
                        } catch is CancellationError {
                            return nil
                        } catch {
                            return (kind, RegionMask?.none, NormalizedMask?.none,
                                    Self.errorDescription(error))
                        }
                    }
                }
                for await result in group {
                    guard let result else { continue }
                    if let mask = result.1, let pixels = result.2 {
                        found[result.0] = mask
                        payloads[result.0] = pixels
                    } else if let failure = result.3 {
                        failures[result.0] = failure
                    }
                }
            }
            guard !Task.isCancelled else { return }
            masks = found
            pixels = payloads
            let filtered = candidates.compactMap { kind -> (SemanticMaskKind, String)? in
                guard let mask = found[kind],
                      MaskPresentationPolicy.decision(for: mask) != .actionable else { return nil }
                let decision = MaskPresentationPolicy.decision(for: mask)
                return (kind, decision.userMessage ?? "This target is unavailable.")
            }
            unavailableTargetMessages = filtered.map { "\(Self.title(for: $0.0)): \($0.1)" }
            loadWarningMessage = failures.isEmpty && filtered.isEmpty
                ? nil : "Some mask targets were unavailable."
            availableSelections = candidates
                .filter {
                    guard let mask = found[$0] else { return false }
                    return MaskPresentationPolicy.decision(for: mask) == .actionable
                }
                .map(Selection.init(kind:))
            isLoading = false
            if selectedKind == nil, let first = availableSelections.first?.kind {
                select(first)
            } else {
                refreshDisplayedPixels()
            }
            if availableSelections.isEmpty {
                errorMessage = failures.isEmpty
                    ? (unavailableTargetMessages.isEmpty
                        ? "No semantic regions were available for this photo."
                        : "No usable regions were found for this photo.")
                    : "Mask generation failed for this photo. Retry to try again."
            }
        }
    }

    private static func title(for kind: SemanticMaskKind) -> String {
        Selection(kind: kind).title
    }

    func select(_ kind: SemanticMaskKind) {
        guard let mask = masks[kind] else { return }
        selectedKind = kind
        selectedMask = mask
        appliedMask = nil
        refreshDisplayedPixels()
    }

    var selectedMaskTitle: String? {
        guard let selectedKind else { return nil }
        let title = Selection(kind: selectedKind).title
        return isInverted ? "Inverted \(title)" : title
    }

    var canApplyMask: Bool {
        selectedMask != nil && onApply != nil && !isApplying
    }

    var applyHelp: String {
        guard selectedMask != nil else { return "Select an available mask first." }
        guard onApply != nil else {
            return "Local adjustments cannot own a mask yet, so applying is disabled."
        }
        return "Use \(selectedMaskTitle ?? "mask") in the active local adjustment."
    }

    /// Applies the selected RegionMask, or the RegionMask produced by the shared invert operation.
    /// The callback carries the asset ID as well as the mask so a future local-adjustment owner can
    /// reject a late result from another photo instead of accidentally attaching it to the current
    /// document.
    func apply() async {
        guard let selectedMask else { return }
        guard let onApply else {
            errorMessage = "Local adjustments cannot own a mask yet. Applying is disabled until an adjustment hook is available."
            return
        }

        isApplying = true
        defer { isApplying = false }
        do {
            let mask = isInverted
                ? try await coordinator.invertedMask(selectedMask)
                : selectedMask
            guard !Task.isCancelled else { return }
            onApply(assetID, mask)
            appliedMask = mask
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Could not prepare \(selectedMaskTitle ?? "the mask"). Try again."
        }
    }

    private nonisolated static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func refreshDisplayedPixels() {
        guard let selectedKind, let sourcePixels = pixels[selectedKind] else {
            selectedPixels = nil
            return
        }
        selectedPixels = isInverted ? try? MaskOperations.invert(sourcePixels) : sourcePixels
    }
}
