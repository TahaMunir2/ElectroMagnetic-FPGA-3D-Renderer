# MVP2 Full Pipeline Integration Snapshot

This folder is a source-controlled handoff of the current MVP2 Vivado integration level. It intentionally contains reusable RTL, custom IP packaging, Tcl scripts, and simulation tests, not Vivado generated run/cache output.

## Integrated Path

The current block-design path is:

```text
CORDIC source adapter -> FDTD solver adapter -> Ey/Ex/Bz BRAMs
                                      |
                                      v
                     field_magnitude_bd_adapter -> s_mag_bram
                                      |
                                      v
                         s_mag_to_renderer_bridge -> renderer_bd_adapter
```

## Validation Status

Passing checks from the live Vivado project snapshot:

- `sim/mvp2_pipeline_smoke_tb.sv`: solver -> `|E|` magnitude -> `s_mag_bram` -> renderer bridge smoke test passes.
- `scripts/check_mvp2_bd_connectivity.tcl`: block-design structural connectivity passes.
- `scripts/run_renderer_ray_unit_sim.tcl`: standalone renderer ray-unit XSim regression passes with `tested=16 pass=16 fail=0`.
- Vivado synthesis completes without black boxes.

Known remaining hardware signoff issues:

- Timing is not closed at the current 100 MHz constraint. Last checked WNS was about `-7.896 ns`.
- Top-level IO is not board-constrained yet. The integrated design exports many debug/control/data ports, so LOC/IOSTANDARD constraints or an internal bus/register interface are still needed before bitstream signoff.

## Notes

- `rtl/field_magnitude_bd_adapter.v` owns the separated `|E|` / `|S|` magnitude calculation.
- `rtl/renderer_integration/s_mag_to_renderer_bridge.v` accounts for synchronous BRAM read latency by enabling `s_mag_bram` in the wait/read state.
- `ip_repo/` mirrors the packaged custom IPs used by the current block design.
- The Tcl scripts default to the local Vivado project path used during integration. Override `VIVADO_PROJECT`, `REPO_ROOT`, and related environment variables when replaying them from another checkout.
