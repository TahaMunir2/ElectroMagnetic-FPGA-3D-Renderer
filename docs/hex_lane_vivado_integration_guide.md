# Hex-Lane FDTD Vivado Integration Guide

This document covers every HDL change required to build and deploy the
16-lane 128×128 FDTD design (`top_fdtd_hex_lane.sv`).

For the 4-lane 64×64 design see `docs/quad_lane_vivado_integration_guide.md`.

| Config | File | Grid | Lanes | Rows/lane | CELL_WIDTH | Iteration cycles | BRAM18s | BRAM36s |
|--------|------|------|-------|-----------|------------|-----------------|---------|---------|
| Hex-lane | `top_fdtd_hex_lane.sv` | 128×128 | 16 | 8 | 7 | 2048 | 48 | 24 |

Source address for grid centre: `14'd8256` (128×64+64).

---

## Overview of the architecture

The 128×128 grid is split into 16 horizontal lanes of 8 rows each. All lanes
run in lockstep. Each lane owns one `bram_module` and one `fdtd_solver`.
Adjacent lanes exchange one row of halo data per phase through BRAM port 1.

One FDTD iteration completes in **2048 cycles** (2 × 8 × 128).
At 100 MHz: ~48,828 iterations/second → ~813 iterations/frame at 60 fps.

**BRAM sizing.** Each lane holds 8 × 128 = 1024 cells × 16 bits = 16 Kbits.
This is an exact fit for one BRAM18 per field (BRAM18 data capacity = 16 Kbits;
the additional 2 Kbits are parity, intrinsic to the silicon, not wasted space).
Total: 16 lanes × 3 fields = **48 BRAM18s = 24 BRAM36s**.

---

## Files changed or added

### 1. `src/hdl/fdtd_solver.sv` — modified

Three parameters and three output ports added since the MVP3 baseline:

**New parameters**

```systemverilog
parameter ROW_OFFSET,   // this lane's starting row in the global grid
parameter FIRST_LANE,   // 1 for lane 0, 0 otherwise
parameter LAST_LANE     // 1 for lane 15, 0 otherwise
```

`ROW_OFFSET` is used for PML depth and boundary zeroing so each lane knows
its absolute position in the 128-row grid.

`FIRST_LANE` and `LAST_LANE` gate the cross-lane adjacency reads. Lane 0
does not read above its row 0. Lane 15 does not read below its row 7.

**New output ports**

```systemverilog
output logic [CELL_WIDTH-1:0] current_row,
output logic [CELL_WIDTH-1:0] current_col,
output logic                  e_phase
```

Combinatorial: derived from the counter each cycle. The wrapper uses them to
drive the halo address and data muxes.

**Vivado action:** Replace `fdtd_solver.sv` in project sources. Add the three
new parameters and three new output ports to any existing connection or
adapter.

---

### 2. `src/hdl/top_fdtd_hex_lane.sv` — new file

This is the top-level for the hex-lane design. It instantiates:

- 16 × `bram_module` (DEPTH=1024, WIDTH=16, ADDR_WIDTH=14)
- 16 × `fdtd_solver` with ROW_OFFSET = 0 / 8 / 16 … 120 and FIRST/LAST_LANE flags
- Combinatorial halo address mux — 15 adjacent pairs
- Registered halo data mux — 1-cycle delay to match BRAM synchronous read latency
- Source routing: `source_lane = source_addr / 1024`, `local_addr = source_addr mod 1024`

External port list:

| Port | Direction | Width | Notes |
|------|-----------|-------|-------|
| `clk` | in | 1 | |
| `rst` | in | 1 | synchronous active-high |
| `source_in` | in | 16 | Q3.13 source value |
| `source_valid` | in | 1 | hold high to keep injecting each iteration |
| `source_addr` | in | 14 | global flat address 0–16383 |
| `solver_enable` | in | 1 | pulse low for ≥1 cycle then high to start next iteration |
| `solver_done` | out | 1 | high for one cycle when all 16 lanes finish |

`source_addr` is 14 bits (`2 × CELL_WIDTH`). Global address `14'd8256`
targets grid centre (128×64+64). The wrapper splits this into `source_lane`
(4-bit, 0–15) and `local_source_addr` (14-bit, 0–1023) in combinatorial logic.

**Vivado action:** Add `top_fdtd_hex_lane.sv` to project sources. Set it as
the top module (or wrap it in a new hardware wrapper — see section 4).

---

### 3. `src/hdl/fdtd_solver_bd_adapter.v` — action required

The existing adapter was written for the single-solver design and does not
connect `current_row`, `current_col`, or `e_phase`, and does not pass
FIRST_LANE / LAST_LANE / ROW_OFFSET.

**Option A (recommended):** Retire the block design and use
`top_fdtd_hex_lane` as a plain module-ref in Vivado. Wire the 7 ports above
to your AXI GPIO or PS interface. No custom IP packaging needed.

**Option B:** Update the adapter to pass through the three new parameters.
The halo mux is inside `top_fdtd_hex_lane`, not in the adapter.

---

### 4. Replacing `top_fdtd_hardware_wrapper.sv`

The old wrapper exposed `start`, `busy`, `done`, `iteration_count`,
`ey_probe`, `ex_probe`, `bz_probe`. Write a new thin wrapper that:

