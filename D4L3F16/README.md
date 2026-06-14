# D4L3F16 Framebuffer Stream Renderer

`D4L3F16` is an experimental implementation of the report's framebuffer and
parallel-lane architecture, derived from the board-verified `D4S48` renderer.

The implemented RTL covers the render-to-framebuffer side:

- `marcher16.sv` keeps the verified Design4 `march_step4` arithmetic but uses a
  16-cycle launch interval. The 48 march steps are statically grouped onto 12
  heightmap BRAM read ports.
- `ray_unit4_f16.sv` wraps one folded lane: `ray_gen -> marcher16 -> normal4 ->
  shader`.
- `ray_unit4_lanes3_f16_axis.sv` instantiates three folded lanes. Lane `L`
  renders columns where `x mod 3 == L`, then a small reorder buffer emits RGB
  pixels in raster order as an AXI4-Stream-style video source.

The output stream uses:

```text
m_axis_tdata  = {R, G, B}
m_axis_tvalid = pixel valid
m_axis_tready = downstream ready
m_axis_tuser  = first pixel of frame
m_axis_tlast  = last pixel of line
```

`m_axis_x` and `m_axis_y` are debug coordinates for simulation and custom
framebuffer writers. AXI VDMA does not need them when the stream is already in
raster order.

## Resource Model

For `N_STEPS=48`:

```text
D4S48 direct lane:       48 marcher copies + 2 normal copies = 50 copies
D4L3F16 per lane:        12 marcher copies + 2 normal copies = 14 copies
D4L3F16 three lanes: 3 * 14 copies = 42 copies
```

Vivado synthesis of the current shader trims the normal BRAM path because the
shader only uses `Nz` for lighting, so the measured BRAM use is 36 RAMB36 tiles.
That confirms the expected memory reduction.  However, the arithmetic is
triplicated with the lanes: synthesis reports 450 DSP48E1s, which exceeds the
PYNQ-Z1 `xc7z020` budget of 220 DSPs.  Therefore this variant validates the
framebuffer/lane architecture and stream ordering, but it is not a board-fit
implementation without further DSP reduction or time-multiplexing.

The three-lane aggregate rate is approximately:

```text
3 pixels / 16 cycles * 100 MHz = 18.75 Mpix/s
```

At 640x480, this is about 61 fps before DDR/VDMA overhead.

## DDR Framebuffer Integration

This folder does not implement a full board bitstream yet. A complete board
design should connect `ray_unit4_lanes3_f16_axis` to an AXI VDMA S2MM channel
that writes one DDR framebuffer while a separate AXI VDMA MM2S channel scans
the other buffer to HDMI at the fixed 25 MHz pixel rate.

Recommended block design:

```text
ray_unit4_lanes3_f16_axis
  -> AXI VDMA S_AXIS_S2MM
  -> PS DDR through Zynq HP port

PS DDR through Zynq HP port
  -> AXI VDMA M_AXIS_MM2S
  -> AXI4-Stream to Video Out / VTC
  -> rgb2dvi
  -> HDMI TX pins
```

Use at least two VDMA frame stores and swap buffers only on frame boundaries.
The PS should configure the framebuffer base addresses, stride, horizontal
size, and vertical size before enabling both VDMA channels.

## Verification

Smoke test from a Vivado shell:

```powershell
cd D4L3F16/sim_axis
xvlog -sv ../../D4S48/ray_gen.sv ../../D4S48/march_step4.sv ../marcher16.sv ../../D4S48/normal4.sv ../../D4S48/shader.sv ../ray_unit4_f16.sv ../../wrapper/heightmap_bram.sv ../ray_unit4_lanes3_f16_axis.sv ../tb_lanes3_f16_axis_smoke.sv
xelab --relax tb_lanes3_f16_axis_smoke -snapshot tb_lanes3_f16_axis_smoke
xsim tb_lanes3_f16_axis_smoke -runall
```

Expected result:

```text
D4L3F16_AXIS outputs=288 coord_errors=0 user_errors=0 last_errors=0 overflow=0
```

Create a synthesis project:

```powershell
vivado -mode batch -source scripts/create_d4l3f16_axis_project.tcl -tclargs -force
```

Current synthesis result for `ray_unit4_lanes3_f16_axis` at 100 MHz:

```text
timing: all user constraints met at synthesis, WNS +1.023 ns
LUTs:   47,738 / 53,200  (89.73%)
regs:   51,074 / 106,400 (48.00%)
BRAM:   36 / 140         (25.71%)
DSP:    450 / 220        (204.55%, does not fit)
```
