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
ComputeConstants consts;

RWTexture2D<uint2> fieldTextures[4];

uint64_t readField(int2 pos)
{
    pos.x = pos.x < 0 ? pos.x + FIELD_WIDTH : (pos.x >= FIELD_WIDTH ? pos.x - FIELD_WIDTH : pos.x);
    pos.y = pos.y < 0 ? pos.y + FIELD_HEIGHT : (pos.y >= FIELD_HEIGHT ? pos.y - FIELD_HEIGHT : pos.y);
    uint2 val = fieldTextures[consts.readTexture].Load(pos);
    return (uint64_t)val.x << 32 | val.y;
}

uint64_t readCell(inout uint64_t[3][3] chunk, uint64_t x, uint64_t y)
{
    return (chunk[y >> 3][x >> 3] >> ((y & 7) << 3 | (x & 7))) & 1;
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, WORKGROUP_SIZE, 1)]
void compMain(uint3 threadId: SV_DispatchThreadID)
{
    if (consts.randomize)
    {
        int x = int(threadId.x + consts.tickIndex * 4);
        int y = int(threadId.y);

        uint rand = ((x * 73851093) ^ (y * 19349663) ^ (consts.tickIndex * 83412791)) & 0xFFFFFFFF;

        uint shiftA = consts.tickIndex % 32;
        uint shiftB = (consts.tickIndex * 3) % 32;
        uint patternA = (rand << shiftA) | (rand >> (32 - shiftA));
        uint patternB = (rand << shiftB) | (rand >> (32 - shiftB));
        uint2 value = uint2(patternA, patternB);

        fieldTextures[consts.writeTexture][int2(threadId.xy)] = value;
    }
    else
    {
        uint64_t neighbors[3][3];
        for (int y = 0; y < 3; y++)
        {
            for (int x = 0; x < 3; x++)
            {
                int2 pos = int2(threadId.xy) + int2(x - 1, y - 1);
                neighbors[y][x] = readField(pos);
            }
        }
        uint64_t result = 0;
        for (uint64_t y = 8; y < 16; y++)
        {
            for (uint64_t x = 8; x < 16; x++)
            {
                uint64_t neighbor_cnt = 0;
                neighbor_cnt += readCell(neighbors, x - 1, y - 1);
                neighbor_cnt += readCell(neighbors, x, y - 1);
                neighbor_cnt += readCell(neighbors, x + 1, y - 1);
                neighbor_cnt += readCell(neighbors, x - 1, y);
                neighbor_cnt += readCell(neighbors, x + 1, y);
                neighbor_cnt += readCell(neighbors, x - 1, y + 1);
                neighbor_cnt += readCell(neighbors, x, y + 1);
                neighbor_cnt += readCell(neighbors, x + 1, y + 1);

                uint64_t cell = readCell(neighbors, x, y);
                uint64_t nextCell = ((cell & ((neighbor_cnt == 2) | (neighbor_cnt == 3))) | (~cell & (neighbor_cnt == 3))) & 1;
                result |= (nextCell << (((y & 7) << 3) | (x & 7)));
            }
        }
        uint resultA = uint(result >> 32);
        uint resultB = uint(result & 0xFFFFFFFF);
        fieldTextures[consts.writeTexture][int2(threadId.xy)] = uint2(resultA, resultB);
    }
}
