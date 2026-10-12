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

    // Three slowly drifting interference curves: an optical suggestion, with no scan line,
    // timeline, fabricated region, or connection to inference internals. The photo stays intact.
    float t = u.timing.w > 0.5 ? 0.0 : u.timing.x;
    float2 q = (local - 0.5) * float2(u.display.x * u.imageRect.z / u.imageRect.w, 1);
    float field = q.y + 0.16 * sin(q.x * 3.1 + t * 0.19)
        + 0.09 * sin(q.x * 5.7 - t * 0.13);
    float curve = sin(field * 9.0 + t * 0.27);
    float ribbon = exp(-curve * curve * 180.0);
    float halo = exp(-curve * curve * 14.0);
    float edgeFade = smoothstep(0.0, 0.06, min(min(local.x, 1.0-local.x),
                                                         min(local.y, 1.0-local.y)));
    float breathe = 0.8 + 0.2 * sin(t * 0.43);
    float3 pearl = mix(float3(0.58, 0.81, 0.91), float3(1.0, 0.87, 0.65),
                       0.5 + 0.5 * sin(field * 4.0 + t * 0.11));
    float reveal = u.timing.z;
    float waiting = u.timing.y * (1.0 - smoothstep(0.0, 0.45, reveal));
    float alpha = (ribbon * 0.11 + halo * 0.025) * edgeFade * breathe * waiting;
    float3 color = pearl * alpha;

    if (u.display.z > 0.5) {
        float coverage = mask.sample(linearSampler, source).r;
        float2 texel = 1.0 / float2(mask.get_width(), mask.get_height());
        float dx = mask.sample(linearSampler, source + float2(texel.x, 0)).r
                 - mask.sample(linearSampler, source - float2(texel.x, 0)).r;
        float dy = mask.sample(linearSampler, source + float2(0, texel.y)).r
                 - mask.sample(linearSampler, source - float2(0, texel.y)).r;
        float boundary = saturate(length(float2(dx, dy)) * 2.8);
        // The same curves soften into the true coverage. A short traveling glint catches the
        // returned boundary before the entire treatment recedes into the unchanged photograph.
        float arrive = smoothstep(0.0, 0.16, reveal);
        float depart = 1.0 - smoothstep(0.52, 1.0, reveal);
        float glint = exp(-pow((local.x * 0.65 + local.y * 0.35 - reveal * 1.5 + 0.2) * 8.0, 2.0));
        float maskAlpha = (coverage * 0.13 + boundary * (0.18 + 0.33 * glint)) * arrive * depart;
        if (u.timing.w > 0.5) maskAlpha = coverage * 0.18;
        color += mix(pearl, float3(0.84, 0.95, 1.0), 0.6) * maskAlpha;
        alpha += maskAlpha;
    }
    return float4(color, alpha) * u.display.y; // premultiplied, transparent outside the photograph
}
