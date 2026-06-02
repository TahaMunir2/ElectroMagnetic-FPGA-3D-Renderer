# D1S48 Renderer

`D1S48` is the 48-step copy of the Design 1 renderer. The marcher depth is
`N_STEPS=48`, so the renderer uses 48 marcher BRAM ports plus 4 normal BRAM
ports. With the 64x64 heightmap, this is 52 inferred heightmap BRAM instances.

Pipeline latency is `4 * N_STEPS + 14`, which is 206 cycles for this copy. HDMI
wrappers in this directory delay `hsync`, `vsync`, and data-enable by 206
pixel-clock cycles.

## Board Wrappers

- `D1_wrapper/design1_ray_unit_hdmi_top.sv` - direct HDMI wrapper.
- `D1_wrapper/d1s48_renderer_core_axi.sv` - PS-controlled camera wrapper for
  block-design use.
- `D1_wrapper/d1s48_renderer_core_axi_bd.v` - Verilog module-reference shim for
  Vivado block design.

## Vivado Projects

Generated projects are intentionally ignored by git:

```powershell
vivado -mode batch -source scripts/create_d1s48_vivado_project.tcl
vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl
```

The camera-control block design maps the renderer AXI4-Lite registers at
`0x40000000`.
