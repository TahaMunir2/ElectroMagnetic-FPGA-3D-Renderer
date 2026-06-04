# Design 3

Design 3 performs bilinear height interpolation inside every march step, which
smooths the terrain silhouette as well as its shading. It remains a half-rate
renderer: the core runs at 50 MHz and accepts one active pixel every two core
cycles while HDMI scans at 25 MHz.

The current hardware target uses `N_STEPS=48`. Each `march_step3` owns two
heightmap read ports and reads four bilinear corners over two cycles. The
marcher therefore exposes 96 single-port heightmap read ports, and `normal3`
uses two more.

Latency:

- `ray_gen`: 4 cycles
- `marcher3`: 336 cycles, from 48 steps at 7 cycles per step
- `normal3`: 5 cycles
- `shader`: 5 cycles
- Total render latency: 350 renderer-core cycles, or 175 pixel-clock cycles

The HDMI top includes the full `800 x 525` VGA timing in the core domain and
feeds the renderer only during the `640 x 480` active area. This keeps the FIFO
producer rate matched to scanout instead of filling the FIFO during blanking.
The HDMI sync and data-enable signals are delayed by the 175-pixel render
latency before FIFO pixels are displayed.

Design3's bilinear marcher also requires each heightmap BRAM output register to
clock every cycle. The HDMI top therefore ties each BRAM `re` input high; using
the per-step request signal as the BRAM clock enable causes stale corner data
and can produce an all-sky image.
