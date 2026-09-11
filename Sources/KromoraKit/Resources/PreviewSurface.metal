#include <metal_stdlib>
using namespace metal;

struct PreviewQuadVertex {
    float2 position;
    float2 texcoord;
};

struct PreviewQuadUniforms {
    float2 transformOrigin;
    float2 imageOrigin;
    float2 imageSize;
    float scale;
    float2 viewportSize;
};

struct PreviewQuadOutput {
    float4 position [[position]];
    float2 texcoord;
};

vertex PreviewQuadOutput preview_quad_vertex(
    const device PreviewQuadVertex *vertices [[buffer(0)]],
    constant PreviewQuadUniforms &uniforms [[buffer(1)]], uint vertexID [[vertex_id]]
) {
    PreviewQuadOutput output;
    float2 pixelPosition = uniforms.transformOrigin
        + (uniforms.imageOrigin + vertices[vertexID].position * uniforms.imageSize)
            * uniforms.scale;
    // CanvasNavigation and MaskOverlay are y-down (pixel y=0 is the top of the view). Metal
    // clip space is y-up, so the top of the view is NDC y=+1 — the same mapping as
    // MaskOverlay.metal. Mapping y=0 to NDC -1 inverts the presented frame on screen while
    // still looking upright through CIImage(mtlTexture:) in offscreen tests.
    float2 ndc = float2(
        pixelPosition.x / uniforms.viewportSize.x * 2.0 - 1.0,
        1.0 - pixelPosition.y / uniforms.viewportSize.y * 2.0
    );
    output.position = float4(ndc, 0.0, 1.0);
    // Core Image's completed texture is authored in a y-up image space (row 0 is the visual
    // bottom). Invert only the sampling axis so the top of the view samples the visual top.
    output.texcoord = float2(vertices[vertexID].texcoord.x,
                             1.0 - vertices[vertexID].texcoord.y);
    return output;
}

fragment float4 preview_quad_fragment(
    PreviewQuadOutput input [[stage_in]],
    texture2d<float> image [[texture(0)]],
    sampler imageSampler [[sampler(0)]]
) {
    return image.sample(imageSampler, input.texcoord);
}
