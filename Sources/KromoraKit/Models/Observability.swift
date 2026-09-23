import Foundation
import os.log
import CryptoKit

/// The stable vocabulary used by the Points of Interest instrument.
///
/// Keep these names static: Instruments groups intervals by signpost name, and a stable vocabulary
/// makes captures comparable across builds. The values attached to an interval are intentionally
/// coarse and private-safe; they never contain a filename, URL, or metadata dictionary.
enum KromoraWorkflowStage: CaseIterable {
    case launch
    case libraryIndex
    case scan
    case decode
    case render
    case cache
    case photoSwitch
    case histogram
    case export
    case liveEdit
    case photoTransfer
    case photoThumbnail
    case photoCollectionInsert
    case analysisImagePreparation
    case analysisGlobalTone
    case analysisSubjectMask
    case analysisFaceMask
    case analysisForegroundMask
    case analysisBackgroundMask
    case analysisPersonMask
    case analysisMaskedStatistics
    case analysisAssembly
    case analysisTotal
    case autoTotal
    case autoAnalysis
    case autoCandidateRender

    var name: StaticString {
        switch self {
        case .launch: return "Launch"
        case .libraryIndex: return "LibraryIndex"
        case .scan: return "Scan"
        case .decode: return "Decode"
        case .render: return "Render"
        case .cache: return "Cache"
        case .photoSwitch: return "PhotoSwitch"
        case .histogram: return "Histogram"
        case .export: return "Export"
        case .liveEdit: return "LiveEdit"
        case .photoTransfer: return "PhotoTransfer"
        case .photoThumbnail: return "PhotoThumbnail"
        case .photoCollectionInsert: return "PhotoCollectionInsert"
        case .analysisImagePreparation: return "PhotoAnalysisImagePreparation"
        case .analysisGlobalTone: return "PhotoAnalysisGlobalTone"
        case .analysisSubjectMask: return "PhotoAnalysisSubjectMask"
        case .analysisFaceMask: return "PhotoAnalysisFaceMask"
        case .analysisForegroundMask: return "PhotoAnalysisForegroundMask"
        case .analysisBackgroundMask: return "PhotoAnalysisBackgroundMask"
        case .analysisPersonMask: return "PhotoAnalysisPersonMask"
        case .analysisMaskedStatistics: return "PhotoAnalysisMaskedStatistics"
        case .analysisAssembly: return "PhotoAnalysisAssembly"
        case .analysisTotal: return "PhotoAnalysisTotal"
        case .autoTotal: return "AutoTotal"
        case .autoAnalysis: return "AutoAnalysis"
        case .autoCandidateRender: return "AutoCandidateRender"
        }
    }
}

enum KromoraWorkflowEvent: CaseIterable {
    case cacheHit
    case cacheMiss
    case cancellation
    case coalesced
    case pointerInput
    case renderStart
    case renderEnd
    case gpuComplete
    case presentationMaterialized
    case presentationEncoded
    case drawablePresented
    case staleRevision
    case maskOverlayPointerInput
    case maskOverlayPresentationEncoded
    case maskOverlayGPUComplete
    case maskOverlayDrawablePresented
    case libraryIndexWarm
    case libraryIndexRebuild

    var name: StaticString {
        switch self {
        case .cacheHit: return "CacheHit"
        case .cacheMiss: return "CacheMiss"
        case .cancellation: return "Cancellation"
        case .coalesced: return "Coalesced"
        case .pointerInput: return "PointerInput"
        case .renderStart: return "RenderStart"
        case .renderEnd: return "RenderEnd"
        case .gpuComplete: return "GPUComplete"
        case .presentationMaterialized: return "PresentationMaterialized"
        case .presentationEncoded: return "PresentationEncoded"
        case .drawablePresented: return "DrawablePresented"
        case .staleRevision: return "StaleRevision"
        case .maskOverlayPointerInput: return "MaskOverlayPointerInput"
        case .maskOverlayPresentationEncoded: return "MaskOverlayPresentationEncoded"
        case .maskOverlayGPUComplete: return "MaskOverlayGPUComplete"
        case .maskOverlayDrawablePresented: return "MaskOverlayDrawablePresented"
        case .libraryIndexWarm: return "LibraryIndexWarm"
        case .libraryIndexRebuild: return "LibraryIndexRebuild"
        }
    }
}

