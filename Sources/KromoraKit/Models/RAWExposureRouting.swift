import Foundation

/// How the one global Exposure control reaches the pixels of a RAW source (KRMA-1174).
///
/// The slider is `LightAdjustments.exposure` for every source; the user sees one control. A
/// standard image renders it as `CIExposureAdjust` on developed RGB (`RenderPipeline.applyLight`).
/// A RAW instead hands it to `CIRAWFilter.exposure`, so it is applied inside the decoder — before the
/// Look and before every RGB stage, and ahead of the decoder's own tone curve and highlight handling.
///
/// **Routing happens on a derived document, never on the stored one.** `routedForRendering(source:)`
/// returns the copy the renderer actually builds from: the stored `light.exposure` is folded into
/// `rawDevelop.exposure` and zeroed, so the value is applied exactly once, `applyLight` has nothing
/// left to do, and the identity digests (developed-source key, processing prefix, session key) all
/// see the routed values without any extra invalidation rule. The stored document, undo history,
/// clipboard, package file and Auto's reads of `light.exposure` are untouched.
///
/// **Slider calibration, per decoder family (KRMA-1174, KRMA-1180).** Decoder exposure is not RGB EV
/// for every file. Two families measured so far (`RAWExposureCalibrationBenchmark`, whole-frame median
/// luminance matched to RGB exposure at −4…+4 EV):
///
/// - **Tone-curve decoders** — four Sony ARWs and a Samsung Bayer DNG. The decoder applies its tone
///   curve after exposure, so one decoder stop moves midtones further than one RGB stop: the matching
///   decoder exposure is 0.73–0.83 of the slider value for every file that stays below the shoulder
///   (Samsung: −4→−3.00, −2→−1.45, −1→−0.73, +1→+0.83, +2→+1.97). `decoderStopsPerSliderStop` (0.75)
///   encodes that. It aims at matched *midtone* brightness, not equal pixels: the decoder keeps a
///   highlight shoulder RGB EV does not have, so positive moves on bright scenes brighten less.
/// - **Local-tone-map decoders** — two Apple ProRAW DNGs (linear-raw, `isLocalToneMapSupported`).
///   Decoder exposure matched RGB EV exactly (ratio 1.00 at every setting from −4 to +4, the same as the
///   two earlier DNG controls), so `linearDecoderStopsPerSliderStop` is 1.0. Applying 0.75 there made
///   the slider 25% too weak in both directions.
///
/// The family is read from the file's decoder (`RAWCapabilities.isLocalToneMapSupported`), which every
/// Sony ARW and the Samsung DNG report false and both Apple DNGs true. That is a two-camera-maker
/// observation, not a proof about every local-tone-map decoder; anything unmeasured, and any call that
/// has no decoder state, uses the tone-curve ratio.
///
/// **Existing explicit decoder exposure.** A document with a nonzero `rawDevelop.exposure` (written
/// while the Develop tab was reachable) keeps it. It is already in decoder stops, so it is added to
/// the calibrated slider value as a single combined decoder exposure.
///
/// Local-mask exposure and standard-image exposure stay RGB.
enum RAWExposureRouting {
    /// Decoder stops per Exposure-slider stop for tone-curve decoders; see the calibration note above.
    static let decoderStopsPerSliderStop = 0.75

    /// Decoder stops per slider stop for decoders whose exposure already behaves as linear EV.
    static let linearDecoderStopsPerSliderStop = 1.0

    /// The calibration for `decoder`; `nil` (no decoder state available) is the tone-curve ratio.
    static func stopsPerSliderStop(decoder: RAWCapabilities?) -> Double {
        decoder?.isLocalToneMapSupported == true
            ? linearDecoderStopsPerSliderStop : decoderStopsPerSliderStop
    }

    /// The decoder exposure that `sliderEV` asks for.
    static func decoderExposure(forSliderEV sliderEV: Double, decoder: RAWCapabilities? = nil) -> Double {
        sliderEV * stopsPerSliderStop(decoder: decoder)
    }

    /// The decoder exposure to write, combining an explicit `rawDevelop.exposure` with the slider.
    static func combinedDecoderExposure(
        explicit: Double?, sliderEV: Double, decoder: RAWCapabilities? = nil
    ) -> Double? {
        guard sliderEV != 0 else { return explicit }
        return (explicit ?? 0) + decoderExposure(forSliderEV: sliderEV, decoder: decoder)
    }

    /// Whether routing `document` needs the file's decoder state: a nonzero global Exposure (to pick
    /// the calibration) or active Luminance noise reduction (support flag and default).
    static func needsDecoderState(_ document: EditDocument) -> Bool {
        document.light.exposure != 0 || RAWDetailRouting.needsDecoderState(document)
    }
}

extension EditDocument {
    /// The document the renderer builds from for `source`.
    ///
    /// For a RAW, global Exposure moves into `rawDevelop.exposure`, and, given the file's decoder
    /// state, global Luminance noise reduction moves into the decoder when it supports
    /// it (`RAWDetailRouting`). `decoder` selects the exposure calibration for the file's family
    /// (without it the tone-curve ratio applies) and is required for the noise reduction, which
    /// otherwise stays in RGB. A standard image is returned unchanged.
    func routedForRendering(
        source kind: ImageSource.Kind, decoder: RAWCapabilities? = nil
    ) -> EditDocument {
        guard kind == .raw else { return self }
        var routed = self
        if light.exposure != 0 {
            routed.rawDevelop.exposure = RAWExposureRouting.combinedDecoderExposure(
                explicit: rawDevelop.exposure, sliderEV: light.exposure, decoder: decoder)
            routed.light.exposure = 0
        }
        if let decoder, RAWDetailRouting.needsDecoderState(self) {
            routed = routed.routingNoiseReduction(decoder: decoder)
        }
        return routed
    }
}
