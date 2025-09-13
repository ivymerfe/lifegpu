module viewer;

import constants;

struct SceneConstants
{
    float x;
    float y;
    float scale;
    float aspect_ratio;
}

[[vk::push_constant]]
SceneConstants scene;

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

float fractalNoise(float2 pos, int octaves, float persistence)
{
    float total = 0.0;
    float frequency = 1.0;
    float amplitude = 1.0;
    float maxValue = 0.0;

    for (int i = 0; i < octaves; ++i)
    {
        float n = frac(sin(dot(pos * frequency, float2(12.9898, 78.233))) * 43758.5453);
        total += n * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0;
    }
    return total / maxValue;
}

float noise(float2 pos)
{
    return fractalNoise(pos, 5, 0.5);
}

[shader("pixel")]
float4 psMain(VertexOutput input) : SV_Target0
{
    float2 field_coord = input.field_pos * 1024.0;
    int2 cell = int2(field_coord);

    float n = noise(cell);

    if (n > 0.5)
        return float4(0.1, 0.2, 0.8, 1);
    else
        return float4(0.9, 0.9, 0.9, 1);
}
