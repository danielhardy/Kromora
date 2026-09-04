#include <metal_stdlib>
using namespace metal;

struct MaskOverlayVertex {
    float2 position;
    float4 color;
};

struct MaskOverlayOutput {
    float4 position [[position]];
    float4 color;
};

vertex MaskOverlayOutput mask_overlay_vertex(
    const device MaskOverlayVertex *vertices [[buffer(0)]], uint vertexID [[vertex_id]]
) {
    MaskOverlayOutput output;
    float2 ndc = float2(vertices[vertexID].position.x * 2.0 - 1.0,
                        1.0 - vertices[vertexID].position.y * 2.0);
    output.position = float4(ndc, 0.0, 1.0);
    output.color = vertices[vertexID].color;
    return output;
}

fragment float4 mask_overlay_fragment(MaskOverlayOutput input [[stage_in]]) {
    return input.color;
}
