# D4S48 Low-DSP Package

This folder is a source-only package of the optimized 48-step Design4 renderer.
It is intended to be copied or checked out onto another branch and integrated
into a larger HDMI or VDMA pipeline without carrying Vivado generated output.

## Contents

- `src/`: renderer HDL, HDMI top wrapper, 640x480 timing, and heightmap BRAM
- `constraints/`: PYNQ-Z1 HDMI pin constraints
- `tb/`: smoke and HDMI wrapper testbenches
- `scripts/`: package-relative Vivado project/build scripts
- `filelist.f`: ordered HDL source list
- `MANIFEST.txt`: copied source inventory and verification snapshot

## Build Standalone HDMI Design

From the repository root:

```powershell
vivado -mode batch -source packages/d4s48_lowdsp/scripts/create_project.tcl -tclargs -force
vivado -mode batch -source packages/d4s48_lowdsp/scripts/build_bitstream.tcl
```

If Vivado cannot find `rgb2dvi`, pass the Digilent Vivado library explicitly:

```powershell
vivado -mode batch -source packages/d4s48_lowdsp/scripts/create_project.tcl -tclargs -force -ip_repo D:/ic/vivado-library-master/ip
```

The generated project is written under `packages/d4s48_lowdsp/vivado_project_d4s48_lowdsp/`
and should remain untracked.

## Integration Notes

- HDMI top: `src/ray_unit_hdmi_top_d4s48.sv`
- Renderer core: `src/ray_unit4.sv`
- Input clock: PYNQ-Z1 125 MHz PL clock
- Clock wizard outputs: 25 MHz pixel, 125 MHz TMDS serial, 100 MHz renderer core
- `rgb2dvi_0` must use external `PixelClk` and `SerialClk`
- Renderer latency: 590 core cycles
- HDMI delay: 148 pixel clocks plus 8 FIFO priming pixels, total 156 pixels
- Throughput: one pixel per four 100 MHz core cycles, matching 25 MHz HDMI
- Resource target: 57 DSPs after bilinear interpolation DSP sharing

For a larger pipeline, instantiate `ray_unit4` directly if another module owns
frame timing, buffering, or HDMI. Use the BRAM interface arrays from
`ray_unit_hdmi_top_d4s48.sv` as the reference wiring for the 48 marcher BRAM
copies and 2 normal BRAM copies.
