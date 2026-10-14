import AppKit
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
    case assetUnavailable
    case cancelled
    case failed(String)
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

/// PhotoKit-backed provider. Network access is allowed so iCloud-only originals resolve; the
/// request is cancelled with the calling task and the continuation resumes exactly once, on the
/// first non-degraded result, error, cancellation, or nil image.
struct PhotoKitThumbnailProvider: PhotosThumbnailProviding {
    static let targetSize = CGSize(width: 256, height: 192)

    func thumbnail(for localIdentifier: String) async throws -> NSImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
        else { throw PhotosThumbnailFailure.assetUnavailable }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let requests = RequestBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let id = PHImageManager.default().requestImage(
                    for: asset, targetSize: Self.targetSize, contentMode: .aspectFill, options: options
                ) { image, info in
                    let info = info ?? [:]
                    if let error = info[PHImageErrorKey] as? NSError {
                        continuation.resume(throwing: PhotosThumbnailFailure.failed(error.localizedDescription))
                    } else if (info[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: PhotosThumbnailFailure.cancelled)
                    } else if let image {
                        // Opportunistic delivery sends a degraded image first; the final one
                        // follows. Accept the first image and stop, keeping resume single-shot.
                        if (info[PHImageResultIsDegradedKey] as? Bool) == true { return }
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: PhotosThumbnailFailure.assetUnavailable)
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
    private let state = Mutex<PHImageRequestID?>(nil)
    private let cancelled = Mutex(false)

    func set(_ id: PHImageRequestID) {
        let shouldCancel = cancelled.withLock { $0 }
        if shouldCancel { PHImageManager.default().cancelImageRequest(id) }
        state.withLock { $0 = id }
    }

    func cancel() {
        cancelled.withLock { $0 = true }
        if let id = state.withLock({ $0 }) { PHImageManager.default().cancelImageRequest(id) }
    }
}
