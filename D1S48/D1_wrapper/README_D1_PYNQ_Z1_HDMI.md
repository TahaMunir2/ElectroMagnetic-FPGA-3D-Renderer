# Design 1 S48 PYNQ-Z1 HDMI Output

Use `design1_ray_unit_top.sv` for timing-only implementation runs.

Use `design1_ray_unit_hdmi_top.sv` for board output on the PYNQ-Z1 HDMI TX connector.

## Vivado Setup

The easiest path is to generate the project from the repo root:

```tcl
source scripts/create_d1s48_vivado_project.tcl
```

Or from a Windows shell where Vivado is on PATH:

```powershell
vivado -mode batch -source scripts/create_d1s48_vivado_project.tcl
```

The generated project is `D1S48/vivado_project_d1s48/d1s48_renderer.xpr`.

For PS-controlled camera registers, generate the block-design project instead:

```powershell
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl
```

That project is `D1S48/vivado_project_d1s48_camera/d1s48_camera_renderer.xpr`.
The AXI4-Lite camera register block is assigned to `0x40000000`.

Manual setup is:

1. Change the project part/board to PYNQ-Z1 / `xc7z020clg400-1`.
2. Add these HDL files to Design Sources:
   - `D1S48/D1_wrapper/design1_ray_unit_hdmi_top.sv`
   - `D1S48/D1_wrapper/design1_video_timing_640x480.sv`
   - `D1S48/D1_wrapper/cube_heightmap_bram.sv`
   - `D1S48/design1_*.sv`
3. Add `D1S48/D1_wrapper/pynq_z1_hdmi.xdc` to Constraints.
4. Disable or remove `wrapper/constraints.xdc` from this HDMI constraints set.
   That file is only for the timing-analysis wrapper and creates a conflicting
   100 MHz clock.
5. Set `design1_ray_unit_hdmi_top` as the top module.
6. Add Clocking Wizard IP named `clk_wiz_0`:
   - input clock: `125.000 MHz`
   - `clk_out1`: `25.000 MHz` or `25.175 MHz`
   - `clk_out2`: `125.000 MHz` or `125.875 MHz`
7. Add Digilent `rgb2dvi` IP named `rgb2dvi_0`, configured for 7-series.
8. Generate bitstream and program the board with a monitor connected to HDMI OUT.

`rst` is connected to BTN0 and is active high. Leave BTN0 unpressed for normal
operation; press it to reset the HDMI/render pipeline.

The Design 1 S48 renderer latency is assumed to be 206 pixel-clock cycles. `design1_ray_unit_hdmi_top`
delays `hsync`, `vsync`, and data-enable by that amount so the video control
signals line up with the RGB output from `design1_ray_unit`.

## Mock Heightmap

`cube_heightmap_bram.sv` initializes the `heightmap_bram` module by default.
With `USE_MOCK_DATA=1`, each inferred BRAM powers up with a small synthetic
terrain: a central cube/plateau plus a lower surrounding hill. This removes the
Vivado `mem does not have driver` warning and lets the HDMI renderer produce a
visible image before a real map-loading path exists.

To use an external hex file later, instantiate `heightmap_bram` with:

```systemverilog
.USE_INIT_FILE (1'b1),
.INIT_FILE     ("heightmap_64x64.hex"),
.USE_MOCK_DATA (1'b0)
```

The hex file should contain one signed 16-bit value per line, in row-major
`{y, x}` address order. For the current `GRID_N=64`, that is 4096 lines.
