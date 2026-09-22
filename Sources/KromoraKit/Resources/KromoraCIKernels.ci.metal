// KromoraCIKernels.ci.metal
//
// The nine Core Image kernels behind RenderPipeline, LocalMaskRenderer, and
// ToneCurveFilterCache, written for the Metal CI-kernel language mode.
//
// This is a mechanical port of the retired Core Image Kernel Language sources: same function
// names, same parameter lists (a `destination` parameter is appended last where the CIKL source
// called `destCoord()`; Core Image binds samplers, color samples, and the destination
// implicitly, so the Swift `apply(extent:arguments:)` call sites are unchanged), same constants,
// same operation order. Pixel parity against the CIKL originals is locked by
// MetalKernelParityTests; see that suite's header for the one documented exception (grain).
//
// Build (also wired as scripts/build-metal-libraries.sh so CI and clean checkouts agree):
//   xcrun metal -fcikernel -mmacosx-version-min=14.0 \
//       Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal \
//       -o Sources/KromoraKit/Resources/KromoraCIKernels.ci.metallib
//
// The `-mmacosx-version-min=14.0` flag matches Package.swift's deployment target so the
// resulting library loads on every supported macOS release, not just the building SDK.

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
namespace coreimage {

// MARK: - Effects (RenderPipeline)

// Midtone bell mask for the Clarity stage. Pointwise: no destination coordinate needed.
float4 effectsMidtoneMask(sample_t pixel, float4 controls) {
    if (pixel.a <= 0.00001) { return float4(0.0); }
    float3 rgb = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
    float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    // A smooth bell centred on middle gray, zero at both endpoints.
    float weight = clamp(4.0 * luminance * (1.0 - luminance), 0.0, 1.0);
    float alpha = weight * clamp(controls.x, 0.0, 1.0);
    return float4(0.0, 0.0, 0.0, alpha);
}

// Post-LUT vignette. The mask is defined in the complete output frame, so the destination
// coordinate (not a sampler coordinate) keeps tiled GPU evaluation seam-free.
float4 effectsVignette(
    sample_t pixel,
    float4 geometry,
    float4 shape,
    float4 highlightControls,
    destination dest
) {
    if (pixel.a <= 0.00001) { return pixel; }

    // Normalize independently by half-width/half-height: crop aspect ratio is part of the
    // geometry, while the vignette values remain resolution independent.
    float2 coordinate = dest.coord();
    float2 normalized = (coordinate - geometry.xy) / max(geometry.zw, float2(0.00001));
    float roundness = clamp(shape.y, -1.0, 1.0);
    // p=4 is squarer and p=2 is circular. Positive Roundness therefore rounds the corners.
    float exponent = 3.0 - roundness;
    float radius = pow(pow(abs(normalized.x), exponent) +
                        pow(abs(normalized.y), exponent), 1.0 / exponent);

    float midpoint = clamp(shape.x, 0.0, 1.0);
    float feather = clamp(shape.z, 0.0, 1.0);
    float transition = max(0.015, 0.08 + feather * 0.42);
    float edge = smoothstep(max(0.0, midpoint - transition),
                            min(1.5, midpoint + transition), radius);

    float3 straight = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
    float luminance = dot(straight, float3(0.2126, 0.7152, 0.0722));
    float highlightWeight = smoothstep(0.55, 1.0, luminance);
    float preservation = 1.0 - clamp(highlightControls.x, 0.0, 1.0) * highlightWeight;
    float signedAmount = clamp(shape.w, -1.0, 1.0);
    float multiplier = 1.0 - signedAmount * edge * preservation;
    return float4(pixel.rgb * multiplier, pixel.a);
}

// Deterministic, resolution-aware post-LUT grain. The noise field is defined in the complete
// output frame (destination coordinate), for the same tiling reason as the vignette.
//
// NOTE on bit stability: the value-noise hash below evaluates `sin` at large arguments, where
// single-precision range reduction is implementation-defined. The CIKL compiler and the Metal
// compiler therefore produce different (but equally valid) grain patterns from identical
// sources. Amplitude, frequency response, roughness character, seed sensitivity, and
// determinism are preserved and locked by tests; the exact per-pixel pattern is not.
float grainHash(float2 point, float seedHigh, float seedLow) {
    // Each seed component is a UInt16 supplied as a Float, so both components retain all
    // their bits exactly. Keep them as separate phase offsets: recombining them into a single
    // value near 2^32 would recreate the Float mantissa collision this kernel is avoiding.
    float highPhase = seedHigh * 0.0000152587890625;
    float lowPhase = seedLow * 0.0000152587890625;
    float2 seedOffset = float2(
        highPhase * 17.13 + lowPhase * 53.17,
        highPhase * 31.71 + lowPhase * 97.23
    );
    return fract(sin(dot(point + seedOffset,
                         float2(127.1, 311.7))) * 43758.5453);
}

float grainValueNoise(float2 point, float seedHigh, float seedLow) {
    float2 cell = floor(point);
    float2 local = fract(point);
    local = local * local * (3.0 - 2.0 * local);
    float lowerLeft = grainHash(cell, seedHigh, seedLow);
    float lowerRight = grainHash(cell + float2(1.0, 0.0), seedHigh, seedLow);
    float upperLeft = grainHash(cell + float2(0.0, 1.0), seedHigh, seedLow);
    float upperRight = grainHash(cell + float2(1.0, 1.0), seedHigh, seedLow);
    float lower = mix(lowerLeft, lowerRight, local.x);
    float upper = mix(upperLeft, upperRight, local.x);
    return mix(lower, upper, local.y);
}

float4 effectsGrain(
    sample_t pixel,
    float4 geometry,
    float4 controls,
    float seedHigh,
    float seedLow,
    destination dest
) {
    if (pixel.a <= 0.00001) { return pixel; }

    float2 coordinate = dest.coord();
    float2 normalized = (coordinate - geometry.xy) / geometry.z;
    float frequency = max(1.0, controls.x);
    float roughness = clamp(controls.y, 0.0, 1.0);
    float amount = clamp(controls.z, 0.0, 1.0);
    float2 grainCoordinate = normalized * frequency;

    // A broad octave creates clumps; blending in finer octaves makes Roughness visibly change
    // the grain's character. Pairing noise fields keeps the result closer to a bell-shaped
    // photographic distribution than a flat, independently random digital field.
    float broad = grainValueNoise(grainCoordinate * 0.45, seedHigh, seedLow + 1.0);
    float medium = grainValueNoise(grainCoordinate, seedHigh, seedLow + 7.0);
    float fine = grainValueNoise(grainCoordinate * 2.4, seedHigh, seedLow + 19.0);
    float paired = grainValueNoise(grainCoordinate * 1.35, seedHigh, seedLow + 43.0);
    float shaped = mix(broad, fine, roughness);
    shaped = mix(shaped, medium, 0.35);
    shaped = (shaped * 0.72 + paired * 0.28 - 0.5) * 2.0;

    float3 straight = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
    float luminance = dot(straight, float3(0.2126, 0.7152, 0.0722));
    // Grain is more visible in shadows and is predominantly luminance, with restrained chroma
    // variation so it reads as emulsion texture instead of RGB channel noise.
    float response = 0.58 + 0.42 * (1.0 - luminance);
    float amplitude = 0.055 * amount * response;
    float chroma = (fine - 0.5) * 0.12 * amount * response;
    float3 offset = float3(shaped * amplitude) + float3(chroma, -chroma * 0.55, chroma * 0.35);
    float3 altered = clamp(straight + offset, 0.0, 1.0);
    return float4(altered * pixel.a, pixel.a);
}

// MARK: - Eight-channel HSL mixer (RenderPipeline)

// Channel weights are raised cosine windows around the fixed Lightroom-style centers
// (R/O/Y/G/A/B/P/M). A 45-degree support radius gives adjacent channels a smooth overlap,
// while the circular distance makes the red window continuous across hue 0/1.
float wrappedHue(float value) {
    return value - floor(value);
}

float circularDistance(float hue, float center) {
    float distance = abs(hue - center);
    return min(distance, 1.0 - distance);
}

float hueWeight(float hue, float center) {
    // Raised cosine: both the value and its first derivative reach zero at the edge.
    float radius = 0.125;
    float distance = circularDistance(hue, center);
    if (distance >= radius) { return 0.0; }
    return 0.5 + 0.5 * cos(3.141592653589793 * distance / radius);
}

float hueToRGB(float p, float q, float t) {
    float wrapped = wrappedHue(t);
    if (wrapped < 1.0 / 6.0) { return p + (q - p) * 6.0 * wrapped; }
    if (wrapped < 1.0 / 2.0) { return q; }
    if (wrapped < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - wrapped) * 6.0; }
    return p;
}

