module rendering;

import constants;

struct SceneConstants
{
    float x;
    float y;
    float scale;
    float aspect_ratio;
    uint textureIndex;
}

[[vk::push_constant]]
SceneConstants scene;

Texture2D<uint2> fieldTextures[3];

struct VertexOutput
{
    float4 pos : SV_Position;
    float2 field_pos : FIELD_POS;
}

static const float2 QUAD[6] = {
    float2(-.5, -.5),
    float2(+.5, -.5),
    float2(-.5, +.5),
    float2(-.5, +.5),
    float2(+.5, -.5),
    float2(+.5, +.5)
};

[shader("vertex")]
VertexOutput vsMain(uint vertexIndex: SV_VertexID)
{
    float2 quad_pos = QUAD[vertexIndex];
    VertexOutput out;
    out.field_pos = quad_pos + .5;
    out.pos.x = (quad_pos.x - scene.x) * FIELD_RATIO / scene.aspect_ratio * scene.scale;
    out.pos.y = (quad_pos.y - scene.y) * scene.scale;
    out.pos.z = 0;
    out.pos.w = 1;
    return out;
}

[shader("pixel")]
float4 psMain(VertexOutput in) : SV_Target0
{
    int2 cell = int2(in.field_pos * float2(FIELD_WIDTH, FIELD_HEIGHT) * 8);
    int2 tex = cell >> 3;
    int2 rel = cell & 7;
    uint2 val = fieldTextures[scene.textureIndex].Load(int3(tex, 0));
    uint chunk = val.x << 32 | val.y;
    uint state = (chunk >> (rel.x * rel.y)) & 1;

    if (state == 1)
        return float4(0.9, 0.05, 0.05, 1);
    else
        return float4(0.1, 0.4, 0.7, 1);
}
