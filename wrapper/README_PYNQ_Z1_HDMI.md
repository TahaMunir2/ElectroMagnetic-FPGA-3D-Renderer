# PYNQ-Z1 HDMI Output

Use `ray_unit_top.sv` for timing-only implementation runs.

Use `ray_unit_hdmi_top.sv` for a standalone RTL top that instantiates
`clk_wiz_0` and `rgb2dvi_0` internally.

For Vivado block-design/IP Integrator work, package and instantiate
`ray_renderer_core_axi.sv`. Keep `clk_wiz_0` and `rgb2dvi_0` as separate block
design IP.

## Vivado Setup

1. Change the project part/board to PYNQ-Z1 / `xc7z020clg400-1`.
2. Add these HDL files to Design Sources:
   - `wrapper/ray_renderer_core_axi.sv`
   - `wrapper/ray_unit_hdmi_top.sv`
   - `wrapper/camera_ctrl_axi.sv`
   - `wrapper/video_timing_640x480.sv`
   - `wrapper/heightmap_bram.sv`
   - `src/hdl/*.sv`
3. Add `wrapper/pynq_z1_hdmi.xdc` to Constraints.
4. Disable or remove `wrapper/constraints.xdc` from this HDMI constraints set.
   That file is only for the timing-analysis wrapper and creates a conflicting
   100 MHz clock.
5. Set `ray_unit_hdmi_top` as the top module.
6. Add Clocking Wizard IP named `clk_wiz_0`:
   - input clock: `125.000 MHz`
   - `clk_out1`: `25.000 MHz` or `25.175 MHz`
   - `clk_out2`: `125.000 MHz` or `125.875 MHz`
7. Add Digilent `rgb2dvi` IP named `rgb2dvi_0`, configured for 7-series.
8. Generate bitstream and program the board with a monitor connected to HDMI OUT.

`rst` is connected to BTN0 and is active high. Leave BTN0 unpressed for normal
operation; press it to reset the HDMI/render pipeline.

## PS Camera Control

`ray_renderer_core_axi` exposes an AXI4-Lite slave interface for camera control
and parallel video outputs for `rgb2dvi`. Use it as a module/IP inside a Vivado
block design:

1. Add `ZYNQ7 Processing System`.
2. Run block automation for the PYNQ-Z1 PS.
3. Enable `M_AXI_GP0`.
4. Add `Clocking Wizard`.
   - input: PYNQ-Z1 125 MHz board clock
   - `clk_out1`: 25 MHz pixel clock
   - `clk_out2`: 125 MHz serial clock
5. Add Digilent `rgb2dvi`.
   - configure it for external `SerialClk`
6. Add `ray_renderer_core_axi` as a module/custom IP.
7. Connect clocks:
   - `clk_wiz_0/clk_out1` -> `ray_renderer_core_axi/clk_pix`
   - `clk_wiz_0/clk_out1` -> `rgb2dvi/PixelClk`
   - `clk_wiz_0/clk_out2` -> `rgb2dvi/SerialClk`
8. Connect resets:
   - use the clock wizard `locked` signal and/or Processor System Reset to
     drive an active-low reset for `ray_renderer_core_axi/rst_pix_n`
   - drive `rgb2dvi/aRst` active while the pixel clock is not ready
9. Connect video:
   - `ray_renderer_core_axi/vid_pData` -> `rgb2dvi/vid_pData`
   - `ray_renderer_core_axi/vid_pVDE` -> `rgb2dvi/vid_pVDE`
   - `ray_renderer_core_axi/vid_pHSync` -> `rgb2dvi/vid_pHSync`
   - `ray_renderer_core_axi/vid_pVSync` -> `rgb2dvi/vid_pVSync`
10. Connect AXI:
   - `M_AXI_GP0` -> `ray_renderer_core_axi/S_AXI`
   - `FCLK_CLK0` -> `ray_renderer_core_axi/s_axi_aclk`
   - processor-system-reset active-low peripheral reset ->
     `ray_renderer_core_axi/s_axi_aresetn`
11. Make the `rgb2dvi` TMDS outputs external:
   - `TMDS_Clk_p`
   - `TMDS_Clk_n`
   - `TMDS_Data_p[2:0]`
   - `TMDS_Data_n[2:0]`
12. Rename the external ports or XDC constraints so they match:
   - `hdmi_tx_clk_p`
   - `hdmi_tx_clk_n`
   - `hdmi_tx_p[2:0]`
   - `hdmi_tx_n[2:0]`
13. Assign an address in Address Editor and export the bitstream/hwh.

Register map:

```text
0x00 control   bit 0: write 1 to commit shadow camera at next frame
0x04 status    bit 0: commit pending

0x10 Ox        0x14 Oy        0x18 Oz
0x20 fwd_x     0x24 fwd_y     0x28 fwd_z
0x30 right_x   0x34 right_y   0x38 right_z
0x40 up_x      0x44 up_y      0x48 up_z
```

All camera values are signed Q2.13 in the low 16 bits. The PS should write all
shadow registers first, then write `1` to `0x00`. The PL copies the full camera
state into the live renderer only at `sx=0, sy=0`, so each frame uses one
consistent camera pose.

Example PYNQ usage:

```python
from camera_control import CameraControl

cam = CameraControl(base_addr=0x43C00000)  # use your Address Editor value
cam.write_yaw_pitch(
    position=(-0.35, -0.35, 0.45),
    yaw_deg=45,
    pitch_deg=-45,
)
```

The renderer latency is assumed to be 77 pixel-clock cycles. `ray_renderer_core_axi`
delays `hsync`, `vsync`, and data-enable by that amount so the video control
signals line up with the RGB output from `ray_unit`.

## Mock Heightmap

`heightmap_bram.sv` now initializes itself by default. With `USE_MOCK_DATA=1`,
each inferred BRAM powers up with a small synthetic terrain: a low hill and a
central plateau. This removes the Vivado `mem does not have driver` warning and
lets the HDMI renderer produce a visible image before a real map-loading path
exists.

To use an external hex file later, instantiate `heightmap_bram` with:

```systemverilog
.USE_INIT_FILE (1'b1),
.INIT_FILE     ("heightmap_64x64.hex"),
.USE_MOCK_DATA (1'b0)
```

The hex file should contain one signed 16-bit value per line, in row-major
`{y, x}` address order. For the current `GRID_N=64`, that is 4096 lines.
