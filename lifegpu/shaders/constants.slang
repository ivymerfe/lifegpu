module constants;

public static const int FIELD_WIDTH = 512;
public static const int FIELD_HEIGHT = 512;
public static const float FIELD_RATIO = (float)FIELD_WIDTH / FIELD_HEIGHT;

public static const float4 ALIVE_COLOR = float4(0.9, 0.9, 0.9, 1);
public static const float4 DEAD_COLOR = float4(0, 0, 0, 1);
public static const float SIM_SPEED = 4.0;

public static const int WORKGROUP_SIZE = 32;
