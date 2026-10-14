#include <metal_stdlib>
using namespace metal;

struct DiscoveryUniforms {
    float4 imageRect;  // normalized viewport origin and size
    float4 cropRect;
    float4 sourceX;
    float4 sourceY;
    float4 sourceW;
    float4 timing;     // time, waiting exposure, reveal progress, reduced motion
    float4 display;    // viewport aspect, total opacity, has mask, reserved
};

struct DiscoveryVertex {
    float4 position [[position]];
    float2 uv;
};

vertex DiscoveryVertex mask_discovery_vertex(uint index [[vertex_id]]) {
    float2 p = float2((index << 1) & 2, index & 2);
    return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float value_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), f.x), f.y);
}

static float clumped_noise(float2 p) {
    float sum = 0.0, amplitude = 0.5;
    for (int octave = 0; octave < 3; ++octave) {
        sum += amplitude * value_noise(p);
        p = p * 2.03 + 17.1;
        amplitude *= 0.5;
    }
    return sum / 0.875;
}

/// Light refracted through a shallow tray of developer: an iterated domain warp whose folds
/// concentrate into thin bright webs. Purely procedural; it carries no information.
static float tray_caustic(float2 uv, float t) {
    float2 p = uv * 6.28318 - 250.0;
    float2 i = p;
    float c = 1.0;
    for (int n = 0; n < 5; ++n) {
        float tt = t * (1.0 - 3.5 / float(n + 1));
        i = p + float2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
        c += 1.0 / length(float2(p.x / (sin(i.x + tt) / 0.005), p.y / (cos(i.y + tt) / 0.005)));
    }
    c /= 5.0;
    return pow(saturate(1.17 - pow(c, 1.4)), 8.0);
}

