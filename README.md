# Electromagnetic FPGA 3D Renderer

FPGA renderer and electromagnetic-simulation workspace. The current active board
target is the PYNQ-Z1, with HDMI output and PS-controlled camera registers for
renderer debugging.

## Project Layout

- `src/` - baseline HDL, Python references, and module-level testbenches.
- `design1/` ... `design4/` - renderer design variants.
- `D1S48/` - 48-step Design 1 renderer variant.
- `D1S32/` - 32-step Design 1 renderer variant.
- `wrapper/` - PYNQ-Z1 HDMI/AXI wrappers for the main renderer.
- `D1S48/D1_wrapper/` - PYNQ-Z1 HDMI/AXI wrappers for D1S48.
- `D1S32/D1_wrapper/` - PYNQ-Z1 HDMI/AXI wrappers for D1S32.
- `scripts/` - Vivado Tcl generators and PYNQ-side camera helper code.
- `notebooks/` - PYNQ Jupyter debugging notebooks.
- `docs/` - design notes, setup guides, equations, and repo guidance.
- `vivado_project/` - checked-in Vivado project entry point plus required `.xci`
  IP configuration files.

See [Repository Structure](docs/REPO_STRUCTURE.md) for detailed commit/ignore
guidance.

## Active FPGA Flows

Generate the Design2 HDMI project:

```powershell
vivado -mode batch -source scripts/create_design2_vivado_project.tcl
```

Generate the Design3 HDMI project:

```powershell
vivado -mode batch -source scripts/create_design3_vivado_project.tcl
```

Build an existing generated project through bitstream generation:

```powershell
vivado -mode batch -source scripts/build_vivado_bitstream.tcl -tclargs -project design2/vivado_project_design2/design2_renderer.xpr
```

Generate the D1S48 timing-only HDMI project:

```powershell
vivado -mode batch -source scripts/create_d1s48_vivado_project.tcl
```

Generate the D1S48 block-design project with PS camera control:

```powershell
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl
```

Generate the D1S32 timing-only HDMI project:

```powershell
vivado -mode batch -source scripts/create_d1s32_vivado_project.tcl
```

Generate the D1S32 block-design project with PS camera control:

```powershell
vivado -mode batch -source scripts/create_d1s32_camera_bd_project.tcl
```

The camera-control AXI block is assigned to `0x40000000`.

## MVP: 1D FDTD Implementation

The original simulation scaffold targets a 1D FDTD solver with the following
specifications:

- **Field Components**: 1D Ey and Bz
- **Precision**: Q3.13 fixed-point
- **Cell Count**: 64-cell arrays for Ey and Bz
- **Wave Source**: CORDIC-based sine wave generator
- **Boundary Conditions**: Zero boundaries (causing reflections)

See [1D FDTD Reference](docs/1d_fdtd_reference.md) for detailed specifications.

## Status

The repo now contains the renderer HDL variants, PYNQ-Z1 HDMI wrappers, Vivado
automation scripts, and a PYNQ camera-control notebook/helper.

## Getting Started

Refer to the wrapper READMEs and Vivado Tcl scripts for board builds. For PYNQ
debugging, use `notebooks/renderer_camera_debug.ipynb` with the generated `.bit`
and matching `.hwh` copied to the board.
