"""AXI-Lite register map for the PL renderer.

The hardware-facing map uses camera vectors instead of raw yaw/pitch. The
server accepts yaw/pitch from the UI and converts them into these registers.
All registers are 32-bit word-addressable MMIO offsets.
"""

REG_CONTROL = 0x00
REG_STATUS = 0x04
REG_FRAME_COUNT = 0x08
REG_ERROR_FLAGS = 0x0C

REG_OX = 0x10
REG_OY = 0x14
REG_OZ = 0x18

REG_FWD_X = 0x20
REG_FWD_Y = 0x24
REG_FWD_Z = 0x28
REG_RIGHT_X = 0x2C
REG_RIGHT_Y = 0x30
REG_RIGHT_Z = 0x34
REG_UP_X = 0x38
REG_UP_Y = 0x3C
REG_UP_Z = 0x40

REG_SUN_DX = 0x48
REG_SUN_DY = 0x4C
REG_SUN_DZ = 0x50

REG_HEIGHT_SCALE = 0x58
REG_COLOUR_MODE = 0x5C
REG_RENDER_MODE = 0x60
REG_MAX_DEPTH = 0x64
REG_STEP_SIZE = 0x68

CONTROL_ENABLE = 1 << 0
CONTROL_APPLY = 1 << 1
CONTROL_SOFT_RESET = 1 << 2

STATUS_ENABLED = 1 << 0
STATUS_FRAME_ACTIVE = 1 << 1
STATUS_UPDATE_PENDING = 1 << 2
STATUS_UPDATE_APPLIED = 1 << 3
STATUS_BACKPRESSURE = 1 << 4
STATUS_HEIGHTMAP_NOT_READY = 1 << 5

PARAM_REGISTERS = {
    "camera_x": REG_OX,
    "camera_y": REG_OY,
    "camera_z": REG_OZ,
    "ox": REG_OX,
    "oy": REG_OY,
    "oz": REG_OZ,
    "fwd_x": REG_FWD_X,
    "fwd_y": REG_FWD_Y,
    "fwd_z": REG_FWD_Z,
    "right_x": REG_RIGHT_X,
    "right_y": REG_RIGHT_Y,
    "right_z": REG_RIGHT_Z,
    "up_x": REG_UP_X,
    "up_y": REG_UP_Y,
    "up_z": REG_UP_Z,
    "sun_dx": REG_SUN_DX,
    "sun_dy": REG_SUN_DY,
    "sun_dz": REG_SUN_DZ,
    "height_scale": REG_HEIGHT_SCALE,
    "colour_mode": REG_COLOUR_MODE,
    "color_mode": REG_COLOUR_MODE,
    "render_mode": REG_RENDER_MODE,
    "max_depth": REG_MAX_DEPTH,
    "step_size": REG_STEP_SIZE,
}

READBACK_REGISTERS = {
    "control": REG_CONTROL,
    "status": REG_STATUS,
    "frame_count": REG_FRAME_COUNT,
    "error_flags": REG_ERROR_FLAGS,
    **PARAM_REGISTERS,
}

