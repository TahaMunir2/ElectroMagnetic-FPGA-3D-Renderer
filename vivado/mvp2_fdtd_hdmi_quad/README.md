# MVP2_fdtd_hdmi_quad — 4-lane FDTD -> D1S48 renderer -> HDMI

Quad-lane (parallel) FDTD variant of the HDMI demo. The 64-row grid is split
into four 16-row lanes that solve in lockstep (Taha's quad architecture,
`origin/FDTD-MVP3`), so one iteration finishes in **2048 cycles instead of
8192 — 4x faster** at the same 25 MHz clock. The renderer/bridge/ping-pong are
unchanged; the picture is identical, the solver is just faster.

## What's reused vs new
- **Taha's quad core, logic untouched:** `top_fdtd_quad_lane` -> `fdtd_quad_core.sv`
  (renamed; only adds a magnitude read-back mux + a clear mux). His 4x
  `fdtd_solver` + `bram_module` + halo exchange + cubic `pml` are verbatim.
- **New glue:** `field_magnitude_quad.v` (scans the 4 banked memories via the
  read-back interface; |E|/|S|/signed-Ey), `fdtd_quad_bd_adapter.v` (free-run
  FSM + field clear + soft source + checksum + s_mag out).
- **Downstream identical:** ping-pong, `s_mag_to_heightmap_bridge`,
  `heightmap_bram_rw`, D1S48 renderer, rgb2dvi.

## Build
`scripts/create_fdtd_render_project.tcl` then `scripts/run_build.tcl`.
Result: timing met (WNS +11.1 ns @ 25 MHz), **BRAM 108/140 (77%)** — *less*
than the single-lane 114 because the partitioned `bram_module` packs tighter.
LUT 40% / FF 15% / DSP 38.

## AXI map
| Offset | Block |
|--------|-------|
| 0x40000000 | renderer camera (optional) |
| 0x41200000 | gpio_ctrl |
| 0x41210000 | gpio_status |

## Bring-up
`test_fdtd_hdmi_quad.ipynb`: `set_ctrl(...)` to start free-run, `set_height(n)`
to tune relief, `clear_fields()` to reset. Single source this build
(`source_addr` in `set_ctrl`); multi-source is a deferred follow-up.

## Verified in simulation (Verilator; iverilog can't run the SV)
- Taha's `top_fdtd_quad_lane` standalone: `solver_done` at cycle 2047 (= 2x1024).
- Full front-end `tb_quad_front.sv`: 6 free-run frames, live s_mag field at the
  source, checksum advancing -> quad core + read-back + magnitude all correct.

## UDP source-magnitude control (ESP32 -> PS)
The ESP32 streams a probe value over WiFi/UDP to the PYNQ PS, which maps it to
the FDTD **source amplitude** live (one fixed source at the grid centre).
- Port **5005**, packet = one ASCII integer per datagram (e.g. `2731`).
- Both devices on the same local network (ESP32 on the WiFi router the PYNQ
  Ethernet is on).
- ESP32: `esp32/source_magnitude_udp.ino` (set SSID/PASS/PYNQ_IP, probe on the
  ADC pin).
- PS: `MagnitudeUDP` cell in `test_fdtd_hdmi_quad.ipynb` — `mc.calibrate()` to
  find the probe range, then `mc.start()`; a daemon thread drives `amplitude`
  (gpio_ctrl CH1[31:16]) from the latest packet. `mc.stop()` to end.
