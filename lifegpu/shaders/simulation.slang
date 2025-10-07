module simulation;

import constants;

struct ComputeConstants
{
    uint readTexture;
    uint writeTexture;
    float currentTime;
    bool randomize;
}

[[vk::push_constant]]
ComputeConstants scene;

RWTexture2D<uint2> fieldTextures[4];

[shader("compute")]
[numthreads(FIELD_WIDTH, FIELD_HEIGHT, 1)]
void compMain(uint3 threadId: SV_DispatchThreadID)
{
    if (scene.randomize)
    {
        uint seed = threadId.x * 73856093u ^ threadId.y * 19349663u ^ threadId.z * 83492791u ^ asuint(scene.currentTime);
        uint2 noise = uint2(seed, seed >> 16);

        fieldTextures[scene.writeTexture][int2(threadId.xy)] = noise;
    }
}
