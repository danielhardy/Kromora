import Foundation

/// How the global Luminance noise reduction control reaches the pixels of a RAW source (KRMA-1175).
///
/// **What moves.** Luminance noise reduction is routed to `CIRAWFilter.luminanceNoiseReductionAmount`
/// where the file's decoder supports it. The decoder denoises sensor data before the tone curve and
/// the Look. Measured 1:1 on four Sony ARWs at matched flat-field noise it keeps 98–100% of edge
/// contrast where `CINoiseReduction` keeps 53–83% on the files where both reach the match, and it
/// shows no overshoot (`docs/TESTING.md`). A routed channel is **removed from the RGB stage
/// entirely** (its Amount, Detail and Contrast are reset on the derived document), so it is applied
/// once.
///
/// **What stays RGB, and why.**
/// - **Colour noise reduction.** Raising `colorNoiseReductionAmount` from its 0.5 default to 1.0
///   changed flat-patch chroma noise by under 2% on all four files, while the RGB control reaches
///   large reductions. The decoder's upward range does not serve the control's intent.
/// - **Sharpening** (Amount, Radius, Detail, Masking). `CIRAWFilter.sharpnessAmount` has no radius or
///   edge mask, and the decoder's default sits at 0.83–1.0 on the measured Sony files, leaving at most
///   0.17 of headroom and none on two of four. Routing would make the control a near no-op on exactly
///   the files that need it.
/// - Standard images; local-mask noise reduction and sharpness; and any RAW whose decoder reports
///   luminance noise reduction unsupported.
///
/// **Mapping.** The decoder's default is a per-image value (0.0015 on a low-ISO frame, 0.71 at ISO
/// 2000), so slider 0 must leave it alone and the control must only ever add noise reduction on top
/// of it:
///
///     amount = base + (1 − base) × strength
///     strength = (noise / 100) × (1 − 0.65 × contrast / 100) × (1.5 − detail / 100)
///
/// `base` is an explicit `rawDevelop` amount if the document has one, else the decoder's default.
/// `contrast` keeps the RGB meaning (retain part of the unfiltered source), at the same 0.65 weight.
/// `detail` is the RGB "recover detail after smoothing" knob: the decoder has no sharpness inside its
/// noise reduction, so the equivalent intent is to smooth less (×1.0 at the default 50, ×0.5 at 100,
/// ×1.5 at 0). `strength` is clamped to 1. This is a stable, monotonic mapping into the decoder's
/// remaining headroom, **not** a claim that decoder and RGB amounts are equivalent — the matched
/// comparison in `docs/TESTING.md` shows they are not. The Apple default is the floor and the control
/// scales the same decoder parameter, so the two never stack.
///
/// Like exposure routing this happens on a derived document; the stored document, undo history,
/// clipboard and package are untouched, and routing a routed document changes nothing (the routed
/// channel's amount is zero).
enum RAWDetailRouting {
    /// The decoder amount the Luminance controls ask for on top of `base`.
    static func decoderAmount(base: Double, noise: Double, detail: Double, contrast: Double) -> Double {
        let strength = min(1, noise / 100 * (1 - contrast / 100 * 0.65) * (1.5 - detail / 100))
        return min(1, base + (1 - base) * strength)
    }

    /// Whether routing `document` needs the decoder's support flag and default.
    static func needsDecoderState(_ document: EditDocument) -> Bool {
        document.effects.detail.luminanceNoise > 0
    }
}

extension EditDocument {
    /// Fold supported global Luminance noise reduction into `rawDevelop`; see `RAWDetailRouting`.
    func routingNoiseReduction(decoder: RAWCapabilities) -> EditDocument {
        var routed = self
        let detail = effects.detail
        if detail.luminanceNoise > 0, decoder.isLuminanceNoiseReductionSupported {
            routed.rawDevelop.luminanceNoiseReductionAmount = RAWDetailRouting.decoderAmount(
                base: rawDevelop.luminanceNoiseReductionAmount
                    ?? decoder.luminanceNoiseReductionAmount,
                noise: detail.luminanceNoise, detail: detail.luminanceDetail,
                contrast: detail.luminanceContrast)
            routed.effects.detail.luminanceNoise = 0
            routed.effects.detail.luminanceDetail = DetailAdjustments.neutral.luminanceDetail
            routed.effects.detail.luminanceContrast = DetailAdjustments.neutral.luminanceContrast
        }
        return routed
    }
}
