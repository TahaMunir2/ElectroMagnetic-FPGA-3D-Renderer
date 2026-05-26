# Hardware Team Change Request

## Goal

Make the `rendering_new_new/src/hdl` renderer compatible with the laptop UI and PYNQ PS server described in:

- `UI/Client/Client.md`
- `UI/Server/Server.md`

The UI/server layer assumes the PL exposes a controllable renderer through AXI-Lite registers and produces preview frames through a framebuffer, DMA, VDMA, or AXI-Stream video path. The current renderer modules are close to the rendering pipeline, but they still need a system-level wrapper.

## Current HDL State

The renderer branch contains a heightmap ray renderer made from:

```text
ray_gen
  -> marcher
  -> normal
  -> shader
```

The pipeline accepts pixel coordinates, camera parameters, and heightmap BRAM data, then outputs RGB pixels with aligned pixel coordinates and `valid_out`.

Important current limitations:

- There is no AXI-Lite slave register interface.
- There is no top-level module connecting the renderer to PS-controlled registers.
- Camera parameters are discrete vectors, not UI-level `yaw` / `pitch`.
- There is no pixel counter or frame scheduler in the renderer top level.
- There is no AXI-Stream, VDMA, DMA, or framebuffer output module.
- Heightmap memory loading and port arbitration are not defined at system level.
- `colour_mode`, `render_mode`, `max_depth`, `step_size`, and `height_scale` are not fully represented as runtime controls.

## Required Hardware Changes

### 1. Add A Renderer Top Module

Create a top-level module that instantiates `ray_unit` and owns the system integration.

Suggested name:

```text
renderer_top.sv
```

Responsibilities:

- Generate `px`, `py`, and `valid_in` for every pixel in the frame.
- Feed camera origin and basis vectors into `ray_unit`.
- Connect heightmap storage to the marcher and normal BRAM ports.
- Collect RGB output pixels.
- Generate frame timing/status signals.
- Expose control/status through AXI-Lite.

Minimum renderer top interface:

```systemverilog
module renderer_top (
    input  logic        clk,
    input  logic        rst_n,

    // AXI-Lite slave from PS
    // Add standard AXI-Lite signals here.

    // Pixel/frame output
    output logic [7:0]  m_axis_tdata_r,
    output logic [7:0]  m_axis_tdata_g,
    output logic [7:0]  m_axis_tdata_b,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,
    output logic        m_axis_tuser
);
```

Exact signal shape can follow the Vivado IP packaging style used by the team.

### 2. Add AXI-Lite Register File

The PS server will write renderer parameters using PYNQ MMIO. The hardware must expose stable 32-bit registers.

Baseline UI/server register map:

```text
0x00 REG_CONTROL
0x04 REG_YAW
0x08 REG_PITCH
0x0C REG_CAMERA_X
0x10 REG_CAMERA_Y
0x14 REG_CAMERA_Z
0x18 REG_HEIGHT_SCALE
0x1C REG_COLOUR_MODE
0x20 REG_RENDER_MODE
0x24 REG_MAX_DEPTH
0x28 REG_STEP_SIZE
0x2C REG_STATUS
```

Recommended hardware-facing expansion:

```text
0x00 REG_CONTROL
0x04 REG_STATUS
0x08 REG_FRAME_COUNT
0x0C REG_ERROR_FLAGS

0x10 REG_OX
0x14 REG_OY
0x18 REG_OZ

0x20 REG_FWD_X
0x24 REG_FWD_Y
0x28 REG_FWD_Z
0x2C REG_RIGHT_X
0x30 REG_RIGHT_Y
0x34 REG_RIGHT_Z
0x38 REG_UP_X
0x3C REG_UP_Y
0x40 REG_UP_Z

0x48 REG_SUN_DX
0x4C REG_SUN_DY
0x50 REG_SUN_DZ

0x58 REG_HEIGHT_SCALE
0x5C REG_COLOUR_MODE
0x60 REG_RENDER_MODE
0x64 REG_MAX_DEPTH
0x68 REG_STEP_SIZE
```

Preferred split of responsibility:

- PS/server converts `yaw` and `pitch` into `fwd`, `right`, and `up`.
- PL consumes only fixed-point camera vectors.
- PL does not need trigonometric logic for UI camera controls.

This keeps hardware simpler and makes the browser controls easier to adjust.

### 3. Define Fixed-Point Formats

The PS server and HDL must agree on exact formats.

Use the existing renderer defaults unless the hardware team chooses otherwise:

```text
Position/origin: signed 16-bit Q2.13 or Q4.11, depending on final `ray_unit` parameters
Direction vectors: signed 16-bit Q2.13
Height values: signed 16-bit, matching heightmap BRAM format
Step size: signed or unsigned fixed-point, same scale as position increments
Height scale: unsigned fixed-point multiplier or signed fixed-point gain
Mode registers: unsigned integer enum
```

Action needed:

- Pick one final format for each control.
- Document valid min/max values.
- Saturate or clamp unsafe values in hardware or PS software.
- Make reset defaults render a visible frame without UI input.

### 4. Add Runtime Control Latching

AXI-Lite writes can occur during active rendering. The renderer should not sample partially updated camera vectors mid-frame.

Required behavior:

- PS writes registers at any time.
- Hardware copies pending registers into active render registers only at a safe frame boundary.
- `REG_CONTROL` should include an `APPLY` or `UPDATE_PENDING` bit.
- `REG_STATUS` should expose whether active registers have been updated.

Suggested control bits:

