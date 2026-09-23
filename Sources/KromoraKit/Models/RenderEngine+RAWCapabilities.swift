import CoreGraphics
import Foundation

/// Source preparation and RAW-decoder capability reporting, split out of `RenderEngine.swift`
/// (KRMA-530). This responsibility owns the single interactive `InteractiveRAWFilterSession` and
/// never touches `outputImage`, so it can answer geometry/capability questions without evicting the
/// developed-source memo the visible preview depends on.
extension RenderEngine {
    /// Admit a source using decoder-owned geometry. Standard-image dimensions come from ImageIO;
    /// RAW dimensions come from the renderer-owned session, which also rejects a filter whose
    /// output cannot be rasterized before publishing a prepared source.
    func prepareSource(_ source: ImageSource) -> ImageSourcePreparation? {
        switch source.kind {
        case .standard:
            guard let prepared = try? standardPreparation(for: source) else { return nil }
            return prepared
        case .raw:
            guard let session = session(for: source) else { return nil }
            // The session's filter size is sensor-native; the orientation tag decides the
            // display axes (quarter-turns swap them). The canvas, crop math, and scale
            // factors all work in display space, matching the standard-image path.
            let preparedSource = ImageSource(
                backing: source.backing, kind: .raw, nativeExtent: session.orientedNativeSize,
                portableIdentity: source.cacheIdentity.with(
                    geometry: PhotoPixelDimensions(
                        width: Int(session.orientedNativeSize.width),
                        height: Int(session.orientedNativeSize.height)
                    )
                )
            )
            return ImageSourcePreparation(source: preparedSource)
        }
    }

    fileprivate func standardPreparation(for source: ImageSource) throws -> ImageSourcePreparation {
        let extent: CGSize
        switch source.backing {
        case .url(let url):
            extent = try ImageDecoder.prepareStandard(from: url)
        case .data(let data):
            extent = try ImageDecoder.prepareStandard(from: data, name: "import")
        }
        return ImageSourcePreparation(source: ImageSource(
            backing: source.backing, kind: .standard, nativeExtent: extent,
            portableIdentity: source.cacheIdentity.with(
                geometry: PhotoPixelDimensions(width: Int(extent.width), height: Int(extent.height))
            )
        ))
    }

    /// Read capabilities from the same renderer-owned session used for preparation and preview.
    ///
    /// **`outputImage` is deliberately never touched.** That is the difference between ~25 ms and
    /// ~183 ms on a 30 MB DNG (measured; see the Step 10a design doc), and it is why this can run on
    /// every image open without being felt. It also leaves the developed-source memo alone — a
    /// capability question must not evict the image the user is looking at.
    ///
    /// **A gated seed is read only when its gate is open.** Every property below the `is*Supported`
    /// line is a knob this particular decoder may not offer, and what an unoffered property returns is
    /// not a default the panel should show — it is nothing at all. Where the gate is shut the seed
    /// stays at `RAWCapabilities`' own default, which no control can reach anyway: `supports(_:)`
    /// withdraws the control on the same flag.
    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {
        guard case .raw = source.kind else { return nil }
        guard let session = session(for: source) else { return nil }
        let captured = session.capabilities()
        // Keep the capability-to-seed relationship explicit at this API boundary. The session has
        // already captured these values before any mutable development output can change them.
        return RAWCapabilities(
            isSharpnessSupported: captured.isSharpnessSupported,
            isContrastSupported: captured.isContrastSupported,
            isDetailSupported: captured.isDetailSupported,
            isMoireReductionSupported: captured.isMoireReductionSupported,
            isLocalToneMapSupported: captured.isLocalToneMapSupported,
            isLuminanceNoiseReductionSupported: captured.isLuminanceNoiseReductionSupported,
            isColorNoiseReductionSupported: captured.isColorNoiseReductionSupported,
            isLensCorrectionSupported: captured.isLensCorrectionSupported,
            isHighlightRecoverySupported: captured.isHighlightRecoverySupported,
            asShotTemperature: captured.asShotTemperature,
            asShotTint: captured.asShotTint,
            baselineExposure: captured.baselineExposure,
            shadowBias: captured.shadowBias,
            sharpnessAmount: captured.isSharpnessSupported ? captured.sharpnessAmount : 0,
            contrastAmount: captured.isContrastSupported ? captured.contrastAmount : 0,
            detailAmount: captured.isDetailSupported ? captured.detailAmount : 0,
            moireReductionAmount:
                captured.isMoireReductionSupported ? captured.moireReductionAmount : 0,
            localToneMapAmount:
                captured.isLocalToneMapSupported ? captured.localToneMapAmount : 0,
            luminanceNoiseReductionAmount: captured.isLuminanceNoiseReductionSupported
                ? captured.luminanceNoiseReductionAmount : 0,
            colorNoiseReductionAmount: captured.isColorNoiseReductionSupported
                ? captured.colorNoiseReductionAmount : 0,
            lensCorrectionEnabled:
                captured.isLensCorrectionSupported ? captured.lensCorrectionEnabled : false
        )
    }

    /// Not `fileprivate`: `RenderEngine.swift`'s developed-source cache path (line ~2280) also
    /// resolves the same interactive session, so this stays reachable across the split (KRMA-530).
    func session(for source: ImageSource) -> InteractiveRAWFilterSession? {
        let fingerprint = source.decoderFingerprint
        if interactiveRAWSession?.fingerprint != fingerprint {
            // This is the one renderer-owned RAW session. Replacing it releases the old source
            // graph before the new source is admitted, keeping rapid navigation bounded.
            interactiveRAWSession = InteractiveRAWFilterSession(source: source)
            if interactiveRAWSession != nil { rawFilterConstructionCount += 1 }
        }
        return interactiveRAWSession
    }
}
