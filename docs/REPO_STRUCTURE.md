# Repository Structure

This repository keeps source HDL, Vivado automation, and board-debug assets in
source control. Vivado run products and local tool output are ignored.

## Source-Controlled Directories

- `src/hdl/` - baseline renderer/FDTD HDL modules.
- `src/tb/` - SystemVerilog testbenches and generated test-vector sources.
- `design1/`, `design2/`, `design3/`, `design4/` - renderer design variants.
  Generated Vivado projects inside `design2/` and `design3/` are ignored.
- `D1S48/` - 48-step copy of Design 1. Generated Vivado projects inside this
  directory are ignored.
- `D1S32/` - 32-step copy of Design 1. Generated Vivado projects inside this
  directory are ignored.
- `wrapper/` - PYNQ-Z1 HDMI and AXI wrappers for the main renderer path.
- `D1S48/D1_wrapper/` - PYNQ-Z1 HDMI and AXI wrappers for the D1S48 renderer.
- `D1S32/D1_wrapper/` - PYNQ-Z1 HDMI and AXI wrappers for the D1S32 renderer.
- `scripts/` - Vivado Tcl project generators and PYNQ-side Python helpers.
- `notebooks/` - Jupyter notebooks for PYNQ board debugging.
- `vivado_project/` - checked-in Vivado project entry point and selected IP
  configuration files only.
- `docs/` - project notes, board setup, equations, and repo guidance.
- `tests/` - small regression/smoke tests outside the module-local testbench
  directory.

## Generated Output

Do not commit normal Vivado run output:

- `.Xil/`
- `*.jou`, `*.log`, `*.str`, `*.backup.*`
- `*.bit`, `*.bin`, `*.hwh`, `*.ltx`
- `*.dcp`, `*.rpt`, `*.rpx`, `*.pb`
- `*.wdb`, `*.wcfg`, `*.vcd`, `*.vvp`
- `*.cache`, `*.gen`, `*.hw`, `*.ip_user_files`, `*.runs`, `*.sim`

For the D1S variants, generated Vivado project directories are intentionally
ignored:

- `D1S48/vivado_project_*/`
- `D1S32/vivado_project_*/`
- `design2/vivado_project_*/`
- `design3/vivado_project_*/`

## Commit Guidance

Commit HDL, constraints, Tcl scripts, Python helpers, notebooks, and docs.
Commit `.xci` files only when they define required IP configuration for a
project. Avoid committing implementation runs, bitstreams, handoff files, logs,
or temporary duplicate IP directories.

The current checked-in Vivado project keeps only:

- `vivado_project/ray_renderer.xpr`
- `vivado_project/ray_renderer.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci`
- `vivado_project/ray_renderer.srcs/sources_1/ip/rgb2dvi_0/rgb2dvi_0.xci`

If tracked generated artifacts need to be removed from git while keeping the
local files, use:

```powershell
git rm --cached src/tb/*.vcd src/tb/*.vvp
```