```text
bit 0: enable renderer
bit 1: apply pending parameters at next frame
bit 2: soft reset renderer pipeline
bit 3: frame interrupt enable, optional
```

Suggested status bits:

```text
bit 0: renderer enabled
bit 1: frame active
bit 2: parameter update pending
bit 3: parameter update applied
bit 4: output backpressure detected
bit 5: heightmap not ready
```

### 5. Add Pixel Output / Preview Path

The UI server expects preview frames through `/preview.mjpg`. Hardware does not need to know about MJPEG, but it must provide frame data to PS.

Acceptable hardware options:

```text
Option A: AXI4-Stream video -> VDMA -> DDR framebuffer
Option B: AXI DMA writes RGB frames to DDR
Option C: AXI BRAM/framebuffer readable by PS for low-resolution previews
Option D: HDMI output plus optional PS-readable debug framebuffer
```

Recommended for compatibility:

- Use AXI4-Stream RGB output from `renderer_top`.
- Connect to VDMA or framebuffer in DDR.
- Let PS server read the latest completed frame and JPEG-encode it.

Output requirements:

- RGB888 or a clearly documented packed format.
- Known resolution, initially 320x240 or 640x480.
- Frame-done indicator.
- No blocking dependency on the PS preview server.
- If the preview reader is slow, rendering should continue or drop frames.

### 6. Add Pixel Counter And Frame Scheduler

The renderer currently expects pixel inputs. Hardware must generate these.

Required behavior:

- Iterate `px` from `0` to `W - 1`.
- Iterate `py` from `0` to `H - 1`.
- Assert `valid_in` for active pixels.
- Align `tuser` / start-of-frame with the first output pixel.
- Assert `tlast` at end of each line if using AXI4-Stream video.
- Handle pipeline latency from `ray_unit`.

The scheduler should support backpressure if the output path uses `tready`.

### 7. Resolve Heightmap Memory Architecture

`ray_unit` exposes many heightmap read ports:

```text
marcher: 16 read ports
normal: 4 read ports
total: 20 read ports
```

A single physical BRAM cannot directly provide 20 independent read ports. The hardware team must choose a practical memory architecture.

Possible approaches:

- Replicate heightmap BRAM across read ports.
- Bank the heightmap and handle conflicts.
- Reduce `N_STEPS`.
- Time-multiplex the marcher and lower throughput.
- Use a cached/tiled architecture.

For first integration, BRAM replication is simplest if resources allow.

Also define how the PS or simulation engine loads the heightmap:

- AXI BRAM controller
- DMA load into BRAM/URAM
- Pre-initialized ROM for demo terrain
- Shared DDR-backed memory with cached reads

### 8. Connect UI Parameters To HDL Behavior

Current UI parameters need hardware meaning:

```text
yaw, pitch
```

Handled in PS software. Convert to camera basis vectors before MMIO writes.

```text
camera_x, camera_y, camera_z
```

Map to `Ox`, `Oy`, `Oz`.

```text
height_scale
```

Apply before ray marching or in heightmap read path. If not implemented, remove or disable this UI control.

```text
colour_mode
```

Add shader mode selection. At minimum:

- 0: current altitude/lighting shader
- 1: grayscale height
- 2: depth/fog debug
- 3: normal debug

```text
render_mode
```

Define enum before exposing to UI. Suggested:

- 0: normal shaded render
- 1: height/debug render
- 2: depth/debug render

```text
max_depth
```

Currently `N_STEPS` is a synthesis parameter. Runtime `max_depth` requires gating the marcher after a selected number of steps, or multiple compiled configurations. If runtime control is too costly, document it as compile-time only and remove it from the first UI.

```text
step_size
```

Currently `DT` is a parameter in `march_step`. Runtime `step_size` requires passing a register value through marcher/march_step instead of using a parameter constant.

### 9. Add Test And Bring-Up Hooks

Minimum test support:

- Register readback test.
- Static camera default frame.
- Colour bars or test pattern mode without heightmap dependency.
- Small fixed heightmap ROM test.
- Frame counter increments once per completed frame.
- Backpressure simulation for AXI-Stream output.
- Known-good pixel samples compared against a Python or SystemVerilog reference.

Recommended status/debug registers:

```text
frame_count
last_px
last_py
valid_pixel_count
backpressure_count
heightmap_read_count
hit_count
offgrid_count
```

### 10. Update Documentation Deliverables

Hardware team should provide:

- Final AXI-Lite register map.
- Fixed-point format table.
- Control/status bit definitions.
- Frame output format.
- Resolution and clock assumptions.
- Heightmap load path.
- Reset/default parameter values.
- Vivado block design connection notes.

## First Compatible Milestone

The first milestone does not need every UI control to be fully functional.

Minimum compatible demo:

- AXI-Lite registers exist and can be read/written from PYNQ MMIO.
- PS can set camera origin and basis vectors.
- Renderer produces a continuous RGB frame stream.
- Preview path exposes latest frame to PS.
- `/preview.mjpg` can show either rendered output or a PL-generated test pattern.
- Unimplemented controls are ignored safely or reflected as unsupported in `REG_STATUS`.

## Open Decisions

The hardware and software teams need to agree on:

- Final register map: high-level UI registers only, hardware vectors only, or both.
- Exact fixed-point formats.
- Target preview resolution.
- Output path: AXI4-Stream + VDMA, DMA framebuffer, or BRAM framebuffer.
- Whether `max_depth` and `step_size` must be runtime controls.
- Heightmap memory replication/banking strategy.
- Whether the first demo uses live FDTD heightmap data or a static/test heightmap.
