import Foundation
import Combine

/// Developer-only analysis presentation state. The SwiftUI panels render this model but do not
/// own analysis requests, mask policy, or task-group lifetime.
@MainActor
final class AnalysisDebugPanelModel: ObservableObject {
    struct MaskEntry: Identifiable {
        let kind: SemanticMaskKind
        let mask: RegionMask?
        let pixels: NormalizedMask?
        let providerError: String?

        var id: SemanticMaskKind { kind }

        var normalModeReason: String {
            if let providerError { return "Unavailable: \(providerError)" }
            guard let mask else { return "Unavailable: no provider result" }
            return MaskPresentationPolicy.decision(for: mask).userMessage ?? "Available in normal mode"
        }

        var title: String {
            switch kind {
            case .foreground: return "Foreground"
            case .subject: return "Subject"
            case .background: return "Background"
            case .person: return "Person"
            case .face: return "Face"
            case .faceInstance(let index): return "Face \(index + 1)"
            case .foregroundInstance(let index): return "Foreground \(index + 1)"
            case .unknown(let name): return name
            }
        }

        var editingMaskUnavailableMessage: String {
            if let providerError, !providerError.isEmpty {
                return "\(title) editing mask unavailable: \(providerError)"
            }
            guard let mask else { return "\(title) editing mask unavailable" }
            return MaskPresentationPolicy.decision(for: mask).userMessage
                ?? "\(title) editing mask pixels are unavailable"
        }
    }

    @Published private(set) var analysis: PhotoAnalysis?
    @Published private(set) var masks: [MaskEntry] = []
    @Published var visibleKinds = Set<SemanticMaskKind>()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let coordinator: PhotoAnalysisCoordinator
    private let assetID: PhotoAssetID
    private let source: ImageSource
    private var loadTask: Task<Void, Never>?

    init(coordinator: PhotoAnalysisCoordinator, assetID: PhotoAssetID, source: ImageSource) {
        self.coordinator = coordinator
        self.assetID = assetID
        self.source = source
    }

    deinit { loadTask?.cancel() }

    /// Inspect owns the lifetime of the request. Collapsing the section should release the
    /// demand-driven work instead of allowing an off-screen inspector to keep producing masks.
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func load() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let analysis = try await coordinator.analyze(
                    assetID: assetID, source: source, level: .standard
                )
                let candidates: [SemanticMaskKind] = [
                    .subject, .background, .person, .face, .foregroundInstance(0)
                ]
                var entries: [MaskEntry] = []
                await withTaskGroup(of: MaskEntry?.self) { group in
                    for kind in candidates {
                        group.addTask { [coordinator, assetID, source] in
                            do {
                                let quality: MaskQuality = kind.isInfoEditingMask ? .preview : .analysis
                                let mask = try await coordinator.mask(
                                    assetID: assetID, source: source, kind: kind, quality: quality
                                )
                                let pixels = await coordinator.pixels(for: mask.reference)
                                return MaskEntry(kind: kind, mask: mask, pixels: pixels, providerError: nil)
                            } catch is CancellationError {
                                return nil
                            } catch {
                                return MaskEntry(
                                    kind: kind, mask: nil, pixels: nil,
                                    providerError: Self.errorDescription(error)
                                )
                            }
                        }
                    }
                    for await entry in group {
                        if let entry { entries.append(entry) }
                    }
                }
                guard !Task.isCancelled else { return }
                self.analysis = analysis
                self.masks = entries.sorted { $0.title < $1.title }
                self.visibleKinds = Set(entries.compactMap { $0.pixels == nil ? nil : $0.kind })
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func isVisible(_ kind: SemanticMaskKind) -> Bool {
        visibleKinds.contains(kind)
    }

    func setVisible(_ kind: SemanticMaskKind, _ visible: Bool) {
        if visible { visibleKinds.insert(kind) }
        else { visibleKinds.remove(kind) }
    }

    private nonisolated static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private extension SemanticMaskKind {
    var isInfoEditingMask: Bool {
        switch self {
        case .subject, .person: return true
        default: return false
        }
    }
}
