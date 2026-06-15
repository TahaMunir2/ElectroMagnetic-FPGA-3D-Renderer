# Scripts

Vivado helper scripts for the MVP2 block-design checkpoint:

- `vivado_integrate_fdtd_solver_bd.tcl` rebuilds the canonical `mvp2_ftdt_bd`
  block design around the physical BRAM IPs, CORDIC source generator, and
  FDTD solver adapter. It also wires `s_mag_bram` for the post-solver render
  magnitude pass, selected by `mag_mode`.
- `vivado_cleanup_single_bd_project.tcl` removes stale bring-up/test sources
  from the Vivado project and validates that only the canonical block-design
  cells remain.
- `vivado_report_solver_integrated_impl.tcl` opens the implemented run and
  writes utilization, timing, route, and DRC reports.
- `vivado_run_physical_wave_probe_sim.tcl` runs the physical wave probe
  regression with Vivado XSim.
- `cpu_benchmark.ipynb` measures the Cortex-A9 FDTD solver-only baseline.
- `cpu_pipeline_renderer_benchmark.ipynb` measures the Cortex-A9 full pipeline
  baseline: FDTD update, render magnitude buffer generation, and 640x480
  48-step CPU ray-march rendering.

The current MVP2 Vivado architecture deliberately keeps the physical BRAM IPs
outside the solver adapter so later `|S|`, renderer, probe, and PML work can
share or arbitrate access explicitly.
