#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    packed_float3 position;
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

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             uint instanceID [[instance_id]],
                             constant VertexIn *vertices [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             constant InstanceData *instances [[buffer(2)]]) {
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
    
    VertexOut out;
    out.position = float4(rotated, in.position.z, 1.0);
    out.color = float4(in.color, 1.0);
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

// -----------------------------------------------------------------
// Text rendering (glyph atlas quads) — matches Text_Vertex in font_atlas.jai
// -----------------------------------------------------------------

struct TextVertexIn {
    packed_float2 position; // already in NDC, computed on the CPU in draw_text
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
    return float4(1.0, 1.0, 1.0, alpha); // white text, tint later via a color uniform if needed
}