# Scripts

Vivado automation and PYNQ-side helper scripts.

## Vivado Project Generators

Run these from the repository root:

```powershell
vivado -mode batch -source scripts/create_renderer_bd.tcl
vivado -mode batch -source scripts/create_design2_vivado_project.tcl
vivado -mode batch -source scripts/create_d1s48_vivado_project.tcl
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl
vivado -mode batch -source scripts/create_d1s32_vivado_project.tcl
vivado -mode batch -source scripts/create_d1s32_camera_bd_project.tcl
```

Use `-tclargs -force` to recreate an existing generated project.

The Design2, D1S48, and D1S32 generators also accept `-project_dir <path>` if
the default generated project directory is locked or if you want a separate
output copy.

For `rgb2dvi`, install or point Vivado to the Digilent Vivado IP library. The
Design2 and D1S camera project scripts accept:

```powershell
vivado -mode batch -source scripts/create_design2_vivado_project.tcl -tclargs -ip_repo D:/path/to/vivado-library/ip
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl -tclargs -ip_repo D:/path/to/vivado-library/ip
vivado -mode batch -source scripts/create_d1s32_camera_bd_project.tcl -tclargs -ip_repo D:/path/to/vivado-library/ip
```

## Vivado Bitstream Build

Build an existing generated project through `write_bitstream` and produce timing
and utilization reports:

```powershell
vivado -mode batch -source scripts/build_vivado_bitstream.tcl -tclargs -project design2/vivado_project_design2/design2_renderer.xpr
```

## Design2 Smoke Test

The Design2 smoke test samples the mock-heightmap renderer and fails if every
observed output is the sky color:

```powershell
xvlog -sv wrapper/heightmap_bram.sv design2/ray_gen.sv design2/march_step2.sv design2/marcher2.sv design2/normal2.sv design2/shader.sv design2/ray_unit2.sv design2/tb_ray_unit2_smoke.sv
xelab --relax tb_ray_unit2_smoke -snapshot tb_ray_unit2_smoke
xsim tb_ray_unit2_smoke -runall
```

## PYNQ Helpers

- `camera_control.py` contains the Python MMIO wrapper for the PS-controlled
  camera register map.
