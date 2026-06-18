# MVP2 FDTD + D4S80DO HDMI

This variant connects the quad-lane FDTD front-end to the 80-step Design4
low-DSP ray-march renderer and outputs 640x480 HDMI.

## Pipeline

`CORDIC -> fdtd_quad_core -> field_magnitude -> ping-pong s_mag BRAMs
 -> s_mag_to_heightmap_bridge -> 82 writable D4 heightmap BRAM copies
 -> D4S80DO low-DSP ray_unit4 -> async FIFO -> rgb2dvi -> HDMI`

The renderer runs at 100 MHz and emits one pixel every four core cycles,
matching the 25 MHz HDMI pixel stream after the async FIFO.

## Renderer

- BD module reference: `rtl/renderer_d4/d4s80do_renderer_core_bd.v`
- Integrated implementation: `rtl/renderer_d4/d4s80do_core_impl.sv`
- Core renderer sources: `rtl/renderer_d4/ray_unit4.sv`, `marcher4.sv`,
  `march_step4.sv`, `normal4.sv`, `ray_gen.sv`, `shader.sv`
- Writable heightmap copy: `rtl/renderer_d4/heightmap_bram_d4.sv`

The renderer uses the packaged D4 low-DSP march step:

- `N_STEPS = 80`
- marcher latency: `12 * 80 = 960` core cycles
- total renderer latency: `974` core cycles
- HDMI delay: `244` pixel clocks plus `8` FIFO priming pixels
- expected full-pipeline BRAM usage: near `137 / 140`
- expected full-pipeline DSP usage: near `115 / 220`

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

D4S80DO is an experimental extension of the verified D4S48 low-DSP pipeline.
It is expected to be BRAM-tight because this variant does not yet include the
dual-read heightmap sharing optimization.
