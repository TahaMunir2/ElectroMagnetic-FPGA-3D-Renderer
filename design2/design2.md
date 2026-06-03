# Design 2

Design 2 is the folded half-rate version of the renderer. HDMI scanout stays at
25 MHz, the renderer core runs at 50 MHz, and the top feeds one real pixel into
`ray_unit2` every two core cycles.

The current hardware target uses `N_STEPS=48`. Adjacent march steps share one
BRAM read port, so the marcher uses `N_STEPS/2 = 24` heightmap BRAM copies
instead of 48. `normal2` uses two more BRAM ports/copies for bilinear normal
reads. The renderer core therefore uses 26 heightmap BRAM copies, plus the HDMI
FIFO BRAM.

Latency:

- `ray_gen`: 4 cycles
- `marcher2`: 240 cycles, from 48 steps at 5 cycles per step
- `normal2`: 6 cycles
- `shader`: 5 cycles
- Total render latency: 255 renderer-core cycles

The top-level pixel feeder must only advance `(x,y)` when it asserts the
half-rate `gen_valid` strobe. Advancing every 50 MHz cycle corrupts the folded
pipeline input stream and can produce an all-sky frame even when HDMI timing is
valid.
