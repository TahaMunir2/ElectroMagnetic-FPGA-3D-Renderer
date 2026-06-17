# D4S48 Renderer

`D4S48` is the 48-step copy of the corrected Design4 renderer. It keeps
Design4's one-pixel-per-four-core-cycles throughput and one BRAM read port per
march step.

The D4S48 shader replaces `step_count * 255 / 48` with the mathematically
identical `step_count * 85 / 16`. This avoids a constant-divider critical path
at the 100 MHz renderer clock.

The HDMI wrapper keeps `vid_pVDE` independent of FIFO availability so a
renderer startup delay or FIFO underflow cannot invalidate the video timing.
Underflow pixels are shown as magenta for board diagnosis. Reset release is
synchronized separately into the pixel and renderer clock domains.

The registered renderer latency is:

- `ray_gen`: 4 core cycles
- `marcher4`: `12 * 48 = 576` core cycles
- `normal4`: 5 core cycles
- `shader`: 5 core cycles
- total: 590 core cycles

The HDMI wrapper converts that latency to 148 pixel clocks and adds an
eight-pixel FIFO priming margin, delaying video timing by 156 pixel clocks.

Generate and build the standalone PYNQ-Z1 Vivado project from the repository
root:

```powershell
vivado -mode batch -source scripts/create_d4s48_vivado_project.tcl -tclargs -force
vivado -mode batch -source scripts/build_vivado_bitstream.tcl -tclargs -project D4S48/vivado_project_d4s48/d4s48_renderer.xpr
```

The generated Vivado project and bitstream are intentionally ignored by git.

## Verified Implementation

Vivado 2023.2 low-DSP implementation for the PYNQ-Z1 (`xc7z020clg400-1`)
completed through bitstream generation:

- smoke simulation: 4800 outputs, 3651 non-sky pixels, 0 coordinate errors
- setup WNS: +0.446 ns
- hold WHS: +0.010 ns
- asynchronous FIFO bus-skew slack: +9.029 ns and +9.120 ns
- LUTs: 15,394 / 53,200 (28.94%)
- registers: 22,072 / 106,400 (20.74%)
- BRAM tiles: 49 / 140 (35.00%)
- DSPs: 57 / 220 (25.91%)

The generated bitstream is:

`D4S48/vivado_project_d4s48/d4s48_renderer.runs/impl_1/ray_unit_hdmi_top_d4s48.bit`
