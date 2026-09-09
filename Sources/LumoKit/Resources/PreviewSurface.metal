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
    float2 ndc = float2(
        pixelPosition.x / uniforms.viewportSize.x * 2.0 - 1.0,
        pixelPosition.y / uniforms.viewportSize.y * 2.0 - 1.0
    );
    output.position = float4(ndc, 0.0, 1.0);
    output.texcoord = vertices[vertexID].texcoord;
    return output;
}

fragment float4 preview_quad_fragment(
    PreviewQuadOutput input [[stage_in]],
    texture2d<float> image [[texture(0)]],
    sampler imageSampler [[sampler(0)]]
) {
    return image.sample(imageSampler, input.texcoord);
}
