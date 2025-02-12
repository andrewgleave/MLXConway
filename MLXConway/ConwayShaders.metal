#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]], device const Vertex *vertices [[buffer(0)]]) {
    Vertex in = vertices[vertexID];
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment half4 fragmentShader(VertexOut in [[stage_in]], texture2d<half> tex [[ texture(0) ]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    half gray = tex.sample(s, in.texCoord).r;
    return half4(gray, gray, gray, 1.0h);
}
