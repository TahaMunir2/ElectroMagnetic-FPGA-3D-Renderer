# MVP2_fdtd_contour — 4-lane FDTD -> 2D contour renderer -> HDMI

Step A of the "bigger/clearer" path: keeps the 4-lane FDTD front-end but swaps
the 3D ray-march renderer for Cyril's **2D top-down contour/heatmap** renderer.

Per pixel: `(px,py) -> grid cell -> ONE heightmap BRAM read -> 16-band diverging
palette (blue=trough -> red=crest) -> RGB`. Use `mag_mode=2` (signed Ey) for the
canonical wave heatmap.

## Why this variant
The 3D D1S48 renderer needed **52 heightmap BRAMs** (~104 RAMB36, ~75% of the
chip). The contour renderer needs **ONE**. That frees the BRAM that a bigger
grid / more lanes need, it's simpler/lower-DSP, and a 2D color map is how FDTD
fields are normally read (clearer for waves + interference than the 3D terrain).

## Pipeline (single 25 MHz clk_pix)
`CORDIC -> fdtd_quad_core (4 lanes) -> field_magnitude -> ping-pong s_mag
 -> s_mag_to_heightmap_bridge -> 1 heightmap_bram_rw -> contour_unit -> rgb2dvi`.

## Renderer integration
- `rtl/renderer/contour_renderer_core_bd.v` — BD wrapper: `contour_unit` + one
  writable `heightmap_bram_rw` + `design1_video_timing_640x480` + sync align
  (LAT=3). No AXI / camera.
- `rtl/renderer/contour_unit.sv` — Cyril's unit (verified bit-exact, 307200/307200).
- Bridge unchanged — its broadcast write now feeds a single heightmap.

## Build
`scripts/create_fdtd_render_project.tcl` then `scripts/run_build.tcl`.
AXI: `gpio_ctrl 0x41200000`, `gpio_status 0x41210000` (no camera AXI).

## Bring-up (`test_fdtd_contour.ipynb`)
`set_ctrl(..., mag_mode=2, ...)` to start; `set_height(n)` for color span,
`clear_fields()` to reset.

## Next (Step B)
With ~100 RAMB36 freed, bump the grid (64 -> 128) for finer waves.
