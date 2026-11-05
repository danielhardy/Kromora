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
/// **Slider calibration.** Decoder exposure is not RGB EV. The decoder applies its tone curve after
/// exposure, so one decoder stop moves midtones further than one RGB stop. Measured over four Sony
/// ARWs (`RAWExposureCalibrationBenchmark`), the decoder exposure whose whole-frame median luminance
/// matches RGB exposure at −4…+4 EV is 0.73–0.83 of the slider value for every file that stays below
/// the shoulder, and negative values are 0.74–0.82 on all four. `decoderStopsPerSliderStop` encodes
/// that. It aims at matched *midtone* brightness, not equal pixels: the decoder keeps a highlight
/// shoulder RGB EV does not have, so positive moves on bright scenes intentionally brighten less.
///
/// **Existing explicit decoder exposure.** A document with a nonzero `rawDevelop.exposure` (written
/// while the Develop tab was reachable) keeps it. It is already in decoder stops, so it is added to
/// the calibrated slider value as a single combined decoder exposure.
///
/// Local-mask exposure and standard-image exposure stay RGB.
enum RAWExposureRouting {
    /// Decoder stops per Exposure-slider stop; see the calibration note above.
    static let decoderStopsPerSliderStop = 0.75

    /// The decoder exposure that `sliderEV` asks for.
    static func decoderExposure(forSliderEV sliderEV: Double) -> Double {
        sliderEV * decoderStopsPerSliderStop
    }

    /// The decoder exposure to write, combining an explicit `rawDevelop.exposure` with the slider.
    static func combinedDecoderExposure(explicit: Double?, sliderEV: Double) -> Double? {
        guard sliderEV != 0 else { return explicit }
        return (explicit ?? 0) + decoderExposure(forSliderEV: sliderEV)
    }
}

extension EditDocument {
    /// The document the renderer builds from for `source`.
    ///
    /// For a RAW, global Exposure moves into `rawDevelop.exposure`; for a standard image the
    /// document is returned unchanged.
    func routedForRendering(source kind: ImageSource.Kind) -> EditDocument {
        guard kind == .raw, light.exposure != 0 else { return self }
        var routed = self
        routed.rawDevelop.exposure = RAWExposureRouting.combinedDecoderExposure(
            explicit: rawDevelop.exposure, sliderEV: light.exposure)
        routed.light.exposure = 0
        return routed
    }
}
