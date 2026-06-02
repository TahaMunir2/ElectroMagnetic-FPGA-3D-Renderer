# Scripts

Vivado automation and PYNQ-side helper scripts.

## Vivado Project Generators

Run these from the repository root:

```powershell
vivado -mode batch -source scripts/create_renderer_bd.tcl
vivado -mode batch -source scripts/create_d1s48_vivado_project.tcl
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl
```

Use `-tclargs -force` to recreate an existing generated project.

The D1S48 camera BD generator also accepts `-project_dir <path>` if the default
generated project directory is locked or if you want a separate output copy.

For `rgb2dvi`, install or point Vivado to the Digilent Vivado IP library. The
D1S48 camera project script accepts:

```powershell
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl -tclargs -ip_repo D:/path/to/vivado-library/ip
```

## PYNQ Helpers

- `camera_control.py` contains the Python MMIO wrapper for the PS-controlled
  camera register map.
