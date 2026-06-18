# MVP2 FDTD + D5S128 HDMI

This variant connects the quad-lane FDTD front-end to the 128-step Design5
low-DSP ray-march renderer and outputs 640x480 HDMI.

## Pipeline

`CORDIC -> fdtd_quad_core -> field_magnitude -> ping-pong s_mag BRAMs
 -> s_mag_to_heightmap_bridge -> paired dual-read D5 heightmap BRAM copies
 -> D5S128 low-DSP ray_unit4 -> async FIFO -> rgb2dvi -> HDMI`

The renderer runs at 100 MHz and emits one pixel every four core cycles,
matching the 25 MHz HDMI pixel stream after the async FIFO.

## Renderer

- BD module reference: `rtl/renderer_d5/d5s128_renderer_core_bd.v`
- Integrated implementation: `rtl/renderer_d5/d5s128_core_impl.sv`
- Core renderer sources: `rtl/renderer_d5/ray_unit4.sv`, `marcher4.sv`,
  `march_step4.sv`, `normal4.sv`, `ray_gen.sv`, `shader.sv`
- Shared writable heightmap copy: `rtl/renderer_d5/heightmap_bram_d5_dualread.sv`

The renderer uses the packaged D4 low-DSP march step:

- `N_STEPS = 128`
- marcher latency: `12 * 128 = 1536` core cycles
- total renderer latency: `1550` core cycles
- HDMI delay: `388` pixel clocks plus `8` FIFO priming pixels
- heightmap memory: `64` paired marcher BRAMs + `1` normal BRAM
- measured full-pipeline BRAM usage: `122 / 140`
- measured full-pipeline DSP usage: `163 / 220`

The PS can load the camera basis through the camera GPIO registers; until then
the renderer defaults to the fixed isometric view.

## Build

From Vivado batch/Tcl, run:

```tcl
source scripts/create_fdtd_render_project.tcl
source scripts/run_build.tcl
```

The Tcl scripts currently target the project directory set inside
`scripts/create_fdtd_render_project.tcl`.

## Build Status

D5S128 is an experimental extension of the verified D4 low-DSP pipeline. It
adds paired dual-read heightmap memories and a small clk_pix-to-clk_core write
FIFO so 128 logical march-step read ports only require 64 marcher heightmap
copies.

Vivado 2023.2 completed synthesis, implementation, and bitstream generation:

- post-route WNS: `+0.239 ns`
- post-route WHS: `+0.016 ns`
- LUTs: `42,735 / 53,200`
- registers: `59,859 / 106,400`
- BRAM tiles: `122 / 140`
- DSPs: `163 / 220`
- DRC: warnings only (`DPBU`, `DPIP`, `DPOP` DSP pipelining/clock-leaf warnings)
