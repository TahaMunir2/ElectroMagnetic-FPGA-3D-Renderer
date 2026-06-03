# Design 1 S32

Design 1 S32 is the 32-step version of the Design 1 renderer.

The marcher depth is `N_STEPS=32`, so the renderer exposes 32 marcher BRAM
ports plus 4 normal BRAM ports. With the 64x64 heightmap, this is 36 inferred
heightmap BRAM instances.

Pipeline latency is `4 * N_STEPS + 14`, which is 142 cycles for this copy. HDMI
wrappers in this directory therefore delay `hsync`, `vsync`, and data-enable by
142 pixel-clock cycles.

The image pipeline is otherwise the Design 1 renderer: ray generation,
nearest-neighbour march hit detection, bilinear normal/height interpolation, and
shader output at one pixel per clock after pipeline fill.
