# MVP2 FDTD + D4S48 HDMI

This variant connects the quad-lane FDTD front-end to the 48-step Design4
ray-march renderer and outputs 640x480 HDMI.

## Pipeline

`CORDIC -> fdtd_quad_core -> field_magnitude -> ping-pong s_mag BRAMs
 -> s_mag_to_heightmap_bridge -> 50 writable D4 heightmap BRAM copies
 -> D4S48 low-DSP ray_unit4 -> async FIFO -> rgb2dvi -> HDMI`

The renderer runs at 100 MHz and emits one pixel every four core cycles,
matching the 25 MHz HDMI pixel stream after the async FIFO.

## Renderer

- BD module reference: `rtl/renderer_d4/d4s48_renderer_core_bd.v`
- Integrated implementation: `rtl/renderer_d4/d4s48_core_impl.sv`
- Core renderer sources: `rtl/renderer_d4/ray_unit4.sv`, `marcher4.sv`,
  `march_step4.sv`, `normal4.sv`, `ray_gen.sv`, `shader.sv`
- Writable heightmap copy: `rtl/renderer_d4/heightmap_bram_d4.sv`

The renderer uses the packaged D4S48 low-DSP march step:

- `N_STEPS = 48`
- marcher latency: `12 * 48 = 576` core cycles
- total renderer latency: `590` core cycles
- HDMI delay: `148` pixel clocks plus `8` FIFO priming pixels
- expected standalone renderer DSP count: `57`

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

## Verified Build

Vivado 2023.2 completed synthesis, implementation, and bitstream generation for
the full pipeline after replacing the renderer:

- post-route WNS: `+0.164 ns`
- post-route WHS: `+0.017 ns`
- LUTs: `18,960 / 53,200`
- registers: `24,992 / 106,400`
- BRAM tiles: `105 / 140`
- DSPs: `83 / 220`
- DRC: `0` errors, DSP pipelining warnings only

Generated board files:

- `fdtd_hdmi.bit`
- `fdtd_hdmi.hwh`
