# MVP2_fdtd_hdmi_msrc — multi-source FDTD → D1S48 renderer → HDMI

Variant of MVP2_fdtd_hdmi adding **up to 4 configurable coherent sources** for
live interference experiments. Everything else (soft source, 3 view modes,
runtime height) is identical.

Integrates the 2D FDTD Maxwell solver (with ping-pong s_mag buffers) into Taha's
D1S48 ray-march renderer, driving a 3D heightmap of the EM-wave magnitude out
over HDMI on the PYNQ-Z1. PS-controllable over AXI.

## Pipeline (single 25 MHz clk_pix datapath)
```
CORDIC → fdtd_solver → field_magnitude → ping-pong s_mag BRAMs
       → s_mag_to_heightmap_bridge (vblank-gated) → 52 writable heightmap BRAMs
       → D1S48 ray_unit → rgb2dvi → HDMI
```
- External 125 MHz (H16) → clk_wiz → 25 MHz clk_pix (whole datapath) + 125 MHz serial (rgb2dvi)
- PS FCLK_CLK0 50 MHz → AXI domain (renderer camera AXI-Lite + FDTD GPIO)

## Build
```
vivado -mode batch -source scripts/create_fdtd_render_project.tcl          # BD only
RUN_IMPL=1 vivado -mode batch -source scripts/create_fdtd_render_project.tcl # + bitstream
```
Output: `fdtd_hdmi.bit` (+ `fdtd_hdmi.hwh`). Build result: timing met (WNS +5.4 ns @ 25 MHz),
BRAM 114/140 (81%), LUT 21% / FF 14% / DSP 9%.

## AXI map
| Offset | Block | Notes |
|--------|-------|-------|
| 0x40000000 | renderer camera control | AXI4-Lite; sane defaults, optional |
| 0x41200000 | axi_gpio_ctrl | CH1 {amplitude, phase_step}; CH2 {free_run[15], sample_req[14], mag_mode[13], solver_enable[12], source_addr[11:0]} |
| 0x41230000 | axi_gpio_src | source positions 1-3 + per-source enables (CH1 {en[3:0]@24, src2@12, src1@0}; CH2 src3@0) |
| 0x41210000 | axi_gpio_status | CH1 solver_checksum; CH2 {source_q313[31:16], bridge_busy[7], pp_frame_ready[6], pp_read_sel[5], source_latched[4], mag_busy[3], mag_done[2], source_valid[1], solver_done[0]} |

## Bring-up (board person)
1. Program `fdtd_hdmi.bit` + `fdtd_hdmi.hwh` (see `test_fdtd_hdmi.ipynb`).
2. Set source params, then assert `solver_enable + sample_req + free_run`.
3. Sanity check via `axi_gpio_status`: `solver_checksum` keeps changing and
   `pp_frame_ready`/`bridge_busy` toggle ⇒ FDTD→bridge chain is live.
4. HDMI should show an animated 3D terrain of the wave magnitude.
5. Multiple sources: `set_sources([(24,32),(40,32)])` for two coherent sources
   -> interference fringes; move them to change fringe spacing (up to 4).

## Source: soft, not hard
The FDTD source is a **soft source** — the centre cell does `ey <= engine_ey_new
+ source_in` (adds the drive on top of the natural update) rather than
overwriting it. A hard (overwrite) source acts as a fixed reflector and, under
continuous free-run, turns the grid into a driven resonant cavity whose energy
climbs without bound until it saturates. The soft source removes that reflector;
`tb_energy.sv` shows the field settles to a bounded steady state instead of
climbing.

## Display modes (runtime, `mag_mode`)
`mag_mode` (2-bit, GPIO ctrl CH2 bits {21,13}) selects what gets written to the
heightmap:
- `0` = `|E|` rectified magnitude (energy view; clean dome, source spike).
- `1` = `|S|` Poynting (`|E|·|Bz|`) — wider dynamic range, spikier; use a smaller
  `height_ctl` (0 or negative) for it.
- `2` = raw signed `Ey` — smooth hills *and* valleys around a flat plane (the
  "water ripple" wave view, no rectification cusps). The bridge scales it with a
  sign-preserving shift.

## Tuning relief — live, no rebuild
Terrain height is set at runtime via `height_ctl` (signed −16..+15, GPIO ctrl CH2
bits [20:16]); the bridge applies it as a bidirectional shift (`>0` amplify,
`<0` attenuate, `0` pass-through). Because the soft source keeps |E| small, a
positive value (≈ +2..+4) is usually needed. Tune from Python with
`set_height(n)` while it runs — no rebuild.

## Verified in simulation (iverilog, see `sim/`)
- `tb_bridge.sv` — bridge copies all 4096 cells, correct scaling + readback.
- `tb_freerun.sv` — solver auto-restarts on `frame_done`; pauses (no field-BRAM
  corruption) while the magnitude scan runs.
- `tb_energy.sv` — hard vs soft source: hard pins the source cell (reflector),
  soft settles to a bounded, stable field over 120 free-run iterations.

## Notes
- `rtl/renderer/heightmap_bram.sv` is Taha's original read-only mock, kept for
  reference; the build uses `rtl/integration/heightmap_bram_rw.sv` instead.
- The delivered `.bit` predates the `set_clock_groups -asynchronous` line now in
  the XDC. That constraint only cleans the timing report (TIMING-6/7); behaviour
  is unchanged, so no rebuild is needed before the first hardware test.
