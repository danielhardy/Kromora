import AppKit
import Observation
import Photos
import Synchronization

/// Load state of one Photos review tile.
enum PhotosThumbnailState {
    case loading
    case loaded(NSImage)
    case failed(PhotosThumbnailFailure)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum PhotosThumbnailFailure: Error, Equatable {
    case missingIdentifier
    case accessDenied
    case assetUnavailable
    case cancelled
    case failed(String)

    /// Tooltip for a failed tile, naming the actionable cause when there is one.
    var helpText: String {
        switch self {
        case .accessDenied:
            "Kromora needs access to your Photos library to show thumbnails. Allow it in System Settings > Privacy & Security > Photos, then double-click to retry."
        case .missingIdentifier, .assetUnavailable:
            "Thumbnail unavailable. Double-click to retry."
        case .cancelled:
            "Thumbnail loading was cancelled. Double-click to retry."
        case .failed(let reason):
            "Thumbnail failed: \(reason). Double-click to retry."
        }
    }
}

/// Produces a thumbnail for a Photos local identifier. Tests inject fakes; the app uses
/// `PhotoKitThumbnailProvider`.
protocol PhotosThumbnailProviding: Sendable {
    func thumbnail(for localIdentifier: String) async throws -> NSImage
}

/// Resolves a tile's state from a provider: `.loading` until the provider answers, then `.loaded`
/// or `.failed`. A missing identifier fails immediately.
struct PhotosThumbnailLoader: Sendable {
    let provider: any PhotosThumbnailProviding

    func load(_ localIdentifier: String?) async -> PhotosThumbnailState {
        guard let localIdentifier else { return .failed(.missingIdentifier) }
        do {
            return .loaded(try await provider.thumbnail(for: localIdentifier))
        } catch let failure as PhotosThumbnailFailure {
            return .failed(failure)
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch {
            return .failed(.failed(error.localizedDescription))
        }
    }
}

/// Owns the visible state for one thumbnail request so the UI state transitions can be tested
/// independently of SwiftUI and PhotoKit.
@Observable
@MainActor
final class PhotosThumbnailModel {
    private(set) var state = PhotosThumbnailState.loading

    private let loader: PhotosThumbnailLoader

    init(loader: PhotosThumbnailLoader) {
        self.loader = loader
    }

    func load(_ localIdentifier: String?) async {
        state = .loading
        let result = await loader.load(localIdentifier)
        guard !Task.isCancelled else { return }
        if case .failed(.cancelled) = result { return }
        state = result
    }
}

/// PhotoKit-backed provider. Network access is allowed so iCloud-only originals resolve; the
/// request is cancelled with the calling task and the continuation resumes exactly once, on the
/// first non-degraded result, error, cancellation, or nil image.
struct PhotoKitThumbnailProvider: PhotosThumbnailProviding {
    static let targetSize = CGSize(width: 256, height: 192)

    func thumbnail(for localIdentifier: String) async throws -> NSImage {
        // PhotosPicker's out-of-process access does not authorize PhotoKit: without read access,
        // `fetchAssets` silently returns an empty result. Ask once, then fail with an actionable error.
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { throw PhotosThumbnailFailure.accessDenied }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
        else { throw PhotosThumbnailFailure.assetUnavailable }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let requests = RequestBox()
        let completion = CompletionBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let id = PHImageManager.default().requestImage(
                    for: asset, targetSize: Self.targetSize, contentMode: .aspectFill, options: options
                ) { image, info in
                    let info = info ?? [:]
                    if let error = info[PHImageErrorKey] as? NSError {
                        if completion.finish() {
                            continuation.resume(throwing: PhotosThumbnailFailure.failed(error.localizedDescription))
                        }
                    } else if (info[PHImageCancelledKey] as? Bool) == true {
                        if completion.finish() {
                            continuation.resume(throwing: PhotosThumbnailFailure.cancelled)
                        }
                    } else if let image {
                        // Opportunistic delivery sends a degraded image first; wait for its final
                        // result, and finish only once even if PhotoKit calls the handler again.
                        if (info[PHImageResultIsDegradedKey] as? Bool) == true { return }
                        if completion.finish() { continuation.resume(returning: image) }
                    } else if (info[PHImageResultIsInCloudKey] as? Bool) == true {
                        // Network access is enabled above. If Photos still returns no image and
                        // marks the asset as cloud-only, surface a failed tile instead of waiting.
                        if completion.finish() {
                            continuation.resume(throwing: PhotosThumbnailFailure.assetUnavailable)
                        }
                    } else {
                        if completion.finish() {
                            continuation.resume(throwing: PhotosThumbnailFailure.assetUnavailable)
                        }
                    }
                }
                requests.set(id)
            }
        } onCancel: {
            requests.cancel()
        }
    }
}

/// Holds the PhotoKit request id so the cancellation handler can cancel it.
private final class RequestBox: Sendable {
    private struct State {
        var requestID: PHImageRequestID?
        var isCancelled = false
    }

    private let state = Mutex(State(requestID: nil))

    func set(_ id: PHImageRequestID) {
        let shouldCancel = state.withLock { state in
            state.requestID = id
            return state.isCancelled
        }
        if shouldCancel { PHImageManager.default().cancelImageRequest(id) }
    }

    func cancel() {
        let id = state.withLock { state -> PHImageRequestID? in
            state.isCancelled = true
            return state.requestID
        }
        if let id { PHImageManager.default().cancelImageRequest(id) }
    }
}

/// Prevents accidental multiple continuation resumes if PhotoKit delivers overlapping terminal
/// callbacks (for example, cancellation racing with a completed image result).
private final class CompletionBox: Sendable {
    private let isFinished = Mutex(false)

    func finish() -> Bool {
        isFinished.withLock { finished in
            guard !finished else { return false }
            finished = true
            return true
        }
    }
}