/// Safe identifiers for signpost arguments.
///
/// A source token is a truncated SHA-256 digest of the existing cache fingerprint. It helps match
/// events for one photo within a trace while ensuring that a user's path is never emitted to the
/// unified log. Quality remains a human-readable enum so interactive, settled, and export work can
/// be separated in Instruments.
struct KromoraTraceContext: Sendable, Equatable {
    let sourceToken: String
    let quality: String

    init(source: ImageSource, quality: RenderQuality) {
        self.init(sourceToken: source.traceToken, quality: quality.rawValue)
    }

    init(sourceFingerprint: String, quality: String) {
        let digest = SHA256.hash(data: Data(sourceFingerprint.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        self.sourceToken = String(digest.prefix(16))
        self.quality = quality
    }

    init(sourceToken: String, quality: String) {
        self.sourceToken = sourceToken
        self.quality = quality
    }

    static let unknown = Self(sourceFingerprint: "unknown", quality: "unknown")
}

/// A small wrapper that makes begin/end pairing explicit at every early return and throw site.
/// Callers hold it as a local variable and use `defer { interval.end() }`.
struct KromoraSignpostInterval {
    private let signposter: OSSignposter
    private let stage: KromoraWorkflowStage
    private let state: OSSignpostIntervalState
    private var isEnded = false

    init(_ stage: KromoraWorkflowStage, context: KromoraTraceContext = .unknown) {
        self.signposter = OSSignposter(subsystem: "com.kromora.app", category: "workflow")
        self.stage = stage
        self.state = signposter.beginInterval(
            stage.name,
            "source=\(context.sourceToken, privacy: .public) quality=\(context.quality, privacy: .public)"
        )
    }

    mutating func end() {
        guard !isEnded else { return }
        isEnded = true
        signposter.endInterval(stage.name, state)
    }
}

enum KromoraObservability {
    private static let signposter = OSSignposter(subsystem: "com.kromora.app", category: "workflow")

    static func begin(
        _ stage: KromoraWorkflowStage,
        source: ImageSource? = nil,
        quality: RenderQuality? = nil
    ) -> KromoraSignpostInterval {
        KromoraSignpostInterval(
            stage,
            context: source.map { KromoraTraceContext(source: $0, quality: quality ?? .preview) }
                ?? .unknown
        )
    }

    /// Photo-analysis quality is deliberately kept separate from render quality. The overload
    /// keeps the common signpost context format while ensuring Instruments can distinguish fast,
    /// standard, and detailed mask work without exposing a Vision type.
    static func begin(
        _ stage: KromoraWorkflowStage,
        source: ImageSource,
        maskQuality: MaskQuality
    ) -> KromoraSignpostInterval {
        KromoraSignpostInterval(
            stage,
            context: KromoraTraceContext(sourceToken: source.traceToken, quality: maskQuality.rawValue)
        )
    }

    static func event(
        _ event: KromoraWorkflowEvent,
        source: ImageSource? = nil,
        quality: RenderQuality? = nil,
        detail: String = ""
    ) {
        let context = source.map { KromoraTraceContext(source: $0, quality: quality ?? .preview) }
            ?? .unknown
        signposter.emitEvent(
            event.name,
            "source=\(context.sourceToken, privacy: .public) quality=\(context.quality, privacy: .public) detail=\(detail, privacy: .public)"
        )
    }

    static func event(
        _ event: KromoraWorkflowEvent,
        source: ImageSource,
        maskQuality: MaskQuality,
        detail: String = ""
    ) {
        let context = KromoraTraceContext(
            sourceToken: source.traceToken, quality: maskQuality.rawValue
        )
        signposter.emitEvent(
            event.name,
            "source=\(context.sourceToken, privacy: .public) quality=\(context.quality, privacy: .public) detail=\(detail, privacy: .public)"
        )
    }

    /// Hash an input name without ever passing it to an OSLog interpolation. Used before an
    /// `ImageSource` exists, during the eager open-time decode.
    static func sourceToken(forInput input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    static func liveEdit(_ event: KromoraWorkflowEvent, source: ImageSource, quality: RenderQuality,
                         revision: UInt64, detail: String = "") {
        self.event(event, source: source, quality: quality,
                   detail: "revision=\(revision) \(detail)")
    }
}