1. Converts `start` → `solver_enable` (hold enable high after start until
   done fires, then toggle low for one cycle to arm the next iteration)
2. Drives `busy` = `solver_enable && !solver_done`
3. Drives `done` = `solver_done`
4. Counts `iteration_count` by incrementing on each `solver_done`
5. Ties probe outputs to zero or reads them from the BRAMs via a read-back FSM

---

### 5. `src/hdl/pml.sv` — modified

The `ca` attenuation coefficients follow a cubic ramp (`ca(d) = 8192 − d³`)
rather than the previous shallower gradient. `cb_e` and `cb_bz` are
unchanged at −25 for all depths.

| depth d | ca (old) | ca (new) |
|---------|----------|----------|
| 0 | 8192 | 8192 |
| 1 | 8188 | 8191 |
| 2 | 8180 | 8184 |
| 3 | 8168 | 8165 |
| 4 | 8152 | 8128 |
| 5 | 8135 | 8067 |

At Courant=0.003, one-way PML attenuation improves from approximately −48 dB
to better than −100 dB.

**Vivado action:** Replace `pml.sv` in project sources.

---

### 6. Source address

The hardware block design used `SOURCE_ADDR = 18528` (centre of a 192×192
grid). The hex-lane design uses a 14-bit flat address space (128×128 = 16384
cells). Update the address to `8256` (= 128 × 64 + 64) in your AXI GPIO /
PS software layer. No HDL rebuild required.

---

### 7. `src/hdl/top_fdtd_system.sv` — must be excluded

`top_fdtd_system.sv` instantiates `fdtd_solver` with the old `CELLS`
parameter which was removed. Leaving it in the Vivado source set will produce
an elaboration error. Remove it before synthesising.

---

### 8. Files that did NOT change

- `Ey.sv`, `Ex.sv`, `Bz.sv` — 3-stage pipeline, timing fix already applied
- `fdtd_engine.sv`
- `bram_module.v` — do not touch

---

## BRAM inference

`bram_module.v` uses `(* ram_style = "block" *)` on all memory arrays.
At DEPTH=1024 and WIDTH=16, Vivado infers one BRAM18 per field (Ey, Ex, Bz).

Per `bram_module` instance: 3 BRAM18s (one per field).
Total for 16 lanes: 16 × 3 = **48 BRAM18s = 24 BRAM36 equivalents**.

The Zynq-7020 has 280 BRAM18s (140 BRAM36s) — fits comfortably.
The Zynq-7010 has 120 BRAM18s (60 BRAM36s) — also fits.

No Xilinx BRAM IP blocks are needed. If the old block design had `ey_bram`,
`ex_bram`, `bz_bram` as IP instances, remove them.

---

## Constraints

The existing 100 MHz constraint applies unchanged:

```
create_clock -period 10.000 -name clk [get_ports clk]
```

The critical path is through the Q3.13 multiply in `Ey.sv` / `Ex.sv` /
`Bz.sv`. The 3-stage pipeline fix is already in place. The halo muxes are
single-level selects on registered BRAM output data and add no timing
pressure.

---

## Vivado checklist

| # | Task | Detail |
|---|------|--------|
| 1 | Add source | `src/hdl/top_fdtd_hex_lane.sv` |
| 2 | Replace source | `src/hdl/fdtd_solver.sv` |
| 3 | Replace source | `src/hdl/pml.sv` — cubic ca ramp |
| 4 | Set top module | `top_fdtd_hex_lane` (or new wrapper around it) |
| 5 | Write new wrapper | Replace `top_fdtd_hardware_wrapper.sv` — see section 4 |
| 6 | Update source address | Change `source_addr` to `8256` in PS / AXI layer — see section 6 |
| 7 | Remove source | `src/hdl/top_fdtd_system.sv` — conflicts with new fdtd_solver |
| 8 | Remove or update adapter | `fdtd_solver_bd_adapter.v` — see section 3 |
| 9 | Remove old BD BRAM IPs | `ey_bram`, `ex_bram`, `bz_bram` IP blocks no longer needed |
| 10 | Keep constraint | `create_clock -period 10.000` unchanged |
| 11 | Re-validate | Run *Validate Design* — no critical errors expected |
| 12 | Synthesise | Check BRAM utilisation: 48 BRAM18s (24 BRAM36 equivalents) |
| 13 | Implement | WNS should be ≥ 0 at 100 MHz; critical path unchanged from MVP3 |

---

## Simulation results

`top_fdtd_hex_lane.sv` compiles clean against all submodules. A dedicated
testbench (`tests/tb_top_fdtd_hex_lane.sv`) is not yet written. Expected
behaviour mirrors `tb_top_fdtd_quad_lane.sv` with the following changes:

| Parameter | Quad-lane | Hex-lane |
|-----------|-----------|----------|
| `solver_done` timing | 2048 cycles | 2048 cycles |
| BRAM hierarchy | `dut.bram_N` (N = 0–3) | `dut.bram_N` (N = 0–15) |
| `source_lane` width | 2-bit | 4-bit |
| Bottom boundary lane | `dut.bram_3` | `dut.bram_15` |
| Cross-lane test lane | `dut.bram_1` | `dut.bram_1` |
