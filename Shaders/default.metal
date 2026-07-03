#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    packed_float3 position; // pixel-space
    packed_float3 color;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float time;
};

struct InstanceData {
    float2 offset; 
    float2 rotation_speed;
};

struct ScreenUniforms {
    float2 screen_size;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             uint instanceID [[instance_id]],
                             constant VertexIn *vertices [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             constant InstanceData *instances [[buffer(2)]],
                             constant ScreenUniforms &screen [[buffer(3)]]) {
    VertexIn in = vertices[vertexID];
    InstanceData inst = instances[instanceID];

    float angle = uniforms.time * inst.rotation_speed.x;
    float Ct = cos(angle);
    float St = sin(angle);

    float2 pos = float2(in.position.x, in.position.y);
    float2 rotated;
    rotated.x = pos.x * Ct - pos.y * St;
    rotated.y = pos.x * St + pos.y * Ct;
    
    rotated += inst.offset;
    
    // Pixel space (origin = screen center) -> NDC
    float2 ndc = rotated / (screen.screen_size * 0.5);
    ndc.y = -ndc.y;
    
    VertexOut out;
    // Fix: Use the ndc coordinates for the final position
    out.position = float4(ndc, in.position.z, 1.0);
    out.color = float4(in.color, 1.0);
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

// -----------------------------------------------------------------
// Text rendering
// -----------------------------------------------------------------

struct TextVertexIn {
    packed_float2 position; // already in NDC
    packed_float2 uv;
};

struct TextVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex TextVertexOut vertex_text(uint vertexID [[vertex_id]],
                                  constant TextVertexIn *vertices [[buffer(0)]]) {
    TextVertexIn in = vertices[vertexID];

    TextVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 fragment_text(TextVertexOut in [[stage_in]],
                               texture2d<float> atlas [[texture(0)]],
                               sampler atlas_sampler [[sampler(0)]]) {
    float alpha = atlas.sample(atlas_sampler, in.uv).r;
    return float4(1.0, 1.0, 1.0, alpha); 
}

// -----------------------------------------------------------------
// Quad rendering
// -----------------------------------------------------------------

struct QuadVertexIn {
    packed_float2 position; // pixel space
    packed_float2 uv;
    packed_float4 color;
};

struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex QuadVertexOut vertex_quad(uint vid [[vertex_id]],
                                  constant QuadVertexIn *vertices [[buffer(0)]],
                                  constant ScreenUniforms &screen [[buffer(1)]]) {
    QuadVertexIn in = vertices[vid];

    float2 ndc;
    ndc.x = (in.position.x / screen.screen_size.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (in.position.y / screen.screen_size.y) * 2.0;

    QuadVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

fragment float4 fragment_quad(QuadVertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler tex_sampler [[sampler(0)]]) {
    float4 tex_color = tex.sample(tex_sampler, in.uv);
    return tex_color * in.color;
}