fragment float4 mask_discovery_fragment(
    DiscoveryVertex in [[stage_in]], constant DiscoveryUniforms &u [[buffer(0)]],
    texture2d<float> mask [[texture(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 local = (in.uv - u.imageRect.xy) / u.imageRect.zw;
    if (any(local < 0.0) || any(local > 1.0)) return 0.0;
    float2 output = u.cropRect.xy + local * u.cropRect.zw;
    float3 p = float3(output, 1);
    float w = dot(u.sourceW.xyz, p);
    if (abs(w) < 0.00001) return 0.0;
    float2 source = float2(dot(u.sourceX.xyz, p), dot(u.sourceY.xyz, p)) / w;
    if (any(source < 0.0) || any(source > 1.0)) return 0.0;

    // Darkroom: the photograph sits under a low amber safelight while the developer tray
    // shimmers. Nothing here measures or implies Apple's analysis; the light just waits.
    bool still = u.timing.w > 0.5;
    float t = still ? 0.0 : u.timing.x;
    float reveal = u.timing.z;
    float2 q = (local - 0.5) * float2(u.display.x * u.imageRect.z / u.imageRect.w, 1);
    float radius = length(local - 0.5);

    float safelight = u.timing.y * (1.0 - smoothstep(0.35, 0.95, reveal));
    float breathe = 0.85 + 0.15 * sin(t * 0.55);
    float edgeFade = 1.0;

    float3 amber = float3(1.0, 0.46, 0.14);
    float dimming = (0.07 + 0.20 * smoothstep(0.25, 0.75, radius)) * safelight;
    float wash = 0.06 * safelight * breathe;
    float caustic = still ? 0.0 : tray_caustic(q * 0.9, t * 0.35);
    float grainSeed = floor(t * 7.0);
    float grain = hash21(floor(local * float2(u.display.x, 1.0) * 480.0) + grainSeed * 1.7);
    float shimmer = (grain - 0.5) * 0.035 * safelight;

    // Premultiplied: black alpha dims, amber alpha warms, zero alpha adds light.
    float alpha = (dimming + wash) * edgeFade;
    float3 color = amber * wash * edgeFade;
    color += mix(amber, float3(1.0, 0.86, 0.62), 0.55) * (caustic * 0.15 * safelight * breathe) * edgeFade;
    color += shimmer * edgeFade;

    if (!still) {
        // Whole-frame development: the same silver grain that later nucleates on the returned
        // coverage drifts in slow, uniform waves across the entire photograph, so the wait
        // already reads as the reveal's vocabulary. It is a field, not a region: it never
        // favors any part of the image and carries no information about the analysis.
        float2 gp = local * float2(u.display.x, 1.0);
        float clump = clumped_noise(gp * 140.0 + float2(t * 0.05, 0.0));
        float wave = 0.5 + 0.5 * sin(t * 0.45 + clump * 6.28318);
        float developed = smoothstep(0.55, 0.9, wave) * (0.35 + 0.65 * clump);
        float fine = hash21(floor(gp * 520.0) + floor(t * 6.0) * 3.1);
        float sparkle = developed * smoothstep(0.7, 0.97, fine);
        float ambient = safelight;
        float3 silver = float3(0.84, 0.93, 1.0);
        float lift = (developed * 0.03 + sparkle * 0.2) * ambient;
        color += silver * lift;
        alpha += lift * 0.4;
    }

    if (u.display.z > 0.5) {
        float coverage = mask.sample(linearSampler, source).r;
        float2 texel = 1.0 / float2(mask.get_width(), mask.get_height());
        float dx = mask.sample(linearSampler, source + float2(texel.x, 0)).r
                 - mask.sample(linearSampler, source - float2(texel.x, 0)).r;
        float dy = mask.sample(linearSampler, source + float2(0, texel.y)).r
                 - mask.sample(linearSampler, source - float2(0, texel.y)).r;
        float boundary = saturate(length(float2(dx, dy)) * 2.8);

        if (still) {
            color += float3(0.84, 0.95, 1.0) * coverage * 0.18;
            alpha += coverage * 0.18;
        } else {
            // Latent image: fine silver grains nucleate where returned coverage is strongest,
            // sparkle as they bloom, then coalesce into a soft halation around the subject.
            float2 gp = local * float2(u.display.x, 1.0);
            float clump = clumped_noise(gp * 140.0);
            float threshold = (1.0 - coverage) * 0.7 + clump * 0.3;
            float developed = smoothstep(0.0, 0.05, reveal * 1.45 - threshold);
            developed *= smoothstep(0.04, 0.4, coverage);
            float fine = hash21(floor(gp * 520.0) + floor(reveal * 18.0) * 3.1);
            float sparkle = developed * smoothstep(0.55, 0.95, fine) * (1.0 - smoothstep(0.55, 0.9, reveal));
            float depart = 1.0 - smoothstep(0.82, 1.0, reveal);

            float3 silver = float3(0.84, 0.93, 1.0);
            float lift = (developed * 0.075 + sparkle * 0.42) * depart;
            color += silver * lift;
            alpha += lift * 0.4;

            // Halation: light blooms just outside the returned boundary.
            float blurred = coverage;
            for (int k = 0; k < 8; ++k) {
                float angle = float(k) * 0.785398;
                blurred += mask.sample(linearSampler, source + float2(cos(angle), sin(angle)) * texel * 7.0).r;
            }
            blurred /= 9.0;
            float halo = saturate(blurred * 2.2) * (1.0 - coverage) * smoothstep(0.3, 0.7, reveal) * depart;
            color += float3(1.0, 0.9, 0.74) * halo * 0.34;

            // Dodge and burn: surroundings recede slightly while the subject holds the light.
            float burn = (1.0 - coverage) * smoothstep(0.15, 0.6, reveal) * depart * 0.14;
            alpha += burn;

            // Fixer: a crisp pearl edge locks the image in just before the lights come up.
            float fix = boundary * smoothstep(0.52, 0.7, reveal) * (1.0 - smoothstep(0.76, 0.98, reveal));
            color += float3(1.0, 0.97, 0.9) * fix * 0.5;
            alpha += fix * 0.35;
        }
    }
    return float4(color, saturate(alpha)) * u.display.y; // premultiplied, transparent outside the photograph
}