float3 hslToRGB(float hue, float saturation, float luminance) {
    if (saturation <= 0.00001) {
        return float3(luminance, luminance, luminance);
    }
    float q = luminance < 0.5
        ? luminance * (1.0 + saturation)
        : luminance + saturation - luminance * saturation;
    float p = 2.0 * luminance - q;
    return float3(
        hueToRGB(p, q, hue + 1.0 / 3.0),
        hueToRGB(p, q, hue),
        hueToRGB(p, q, hue - 1.0 / 3.0)
    );
}

float4 hslMixer(
    sample_t pixel,
    float4 red,
    float4 orange,
    float4 yellow,
    float4 green,
    float4 aqua,
    float4 blue,
    float4 purple,
    float4 magenta
) {
    // Core Image kernel samples are premultiplied. HSL must see the unpremultiplied colour,
    // then the result is premultiplied again so transparent pixels retain both alpha and the
    // compositing contract of the input image.
    if (pixel.a <= 0.00001) { return pixel; }
    float3 rgb = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
    float maximum = max(max(rgb.r, rgb.g), rgb.b);
    float minimum = min(min(rgb.r, rgb.g), rgb.b);
    float delta = maximum - minimum;

    // Neutrals have no hue neighborhood. Returning the original sample also avoids assigning
    // gray pixels an arbitrary red hue when only one channel is adjusted.
    if (delta <= 0.00001) { return pixel; }

    float luminance = 0.5 * (maximum + minimum);
    float saturation = delta / (1.0 - abs(2.0 * luminance - 1.0));
    float hue;
    if (maximum == rgb.r) {
        hue = (rgb.g - rgb.b) / delta;
        if (hue < 0.0) { hue += 6.0; }
        hue /= 6.0;
    } else if (maximum == rgb.g) {
        hue = ((rgb.b - rgb.r) / delta + 2.0) / 6.0;
    } else {
        hue = ((rgb.r - rgb.g) / delta + 4.0) / 6.0;
    }
    hue = wrappedHue(hue);

    float redWeight = hueWeight(hue, 0.0);
    float orangeWeight = hueWeight(hue, 1.0 / 12.0);
    float yellowWeight = hueWeight(hue, 1.0 / 6.0);
    float greenWeight = hueWeight(hue, 1.0 / 3.0);
    float aquaWeight = hueWeight(hue, 1.0 / 2.0);
    float blueWeight = hueWeight(hue, 2.0 / 3.0);
    float purpleWeight = hueWeight(hue, 3.0 / 4.0);
    float magentaWeight = hueWeight(hue, 5.0 / 6.0);

    float hueDelta = redWeight * red.x + orangeWeight * orange.x
        + yellowWeight * yellow.x + greenWeight * green.x
        + aquaWeight * aqua.x + blueWeight * blue.x
        + purpleWeight * purple.x + magentaWeight * magenta.x;
    float saturationDelta = redWeight * red.y + orangeWeight * orange.y
        + yellowWeight * yellow.y + greenWeight * green.y
        + aquaWeight * aqua.y + blueWeight * blue.y
        + purpleWeight * purple.y + magentaWeight * magenta.y;
    float luminanceDelta = redWeight * red.z + orangeWeight * orange.z
        + yellowWeight * yellow.z + greenWeight * green.z
        + aquaWeight * aqua.z + blueWeight * blue.z
        + purpleWeight * purple.z + magentaWeight * magenta.z;

    return float4(
        hslToRGB(
            wrappedHue(hue + hueDelta),
            clamp(saturation + saturationDelta, 0.0, 1.0),
            clamp(luminance + 0.5 * luminanceDelta, 0.0, 1.0)
        ) * pixel.a,
        pixel.a
    );
}

