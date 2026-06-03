# Quad-Lane FDTD Vivado Integration Guide

This document covers every HDL change since the MVP3 baseline and gives exact
steps to update the Vivado project for the 4-lane parallel architecture.

---

## Overview of the architecture change

The single-solver 64×64 design (`top_fdtd_system` / `top_fdtd_hardware_wrapper`)
is replaced by a 4-lane wrapper (`top_fdtd_quad_lane`). The 64-row grid is split
into four 16-row lanes that run in lockstep. Each lane has its own `fdtd_solver`
and its own `bram_module`. Adjacent lanes exchange one row of halo data per
phase through BRAM port 1.

One FDTD iteration now completes in **2048 cycles** (2 × 16 × 64) instead of
8192 cycles (2 × 64 × 64). 4× speedup at the same clock frequency.

Total BRAM usage is **unchanged**: 4 lanes × 6 memories × 1 BRAM18 each = 24
BRAM18s, same as the single-solver design (1 bram_module × 6 memories × 4
BRAM18s each for a 4096-deep memory).

---

## Files changed or added since MVP3

### 1. `src/hdl/fdtd_solver.sv` — modified

Three additions:

**a) New parameters**

```systemverilog
parameter ROW_OFFSET,   // this lane's starting row in the global 64-row grid
parameter FIRST_LANE,   // 1 for lane 0, 0 otherwise
parameter LAST_LANE     // 1 for lane 3, 0 otherwise
```

`ROW_OFFSET` is used when computing PML depth and boundary zeroing so each lane
knows its absolute position in the 64-row grid.

`FIRST_LANE` and `LAST_LANE` gate the cross-lane adjacency reads. Lane 0 does
not read above its row 0 (no lane above it). Lane 3 does not read below its row
15 (no lane below it). Middle lanes always do cross-lane reads at both boundaries.

**b) New output ports**

```systemverilog
output logic [CELL_WIDTH-1:0] current_row,
output logic [CELL_WIDTH-1:0] current_col,
output logic                  e_phase
```

These are combinatorial: `current_row` and `current_col` are derived from the
counter each cycle; `e_phase` is high during the Bz/Ex half of the iteration
(counter ≥ GRID_SIZE). The wrapper uses them to drive the halo address and data
muxes.

**c) Adj read conditions updated**

The BRAM port 1 adj reads are now gated by FIRST/LAST_LANE in addition to the
row-boundary check. No change to port widths or timing.

**Vivado action:** Replace `fdtd_solver.sv` in project sources. If the existing
block design instantiates `fdtd_solver` directly via module-ref, add the three
new parameters and three new output ports to the connection. If it goes through
`fdtd_solver_bd_adapter.v`, see section 3 below.

---

### 2. `src/hdl/top_fdtd_quad_lane.sv` — new file

This is the new top-level. It instantiates:

- 4 × `bram_module` (DEPTH=1024, WIDTH=16, ADDR_WIDTH=12)
- 4 × `fdtd_solver` with ROW_OFFSET = 0 / 16 / 32 / 48 and FIRST/LAST_LANE flags
- Combinatorial halo address mux (overrides BRAM port 1 address at lane boundaries)
- Registered halo data mux (1-cycle delayed to match BRAM synchronous read latency)
- Source routing logic (divides the global source address into lane index and
  local address)

External port list:

| Port | Direction | Width | Notes |
|------|-----------|-------|-------|
| `clk` | in | 1 | |
| `rst` | in | 1 | synchronous active-high |
| `source_in` | in | 16 | Q3.13 source value |
| `source_valid` | in | 1 | hold high to keep injecting each iteration |
| `source_addr` | in | 12 | **global** flat address 0–4095 |
| `solver_enable` | in | 1 | pulse low for ≥1 cycle then high to start next iteration |
| `solver_done` | out | 1 | high for one cycle when all 4 lanes finish |

`source_addr` is global: the wrapper computes `source_lane = source_addr / 1024`
and `local_addr = source_addr mod 1024` in combinatorial logic. Drive the global
address from your AXI or FSM layer exactly as before.

**Vivado action:** Add `top_fdtd_quad_lane.sv` to project sources. Set it as the
top module (or wrap it in a new hardware wrapper — see section 4).

---

### 3. `src/hdl/fdtd_solver_bd_adapter.v` — action required

The existing adapter was written for the single-solver design. It does not
connect `current_row`, `current_col`, or `e_phase`, and it does not pass the
FIRST_LANE / LAST_LANE / ROW_OFFSET parameters.

Two options:

**Option A (recommended):** Retire the block design entirely and use
`top_fdtd_quad_lane` as a plain module-ref in Vivado. No custom IP packaging
needed. Wire the 7 ports listed above to your AXI GPIO or PS interface.

**Option B:** Update the adapter to pass through the three new parameters and
leave `current_row`, `current_col`, `e_phase` unconnected (tie them to open
outputs). The halo mux is inside `top_fdtd_quad_lane`, not in the adapter, so
this only matters if the adapter directly instantiates `fdtd_solver`. If the
adapter is just wrapping `top_fdtd_system`, the whole chain is replaced anyway.

---

### 4. Replacing `top_fdtd_hardware_wrapper.sv`

The old wrapper exposed `start`, `busy`, `done`, `iteration_count`, `ey_probe`,
`ex_probe`, `bz_probe`. None of those are on `top_fdtd_quad_lane`.

Write a new thin wrapper that:

1. Converts `start` → `solver_enable` (hold enable high after start until done
   fires, then toggle low for one cycle to arm the next iteration)
2. Drives `busy` = `solver_enable && !solver_done`
3. Drives `done` = `solver_done`
4. Counts `iteration_count` by incrementing on each `solver_done`
5. Ties probe outputs to zero or reads them from the BRAMs directly (see below)

The probe outputs require reading `bram_N.ey_mem_0[probe_addr]` after
`solver_done`. That requires either a separate read-back FSM or AXI BRAM
controller. This is unchanged in complexity from the MVP3 design.

---

### 5. Files that did NOT change

These are identical to the MVP3 build. Do not replace them:

- `Ey.sv`, `Ex.sv`, `Bz.sv` — 3-stage pipeline, timing fix already applied
- `fdtd_engine.sv`
- `pml.sv`
- `bram_module.v` — do not touch

---

## BRAM inference

`bram_module.v` uses `(* ram_style = "block" *)` on all six memory arrays.
Vivado will infer one BRAM18 per array (each is 1024 × 16 bits = 16 Kbits,
fits in a single BRAM18).

Per `bram_module` instance: 6 BRAM18s.
Total for 4 lanes: **24 BRAM18s**.

No Xilinx BRAM IP blocks are needed. Do not add them. If the old block design
had `ey_bram`, `ex_bram`, `bz_bram` as IP instances, they are replaced by the
inferred BRAMs inside `bram_module`.

---

## Constraints

The existing 100 MHz constraint applies unchanged:

```
create_clock -period 10.000 -name clk [get_ports clk]
```

The critical path is the same as MVP3 — through the Q3.13 multiply in `Ey.sv` /
`Ex.sv` / `Bz.sv`. The 3-stage pipeline fix from MVP3 is already in place.

With 4 lanes running in parallel there is no new combinatorial depth added. The
halo muxes are single-level selects on BRAM output data (registered), so they
add no timing pressure.

---

## Vivado checklist

| # | Task | Detail |
|---|------|--------|
| 1 | Add source | `src/hdl/top_fdtd_quad_lane.sv` |
| 2 | Replace source | `src/hdl/fdtd_solver.sv` |
| 3 | Set top module | `top_fdtd_quad_lane` (or new wrapper around it) |
| 4 | Write new wrapper | Replace `top_fdtd_hardware_wrapper.sv` — see section 4 |
| 5 | Remove or update adapter | `fdtd_solver_bd_adapter.v` — see section 3 |
| 6 | Remove old BD BRAM IPs | `ey_bram`, `ex_bram`, `bz_bram` IP blocks no longer needed |
| 7 | Keep constraint | `create_clock -period 10.000` unchanged |
| 8 | Re-validate | Run *Validate Design* — no critical errors expected |
| 9 | Synthesise | Check BRAM utilisation: expect 24 BRAM18s |
| 10 | Implement | WNS should be ≥ 0 at 100 MHz; critical path unchanged from MVP3 |

---

## Simulation results

All 9 testbench tests pass on `tests/tb_top_fdtd_quad_lane.sv`:

1. `solver_done` fires after exactly 2048 cycles
2. Source injection writes nonzero Ey at the correct address
3. Ey global row 0 forced to zero (PEC boundary)
4. Ey global row 63 forced to zero (PEC boundary)
5. Ex col 0 forced to zero across all lanes
6. Ex col 63 forced to zero across all lanes
7. Cross-lane propagation: lane 1 has nonzero Ey after 21 iterations
8. `solver_done` re-fires correctly on repeated iterations
9. `rst` halts the solver mid-run

Test 7 confirms the halo exchange is working — energy propagates from lane 0
into lane 1, which requires the Bz halo read from lane 0's BRAM port 1 and
the Ey halo read from lane 1's BRAM port 1 to both be correctly routed.
