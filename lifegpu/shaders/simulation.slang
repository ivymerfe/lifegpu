module simulation;

import constants;

struct ComputeConstants
{
    uint readTexture;
    uint writeTexture;
    uint tickIndex;
    bool randomize;
}

[[vk::push_constant]]
ComputeConstants scene;

RWTexture2D<uint2> fieldTextures[4];

[shader("compute")]
[numthreads(WORKGROUP_SIZE, WORKGROUP_SIZE, 1)]
void compMain(uint3 threadId: SV_DispatchThreadID)
{
    if (scene.randomize)
    {
        int x = int(threadId.x + scene.tickIndex * 4);
        int y = int(threadId.y);

        uint rand = ((x * 73851093) ^ (y * 19349663) ^ (scene.tickIndex * 83412791)) & 0xFFFFFFFF;

        uint shiftA = scene.tickIndex % 32;
        uint shiftB = (scene.tickIndex * 3) % 32;
        uint patternA = (rand << shiftA) | (rand >> (32 - shiftA));
        uint patternB = (rand << shiftB) | (rand >> (32 - shiftB));
        uint2 value = uint2(patternA, patternB);
        
        fieldTextures[scene.writeTexture][int2(threadId.xy)] = value;
    }
}