// MARK: - Three-way color grading (RenderPipeline)

float wrappedGradingHue(float value) {
    return value - floor(value);
}

float gradingHueToRGB(float p, float q, float t) {
    float wrapped = wrappedGradingHue(t);
    if (wrapped < 1.0 / 6.0) { return p + (q - p) * 6.0 * wrapped; }
    if (wrapped < 1.0 / 2.0) { return q; }
    if (wrapped < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - wrapped) * 6.0; }
    return p;
}

float3 gradingColor(float hue, float luminance) {
    // Full-saturation HSL at the source luminance is the wheel's target color. The caller
    // controls how far toward it to move with the wheel saturation.
    float q = luminance < 0.5
        ? luminance * 2.0
        : luminance + 1.0 - luminance;
    float p = 2.0 * luminance - q;
    return float3(
        gradingHueToRGB(p, q, hue + 1.0 / 3.0),
        gradingHueToRGB(p, q, hue),
        gradingHueToRGB(p, q, hue - 1.0 / 3.0)
    );
}

float gradingSmoothStep(float edge0, float edge1, float value) {
    float denominator = max(edge1 - edge0, 0.00001);
    float t = clamp((value - edge0) / denominator, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

float4 colorGrading(
    sample_t pixel,
    float4 shadows,
    float4 midtones,
    float4 highlights,
    float4 controls
) {
    if (pixel.a <= 0.00001) { return pixel; }
    float3 rgb = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
    float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float shiftedLuminance = clamp(luminance + controls.y * 0.25, 0.0, 1.0);
    float blending = clamp(controls.x, 0.0, 1.0);

    // At blending 0 these transitions meet. At blending 1 they overlap by 0.16 of the
    // normalized luminance range. The normalized weights always sum to one.
    float shadowEdge = 0.42 + 0.16 * blending;
    float highlightEdge = 0.58 - 0.16 * blending;
    float shadowWeight = 1.0 - gradingSmoothStep(0.0, shadowEdge, shiftedLuminance);
    float highlightWeight = gradingSmoothStep(highlightEdge, 1.0, shiftedLuminance);
    float midtoneWeight = gradingSmoothStep(0.0, shadowEdge, shiftedLuminance)
        * (1.0 - gradingSmoothStep(highlightEdge, 1.0, shiftedLuminance));
    float weightTotal = max(shadowWeight + midtoneWeight + highlightWeight, 0.00001);
    shadowWeight /= weightTotal;
    midtoneWeight /= weightTotal;
    highlightWeight /= weightTotal;

    float shadowAmount = shadowWeight * clamp(shadows.y, 0.0, 1.0);
    float midtoneAmount = midtoneWeight * clamp(midtones.y, 0.0, 1.0);
    float highlightAmount = highlightWeight * clamp(highlights.y, 0.0, 1.0);
    float amountTotal = shadowAmount + midtoneAmount + highlightAmount;
    if (amountTotal <= 0.00001) { return pixel; }

    float3 tint = (
        shadowAmount * gradingColor(shadows.x, luminance)
        + midtoneAmount * gradingColor(midtones.x, luminance)
        + highlightAmount * gradingColor(highlights.x, luminance)
    ) / amountTotal;
    float3 graded = mix(rgb, tint, clamp(amountTotal, 0.0, 1.0));
    return float4(clamp(graded, 0.0, 1.0) * pixel.a, pixel.a);
}

// MARK: - Local masks (LocalMaskRenderer)

float4 localAnalyticMask(
    sampler image,
    float4 geometry,
    float4 firstPoint,
    float4 secondPoint,
    float4 transform,
    float4 radial,
    float4 controls
) {
    float2 coordinate = samplerCoord(image);
    float2 normalized = (coordinate - geometry.xy) / max(geometry.zw, float2(0.00001));
    normalized.y = 1.0 - normalized.y;

    // Transform around the source centre. Translation is normalized source-space movement.
    float2 shifted = normalized - float2(0.5);
    float cosine = cos(-transform.z);
    float sine = sin(-transform.z);
    shifted = float2(shifted.x * cosine - shifted.y * sine,
                   shifted.x * sine + shifted.y * cosine);
    shifted /= max(transform.xy, float2(0.00001));
    normalized = shifted + float2(0.5) - transform.wz;

    float alpha;
    if (controls.x < 0.5) {
        float2 direction = secondPoint.xy - firstPoint.xy;
        float denominator = max(dot(direction, direction), 0.0000001);
        float projection = dot(normalized - firstPoint.xy, direction) / denominator;
        // This is the GPU form of LinearGradientMaskMath.smoothstep(0, 1, projection).
        // The persisted endpoints encode the falloff width, so no resolution-dependent
        // feather/raster value is introduced here.
        alpha = smoothstep(0.0, 1.0, projection);
        alpha *= controls.y;
    } else {
        float2 delta = normalized - firstPoint.xy;
        // Rotation is defined in source-pixel space. Scaling normalized x/y by the
        // requested extent before rotating keeps an ellipse aligned on non-square sources
        // at interactive, preview, and export resolutions.
        delta *= geometry.zw;
        float radialCosine = cos(radial.z);
        float radialSine = sin(radial.z);
        delta = float2(delta.x * radialCosine + delta.y * radialSine,
                     -delta.x * radialSine + delta.y * radialCosine);
        float distance = length(delta / max(radial.xy, float2(0.00001)));
        float inner = max(0.0, 1.0 - radial.w);
        if (distance <= inner) {
            alpha = 1.0;
        } else if (distance >= 1.0) {
            alpha = 0.0;
        } else {
            alpha = 1.0 - smoothstep(inner, 1.0, distance);
        }
        if (controls.z < 0.5) { alpha = 1.0 - alpha; }
        alpha *= controls.y;
    }
    return float4(0.0, 0.0, 0.0, clamp(alpha, 0.0, 1.0));
}

float4 localInvertMask(sampler image) {
    float4 pixel = sample(image, samplerCoord(image));
    return float4(0.0, 0.0, 0.0, 1.0 - clamp(pixel.a, 0.0, 1.0));
}

float4 localCombineMask(sampler current, sampler next, float4 controls) {
    float a = clamp(sample(current, samplerCoord(current)).a, 0.0, 1.0);
    float b = clamp(sample(next, samplerCoord(next)).a, 0.0, 1.0);
    float result;
    if (controls.x < 0.5) {
        result = b;                 // replace
    } else if (controls.x < 1.5) {
        result = max(a, b);         // add
    } else if (controls.x < 2.5) {
        result = a * (1.0 - b);     // subtract
    } else {
        result = min(a, b);         // intersect
    }
    return float4(0.0, 0.0, 0.0, clamp(result, 0.0, 1.0));
}

// MARK: - Master RGB tone curve (ToneCurveFilterCache)

float4 applyToneCurve(sampler image, sampler curve) {
    float4 pixel = sample(image, samplerCoord(image));
    if (pixel.a <= 0.00001) { return pixel; }

    // +0.5 lands on the texel center (texel i spans [i, i+1)); without it every lookup
    // interpolates between the wrong neighbouring pair, biasing output by up to half a texel.
    float red = sample(curve, float2(clamp(pixel.r / pixel.a, 0.0, 1.0) * 255.0 + 0.5, 0.5)).r;
    float green = sample(curve, float2(clamp(pixel.g / pixel.a, 0.0, 1.0) * 255.0 + 0.5, 0.5)).r;
    float blue = sample(curve, float2(clamp(pixel.b / pixel.a, 0.0, 1.0) * 255.0 + 0.5, 0.5)).r;
    return float4(float3(red, green, blue) * pixel.a, pixel.a);
}

} // namespace coreimage
} // extern "C"
