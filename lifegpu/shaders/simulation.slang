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

uint2 readField(int2 pos)
{
    pos.x = pos.x < 0 ? pos.x + FIELD_WIDTH : (pos.x >= FIELD_WIDTH ? pos.x - FIELD_WIDTH : pos.x);
    pos.y = pos.y < 0 ? pos.y + FIELD_HEIGHT : (pos.y >= FIELD_HEIGHT ? pos.y - FIELD_HEIGHT : pos.y);
    return fieldTextures[consts.readTexture].Load(pos);
}

uint readCell(inout uint2 chunk[3][3], uint x, uint y)
{
    uint idx = (y & 7) * 8 + (x & 7);
    uint arr_idx = idx / 32;
    uint bit_idx = idx % 32;
    return (chunk[y >> 3][x >> 3][arr_idx] >> bit_idx) & 1;
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

        fieldTextures[consts.writeTexture][threadId.xy] = uint2(patternA, patternB);
    }
    else
    {
        uint2 neighbors[3][3];
        for (int y = 0; y < 3; y++)
        {
            for (int x = 0; x < 3; x++)
            {
                int2 pos = int2(threadId.xy) + int2(x - 1, y - 1);
                neighbors[y][x] = readField(pos);
            }
        }
        uint2 result = uint2(0, 0);
        for (uint y = 8; y < 16; y++)
        {
            for (uint x = 8; x < 16; x++)
            {
                uint neighbor_cnt = 0;
                neighbor_cnt += readCell(neighbors, x - 1, y - 1);
                neighbor_cnt += readCell(neighbors, x, y - 1);
                neighbor_cnt += readCell(neighbors, x + 1, y - 1);
                neighbor_cnt += readCell(neighbors, x - 1, y);
                neighbor_cnt += readCell(neighbors, x + 1, y);
                neighbor_cnt += readCell(neighbors, x - 1, y + 1);
                neighbor_cnt += readCell(neighbors, x, y + 1);
                neighbor_cnt += readCell(neighbors, x + 1, y + 1);

                uint cell = readCell(neighbors, x, y);
                uint next_cell = ((cell & ((neighbor_cnt == 2) | (neighbor_cnt == 3))) | (~cell & (neighbor_cnt == 3))) & 1;
                uint idx = (y & 7) * 8 + (x & 7);
                uint arr_idx = idx / 32;
                uint bit_idx = idx % 32;
                result[arr_idx] |= (next_cell << bit_idx);
            }
        }
        fieldTextures[consts.writeTexture][threadId.xy] = result;
    }
}
