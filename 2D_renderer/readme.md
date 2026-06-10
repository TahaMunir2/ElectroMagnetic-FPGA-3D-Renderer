# 2D Contour Renderer — drop-in replacement for the D4S48 ray unit

Verified with Verilator 5.020: full 640×480 raster vs Python golden model,
**307,200 / 307,200 pixels exact, 0 mismatches**, for both RD_LAT=1 and RD_LAT=2.

## Files
- `contour_unit.sv`      — the IP. Mirrors ray_unit4's pixel contract, camera/
                           lighting ports removed, ONE BRAM read port.
- `contour_hdmi_top.sv`  — standalone top. Copy of ray_unit_hdmi_top_d4s48 with
                           the ray unit + 50 BRAMs swapped for contour_unit + 1.
- `contour_golden.py`    — generates heightmap.hex + golden.txt (bit-exact).
- `tb_contour_unit.sv`   — Verilator self-checking testbench.
- `heightmap_bram_sim.sv`— 1-cycle sim BRAM (your real one replaces it on HW).
- `contour_preview.png`  — what the golden output looks like.

## Compute
pixel → cell (reciprocal-mult-shift, divider-free) → 1 BRAM read →
offset-binary top-4-bits → 16-entry palette case → RGB. 1 pixel/cycle.

## Latency (must match the wrapper's video delay)
LAT = RD_LAT + 2 core cycles (addr reg + BRAM read + output reg).
- RD_LAT=1 (simple `dout<=mem[addr]` BRAM) → LAT=3
- RD_LAT=2 (BRAM with output register)     → LAT=4
The wrapper sets VIDEO_DELAY_PIX from this. **Check your heightmap_bram's read
latency and set RD_LAT to match, or the image shifts one cell horizontally.**

## Run the sim
    python3 contour_golden.py
    verilator --binary --timing -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
        --top-module tb_contour_unit \
        contour_unit.sv heightmap_bram_sim.sv tb_contour_unit.sv -o sim
    ./obj_dir/sim

## Vivado: unwire 3D, wire 2D (for a clean standalone test)
1. In the block design, the pixel_generator currently wraps the ray unit. For a
   pure 2D test, set `contour_hdmi_top` as the top (or repackage the IP around
   contour_unit). Leave the VDMA/HDMI-out half of the block design untouched —
   you only own the generator.
2. Remove the ray_unit4 instance and its 48 marcher + 2 normal heightmap_bram
   instances. Add ONE heightmap_bram, fed by contour_unit (already wired in
   contour_hdmi_top.sv).
3. Point the single heightmap_bram at the SAME init data the 3D renderer used,
   so both views show the same terrain.
4. Set RD_LAT in contour_hdmi_top.sv to your BRAM's read latency.
5. Synthesise. Expect a fraction of the ray unit's resources: no marcher chain,
   no normals, 1 BRAM. (3D baseline for reference: 13,176 LUT / 49 BRAM /
   153 DSP. The contour unit is ~a few hundred LUT, 1 BRAM, ~2 DSP.)

## Note on look
Nearest-cell on a 64×64 grid scaled to 640×480 = 10px blocks (visible in the
preview). That's expected for a minimap. Smoother contours = bilinear (4 reads),
deferred. The palette is a `case` — feed it from AXI-Lite to make it UI-swappable.
