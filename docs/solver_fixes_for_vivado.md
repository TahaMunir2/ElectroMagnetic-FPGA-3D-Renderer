# FDTD Solver Fixes — Action Required for Vivado Rebuild

Two bugs in the solver were causing the visual artifacts on the HDMI output:
the cross/X haze around the source, and the "weird stuff at the lane
boundaries". Both are now fixed and verified in simulation on the `FDTD-MVP3`
branch. **These fixes are in `src/hdl/` only — the Vivado import copies have
NOT been touched.** They need to be ported before the next bitstream build.

---

## TL;DR — what you need to do

1. Copy the fixed versions of **`Ex.sv`, `Ey.sv`, `Bz.sv`, `fdtd_solver.sv`,
   `pml.sv`** from `src/hdl/` over the copies in
   `vivado/mvp2_fdtd_hdmi_quad/rtl/fdtd_quad_import/`.
2. Be aware of **one timing change**: an iteration is now **2052 cycles
   instead of 2048**, and `solver_done` fires 4 cycles later. The free-run FSM
   in the adapter does not care (it waits on `solver_done`), but anything that
   counts a fixed number of cycles must be updated.
3. Re-package the IP and rebuild.

---

## Bug 1 — Biased truncation (caused the X / cross haze)

**Files:** `Ex.sv`, `Ey.sv`, `Bz.sv`

The Q3.13 fixed-point multiply renormalises by taking bits `[28:13]` of the
32-bit product. That slice is a **floor** (rounds toward negative infinity),
so every multiply added a small sign-biased error. In the interior `ca = 1.0`
exactly, so there is no loss to wash the error out, and it accumulated
iteration after iteration, smearing a DC residue across the grid in scan
order. With the slow wave this residue dominated and showed up as the X-shaped
haze.

**Fix:** add half an LSB before the slice (round-to-nearest). In each of the
three files, the two truncation assignments now read:

```systemverilog
wire signed [2*FP_WIDTH:0] <f>_ca_rounded = <f>_ca_untruncated + (1 <<< (FRAC_BITS-1));
wire signed [2*FP_WIDTH:0] <f>_cb_rounded = <f>_cb_untruncated + (1 <<< (FRAC_BITS-1));
assign <f>_ca_truncated = $signed(<f>_ca_rounded[FRAC_BITS+FP_WIDTH-1:FRAC_BITS]);
assign <f>_cb_truncated = $signed(<f>_cb_rounded[FRAC_BITS+FP_WIDTH-1:FRAC_BITS]);
```

(`<f>` is `ex`, `ey`, or `bz`.)

**Result:** a single source pulse now propagates as a clean symmetric circle,
and the quad-lane design is numerically near-identical to a single-solver
reference (was 1110 mismatched cells, now ~10, all buried in the deepest PML
column where the field is visually zero).

---

## Bug 2 — Last 4 cells of each phase never written (caused the lane-seam artifacts)

**File:** `fdtd_solver.sv`

The solver masks the first 4 cycles of each phase with `write_valid` to account
for the 4-cycle read-to-write pipeline latency (1 cycle BRAM read + 3 engine
stages). The problem: the writes for the **last 4 cells** of the E phase would
land in the first 4 cycles of the B phase, where the logic has already switched
to writing Bz, so they never happened. Same for the last 4 Bz cells at the end
of the iteration.

Each lane therefore had **4 permanently-frozen cells at its last row** (columns
60-63). In the old single-lane design those sat in the bottom boundary row and
were invisible. In the multi-lane design they sit at **every lane seam** — and
because they are hard zeros, they reflect the wave. That is the lane-boundary
weirdness.

**Fix:** the write phase is now derived from `counter - 4` rather than
`counter`, and the counter runs 4 cycles longer so the pipeline drains fully.
Key changes:

- iteration length: `2*GRID_SIZE` → `2*GRID_SIZE + 4` cycles
- `solver_done` now asserts at `counter == TWO_GRID_SIZE + 3`
- new internal signals `wr_counter`, `e_write_phase` decouple the write
  address/phase from the read address

**Result:** the frozen seam cells now carry live field values; the lane
boundaries are continuous.

---

## Constants retune (`pml.sv` + `top_fdtd_hardware_wrapper.sv`)

While verifying the fixes we found the old `cb = -6` could not propagate a wave
at all: the coupling term `6*dBz/8192` is under half an LSB for any normal
field value, so it rounded to zero. The "wave" previously seen was largely the
truncation artifact moving — once that was fixed, the real wave stalled.

New operating point (already applied in `src/hdl/`):

| Constant | Old | New |
|----------|-----|-----|
| `cb_e`, `cb_bz` | −6 | **−717** |
| `PHASE_STEP` (wrapper) | 0x0005 | **0x01C2** (450) |
| PML `ca` ramp | 8192−d³ | **8192 − 18.4·d³** (8192, 8174, 8045, 7695, 7014, 5892) |

This gives a Courant number S ≈ 0.0875 (8× inside the CFL limit of 1/√2,
~1400× above the quantisation floor), wavelength ≈ 10 cells, and a PML
attenuation of about −113 dB.

**Note on the PS source address / phase step:** if the phase step is driven
from the PS (GPIO) in your build rather than the `PHASE_STEP` localparam, set
it to **450** there. Wavelength scales as `2π·|cb|/PHASE_STEP`, so if you
change `cb` you must rescale the phase step to keep λ ≈ 10 cells.

**Demo tuning (not a bug):** driving the source continuously at high amplitude
fills the box faster than the PML can bleed it. Keep the source amplitude
modest, or inject the source on fewer iterations per displayed frame, to get
clean rings rather than a saturated grid.

---

## Verification status

- `tests/tb_top_fdtd_quad_lane.sv` and `tests/tb_top_fdtd_hex_lane.sv` both pass
  (`ok`) with the new constants and the 2052-cycle iteration.
- Single-pulse propagation is a clean symmetric circle.
- Lane-seam cells are alive and continuous.
- Quad-lane is numerically near bit-exact with a single-solver reference.

The two testbenches' cycle-count assertions were updated to `2*GRID_SIZE + 4`,
and their halo checks were rewritten to verify cross-seam propagation in one
iteration.

---

## Files changed (all in `src/hdl/` and `tests/`, none in `vivado/`)

```
src/hdl/Ex.sv                        round-to-nearest truncation
src/hdl/Ey.sv                        round-to-nearest truncation
src/hdl/Bz.sv                        round-to-nearest truncation
src/hdl/fdtd_solver.sv               pipeline-drain write fix (+4 cycles)
src/hdl/pml.sv                       new cb = -717, cubic ca ramp
src/hdl/top_fdtd_hardware_wrapper.sv PHASE_STEP = 0x01C2
tests/tb_top_fdtd_quad_lane.sv       cycle assertion + halo check
tests/tb_top_fdtd_hex_lane.sv        cycle assertion + halo check
```
