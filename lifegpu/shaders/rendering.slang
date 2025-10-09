module rendering;

import constants;

struct SceneConstants
{
    float x;
    float y;
    float scale;
    float aspect_ratio;
    uint prevTexture;
    uint currTexture;
    float delta;
}

[[vk::push_constant]]
SceneConstants scene;

readonly RWTexture2D<uint2> fieldTextures[4];

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

uint64_t loadCell(uint textureIndex, int2 cell)
{
    int2 tex = cell >> 3;
    int2 rel = cell & 7;
    uint2 val = fieldTextures[textureIndex].Load(tex);
    uint64_t chunk = (uint64_t)val.x << 32 | val.y;
    return (chunk >> (rel.y << 3 | rel.x)) & 1;
}

[shader("pixel")]
float4 psMain(VertexOutput in) : SV_Target0
{
    int2 cell = int2(in.field_pos * float2(FIELD_WIDTH, FIELD_HEIGHT) * 8);
    uint64_t prev_state = loadCell(scene.prevTexture, cell);
    uint64_t curr_state = loadCell(scene.currTexture, cell);
    float4 prev_color = prev_state == 1 ? ALIVE_COLOR : DEAD_COLOR;
    float4 colors[2][2] = { { DEAD_COLOR, SPAWNING_COLOR }, { DYING_COLOR, ALIVE_COLOR } };
    float4 curr_color = colors[prev_state][curr_state];

    return lerp(prev_color, curr_color, scene.delta * SIM_SPEED);
}
