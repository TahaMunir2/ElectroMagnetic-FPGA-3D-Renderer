# Design 1 S48

Design 1 S48 is the 48-step version of the Design 1 renderer.

The marcher depth is `N_STEPS=48`, so the renderer exposes 48 marcher BRAM
ports plus 4 normal BRAM ports. With the 64x64 heightmap, this is 52 inferred
heightmap BRAM instances.

Pipeline latency is `4 * N_STEPS + 14`, which is 206 cycles for this copy. HDMI
wrappers in this directory therefore delay `hsync`, `vsync`, and data-enable by
206 pixel-clock cycles.

The image pipeline is otherwise the Design 1 renderer: ray generation,
nearest-neighbour march hit detection, bilinear normal/height interpolation, and
shader output at one pixel per clock after pipeline fill.
