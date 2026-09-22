module constants;

public static const int FIELD_WIDTH = 2048;
public static const int FIELD_HEIGHT = 2048;
public static const float FIELD_RATIO = (float)FIELD_WIDTH / FIELD_HEIGHT;
public static const int NUM_FIELD_TEXTURES = 3;

public static const float4 ALIVE_COLOR = float4(0.9, 0.9, 0.9, 1);
public static const float4 DEAD_COLOR = float4(0, 0, 0, 1);
public static const float4 DYING_COLOR = float4(1.0, 0, 0, 1);
public static const float4 SPAWNING_COLOR = float4(0, 0.5, 1.0, 1);

public static const float SIM_SPEED = 8.0;

public static const int WORKGROUP_SIZE = 16;
