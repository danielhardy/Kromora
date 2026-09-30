import CoreGraphics
import Foundation

/// Loads a library-sized original thumbnail through the three tiers, cheapest first:
/// the bounded in-memory cache, the package's packed frame, then a decode of the source.
///
/// Only the last tier reads the original file, and it runs only on a miss (new photo, changed
/// source, or a frame the classifier refuses). A decoded thumbnail is handed to the frame store so
/// the next launch starts from a packed record instead.
enum OriginalThumbnailLoader {
    static func load(
        url: URL?, data: Data?, dataFingerprint: String?,
        identity: PortablePhotoIdentity, store: ThumbnailFrameStore?
    ) async -> CGImage? {
        let size = PlatformThumbnailProvider.libraryMaxPixelSize
        if let cached = PlatformThumbnailProvider.memoryCachedImage(
            identity: identity, maxPixelSize: size
        ) { return cached }

        if let store, let hit = await store.read(.original, for: identity),
           FrameClassifier.classify(
               hit.frame.metadata, against: OriginalThumbnailSignature.currentInputs(for: identity)
           ) == .exact
        {
            PlatformThumbnailProvider.primeMemoryCache(
                hit.image, identity: identity, maxPixelSize: size
            )
            return hit.image
        }

        let decoded = await Task.detached { () -> (image: CGImage, frame: PresentationFrame?)? in
            let image: CGImage?
            if let url {
                image = PlatformThumbnailProvider.generateCGImage(
                    from: url, maxPixelSize: size, portableIdentity: identity
                )
            } else if let data {
                image = PlatformThumbnailProvider.generateCGImage(
                    from: data, maxPixelSize: size, dataFingerprint: dataFingerprint,
                    portableIdentity: identity
                )
            } else {
                image = nil
            }
            guard let image else { return nil }
            let frame = store == nil
                ? nil : ThumbnailFrameEncoder.originalFrame(image: image, identity: identity)
            return (image, frame)
        }.value
        guard !Task.isCancelled else { return nil }
        guard let decoded else { return nil }
        if let store, let frame = decoded.frame { await store.enqueueWrite(frame) }
        return decoded.image
    }
}
