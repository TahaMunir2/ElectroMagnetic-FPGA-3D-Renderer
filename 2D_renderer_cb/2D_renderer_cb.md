# 2D Contour Renderer — runtime-writable palette (PYNQ-Z1)

Verified in Verilator 5.020:
- default palette: 307,200/307,200 pixels exact vs golden — PASS
- after writing a new palette through the port: 307,200/307,200 exact vs the
  new golden — PASS (proves the palette input recolours the output)
- RD_LAT=1 and RD_LAT=2 both alignment-verified

## What changed vs the previous version
The 16 colours were a hardcoded `case` baked into the bitstream. They are now a
**16×24-bit LUTRAM** with a write port `{pal_we, pal_idx, pal_rgb}`. Rewriting
those 16 entries recolours the entire 640×480 image instantly — no per-pixel
transform, no recompute. The PS pushes a colour-blindness-corrected palette.

## Files
HDL (synthesise these):
- `contour_unit.sv`          — renderer + writable palette LUTRAM + write port.
- `contour_palette_axil.sv`  — AXI4-Lite slave → palette write port (REAL system).
- `palette_loader.sv`        — no-PS preset cycler → palette write port (BOARD TEST).
- `contour_hdmi_top.sv`      — standalone top (uses palette_loader).
- `palettes.svh`             — generated preset palettes (P0/P1/P2).
- `heightmap_bram_sim.sv`    — SIM ONLY; on HW use your real heightmap_bram.

Verification / assets:
- `contour_golden.py`           — generates heightmap.hex, goldens, palettes.svh.
- `tb_contour_unit.sv`          — Verilator self-checking TB (default → write → recheck).
- `contour_preview.png`         — default rainbow output.
- `contour_cividis_preview.png` — cividis (accessible) output.

## AXI-Lite register map (contour_palette_axil)
Byte offset | name    | meaning
------------|---------|--------------------------------------------------------
0x00        | CONTROL | bit0 = mode (general purpose; e.g. 0=2D)        r/w
0x04        | PAL_WR  | write {idx[27:24], rgb[23:0]}; writes palette[idx].
            |         | rgb = {R[23:16], G[15:8], B[7:0]}. One write = one entry.
0x08..0x1C  | —       | reserved / future params (e.g. height bias)

PS pushes a palette:  for i in 0..15: poke(BASE+0x04, (i<<24)|(R<<16)|(G<<8)|B)

## Latency knob (must match the wrapper)
LAT = RD_LAT + 2 core cycles. Set `RD_LAT` in BOTH contour_unit and
contour_hdmi_top to your heightmap_bram read latency:
- 1 = simple `dout <= mem[addr]`
- 2 = with an output register
Wrong value shifts the image one cell horizontally.

## Run the sim
    python3 contour_golden.py
    verilator --binary --timing -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
        --top-module tb_contour_unit \
        contour_unit.sv heightmap_bram_sim.sv tb_contour_unit.sv -o sim
    ./obj_dir/sim

## Regenerate the bitstream in Vivado (same flow as before)
BOARD TEST (no PS — see the palette change on screen):
1. Add sources: contour_unit.sv, palette_loader.sv, palettes.svh,
   contour_hdmi_top.sv, your real heightmap_bram, and keep clk_wiz_1 / rgb2dvi_0.
2. Top = contour_hdmi_top. Remove the old ray_unit4 + its 50 heightmap_bram
   instances; this top instantiates ONE heightmap_bram, fed by contour_unit.
3. Point that heightmap_bram at the SAME init data the 3D renderer used.
4. Set RD_LAT to your BRAM read latency.
5. (optional) wire `sw[1:0]` to two board switches and set USE_SW=1 to pick the
   palette manually; otherwise it auto-cycles P0→P1→P2 (~1.3 s each).
6. Synthesise → bitstream. On HDMI you should see the contour map cycle through
   rainbow → cividis → viridis, proving the writable palette path end-to-end.

REAL SYSTEM (PS-driven palette — do the PS/UI wiring in your UI chat):
1. Delete u_loader. Instantiate contour_palette_axil instead; wire its
   {pal_we,pal_idx,pal_rgb} to u_contour and its AXI-Lite bus to the Zynq PS
   (run s_axi_aclk from the 100 MHz core clock).
2. Package as the pixel_generator IP if using the block-design/VDMA flow.
3. PS writes the palette per the register map above.

## Expected resources (sanity check after synth)
vs your 3D baseline (13,176 LUT / 49 BRAM / 153 DSP), the contour unit should be
a few hundred LUT, 1 BRAM, ~2 DSP, plus 16×24 bits of LUTRAM for the palette.
The AXI-Lite slave is tens of LUT. If it's much bigger, tell me the numbers.

## Note on look / accessibility
Nearest-cell on a 64×64 grid scaled to 640×480 = 10px blocks (a minimap).
cividis/viridis have monotonic luminance, so the map reads correctly under CVD
and in greyscale. For the report: validate each PS-computed palette by simulating
it back through the CVD model and showing the min inter-band ΔE increases vs the
rainbow ramp; and consider layering a non-colour channel (contour outlines from
the band index, or a numeric height readout) for low-vision users.
