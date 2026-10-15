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
        identity: PortablePhotoIdentity, store: ThumbnailFrameStore?,
        ledger: FrameLookupLedger = .shared,
        surface: FrameLookupSurface = .gridOriginal,
        decodeObserver: (@Sendable () async -> Void)? = nil
    ) async -> CGImage? {
        let size = PlatformThumbnailProvider.libraryMaxPixelSize
        if let cached = PlatformThumbnailProvider.memoryCachedImage(
            identity: identity, maxPixelSize: size
        ) {
            KromoraObservability.thumbnailDiagnostic(.thumbnailOriginalLoad, detail: "tier=memory")
            return cached
        }

        // Why a decode happened is the question the library-launch diagnostics have to answer, so
        // the miss reason travels with the decode line below.
        var packOutcome = store == nil ? "noStore" : "unread"
        let clock = ContinuousClock()
        let lookupStart = clock.now
        var lookupMs = 0
        if let store {
            let result = await store.readWithOutcome(.original, for: identity)
            lookupMs = Self.milliseconds(clock.now - lookupStart)
            if let hit = result.hit {
                let classification = FrameClassifier.classifyWithReason(
                    hit.frame.metadata, against: OriginalThumbnailSignature.currentInputs(for: identity)
                )
                await ledger.record(surface: surface, outcome: Self.outcome(classification))
                if classification.classification == .exact {
                    PlatformThumbnailProvider.primeMemoryCache(
                        hit.image, identity: identity, maxPixelSize: size
                    )
                    KromoraObservability.thumbnailDiagnostic(
                        .thumbnailOriginalLoad, detail: "tier=pack lookupMs=\(lookupMs)"
                    )
                    return hit.image
                }
                packOutcome = "rejected.\(classification.reason?.rawValue ?? "\(classification.classification)")"
            } else {
                packOutcome = result.corrupt ? "corrupt" : "missing"
                await ledger.record(
                    surface: surface,
                    outcome: result.corrupt ? .corrupt : .missingFile
                )
            }
        }

        await decodeObserver?()
        let decoded = await Self.decode(
            url: url, data: data, dataFingerprint: dataFingerprint, identity: identity,
            size: size, buildsFrame: store != nil
        )
        guard !Task.isCancelled else { return nil }
        KromoraObservability.thumbnailDiagnostic(
            .thumbnailOriginalLoad,
            detail: "tier=decode packOutcome=\(packOutcome) lookupMs=\(lookupMs) "
                + "decodeMs=\(Self.milliseconds(clock.now - lookupStart) - lookupMs) "
                + "decoded=\(decoded != nil)"
        )
        guard let decoded else { return nil }
        if let store, let frame = decoded.frame { await store.enqueueWrite(frame) }
        return decoded.image
    }

    @concurrent private static func decode(
        url: URL?, data: Data?, dataFingerprint: String?, identity: PortablePhotoIdentity,
        size: Int, buildsFrame: Bool
    ) async -> (image: CGImage, frame: PresentationFrame?)? {
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
        guard let decodedImage = image else { return nil }
        // Show exactly what will be stored, so a cold decode and a later packed read agree.
        let shown = ThumbnailFrameEncoder.normalizedRaster(decodedImage)?.image ?? decodedImage
        let frame = buildsFrame
            ? ThumbnailFrameEncoder.originalFrame(image: shown, identity: identity) : nil
        return (shown, frame)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }

    private static func outcome(
        _ result: (classification: FrameClassification, reason: FrameRejectionReason?)
    ) -> FrameLookupOutcome {
        switch result.classification {
        case .exact: .exact
        case .staleCompatible: .staleCompatible
        case .provisionalOnly: .provisionalOnly
        case .unusable: .rejected(result.reason ?? .sourceFingerprintMismatch)
        }
    }
}
