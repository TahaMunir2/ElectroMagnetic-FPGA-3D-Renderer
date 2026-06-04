# Design4

Design4 performs the same bilinear height lookup as Design3 while using one
BRAM read port per march step. Each step reads its four corners over four
cycles, so the renderer accepts one pixel every four core cycles.

For 640x480 HDMI, the renderer core runs at 100 MHz while scanout runs at
25 MHz. The HDMI wrapper mirrors the complete 800x525 VGA timing in the core
domain, feeds only active pixels, and uses an asynchronous FIFO to bridge
renderer latency and clock phase.

The registered pipeline latency is:

- `ray_gen`: 4 core cycles
- `marcher4`: `11 * N_STEPS` core cycles
- `normal4`: 5 core cycles
- `shader`: 5 core cycles

With `N_STEPS=16`, total latency is 190 core cycles, or 48 pixel clocks after
rounding up. The HDMI wrapper adds an eight-pixel FIFO priming margin and
delays sync and data-enable by 56 pixel clocks total. This gives the FWFT
asynchronous FIFO enough time to expose pixel 0 in the read domain before
active video starts.

The Design4 BRAM outputs must remain clock-enabled every cycle. The logical
read-enable signals still describe requests, but the wrapper ties each
`heightmap_bram.re` input high so later pipeline stages capture the expected
registered data.

Generate and build the Vivado project from the repository root:

```powershell
vivado -mode batch -source scripts/create_design4_vivado_project.tcl -tclargs -force
vivado -mode batch -source scripts/build_vivado_bitstream.tcl -tclargs -project design4/vivado_project_design4/design4_renderer.xpr
```
