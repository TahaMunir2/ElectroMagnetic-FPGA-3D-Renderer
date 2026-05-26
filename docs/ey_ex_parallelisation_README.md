# Ey/Ex Parallelisation — Theory and Implementation Plan

---

## Background: current sequential structure

Each iteration runs three sequential passes, one cell per clock:

```
Phase 1 — Ey update:  counter 0         to GRID-1        (36,864 cycles)
Phase 2 — Ex update:  counter GRID       to 2*GRID-1      (36,864 cycles)
Phase 3 — Bz update:  counter 2*GRID     to 3*GRID-1      (36,864 cycles)
─────────────────────────────────────────────────────────────────────────
Total per iteration:                                      110,592 cycles
```

The Bz pass must wait for both Ey and Ex to finish because it reads their
new values. But the question is: does the Ey pass need to finish before Ex
starts?

---

## Why Ey and Ex can run simultaneously

The 2D TM-mode update equations are:

```
Ey[i,j]^(n+1) = ca_ey * Ey[i,j]^n  +  cb_ey * (Bz[i,j]^n   - Bz[i-1,j]^n)
Ex[i,j]^(n+1) = ca_ex * Ex[i,j]^n  -  cb_ex * (Bz[i,j]^n   - Bz[i,j-1]^n)
Bz[i,j]^(n+1) = ca_bz * Bz[i,j]^n  +  cb_bz * ((Ey[i+1,j]^(n+1) - Ey[i,j]^(n+1))
                                                - (Ex[i,j+1]^(n+1) - Ex[i,j]^(n+1)))
```

Looking at the Ey and Ex equations:

| | Reads from | Writes to |
|--|-----------|-----------|
| Ey update | Ey^n, Bz^n | Ey^(n+1) |
| Ex update | Ex^n, Bz^n | Ex^(n+1) |

**Neither reads from the other.** Ey reads its own old values and old Bz.
Ex reads its own old values and old Bz. They share nothing on the read side
and write to entirely separate BRAMs. They are completely independent and
can run at the same time.

Bz is the serialisation point — it needs Ey^(n+1) and Ex^(n+1), so it must
wait for both. But if Ey and Ex finish together, Bz can start immediately
after with no extra delay.

---

## New iteration structure

```
Phase 1 — Ey + Ex update:  counter 0     to GRID-1    (36,864 cycles)
Phase 2 — Bz update:        counter GRID  to 2*GRID-1  (36,864 cycles)
────────────────────────────────────────────────────────────────────────
Total per iteration:                                    73,728 cycles
```

**1.5× speedup, zero extra hardware cost.** The compute units for Ey and Ex
(`u_ey`, `u_ex`) already exist inside `fdtd_engine` and are already running
every cycle — they are just being ignored on the wrong phase. The only
changes are to control logic and one engine port split.

---

## BRAM port analysis

The merged E-field pass must supply both engines simultaneously. Here is
what each needs at cell (i, j):

| Signal | Ey needs | Ex needs | How supplied |
|--------|----------|----------|--------------|
| field old value | Ey[i,j] from Ey BRAM port A | Ex[i,j] from Ex BRAM port A | separate BRAMs, no conflict |
| bz_right | Bz[i,j] from Bz BRAM port A | Bz[i,j] from Bz BRAM port A | **same address** — shared read |
| bz_left | Bz[i-1,j] via Bz BRAM port B (adj) | Bz[i,j-1] = `prev_bz` register | **no extra port needed for Ex** |
| write destination | Ey BRAM | Ex BRAM | separate BRAMs, no conflict |

`prev_bz` is already a registered copy of the previous cycle's `bz_rd_dout`.
Since the scan is sequential across cells, on the cycle processing cell (i,j),
`prev_bz` holds Bz[i,j-1] — which is exactly Ex's bz_left. This is already
how the current Ex pass works; it doesn't change in the merged pass.

All reads and writes fit within the existing 2-port-per-BRAM structure. No
additional BRAM ports are required.

---

## The one required engine change

Currently `fdtd_engine` has a single `bz_left` port that feeds both `u_ey`
and `u_ex`:

```
bz_left ──┬──► u_ey.bz_left
           └──► u_ex.bz_left
```

In the merged pass these need different values:

```
bz_left_ey = Bz[i-1,j]   (row above  — from bz_adj port)
bz_left_ex = Bz[i,j-1]   (col to left — from prev_bz register)
```

`bz_left` must be split into two separate inputs:

```
bz_left_ey ──► u_ey.bz_left
bz_left_ex ──► u_ex.bz_left
```

This is the only structural change to `fdtd_engine`. `u_bz` is unaffected —
it has its own `bz_left` input which continues to use `prev_bz` as before.

---

## Summary of changes needed per file

### `fdtd_engine.sv`
- Rename `bz_left` port → `bz_left_ey` and add new `bz_left_ex` port
- Wire `bz_left_ey` → `u_ey.bz_left`
- Wire `bz_left_ex` → `u_ex.bz_left`
- `u_bz.bz_left` continues to receive its own input (currently `bz_left` in the solver — keep as `engine_bz_left` driving `u_bz`)

### `fdtd_solver.sv`
- Change loop termination from `THREE_GRID_SIZE` to `TWO_GRID_SIZE`
- Merge phase 1 and phase 2 into a single phase:
  - Read `ey_rd_addr` and `ex_rd_addr` both = `cell_addr`
  - Read `bz_rd_addr` = `cell_addr` (shared)
  - Assert `bz_adj_rd_addr` = `cell_addr - CELLS` when `row != 0` (for Ey's bz_left)
  - Pass `bz_adj_dout` → `engine_bz_left_ey`, `prev_bz` → `engine_bz_left_ex`
  - Assert both `ey_we` and `ex_we` during this phase (with existing `write_valid` guard)
  - Apply boundary conditions for both Ey and Ex simultaneously
- Remap old phase 3 (Bz) to new phase 2: `counter >= GRID_SIZE`

### `fdtd_engine.sv` port update propagates to `fdtd_solver.sv`
- Replace `.bz_left(engine_bz_left)` with `.bz_left_ey(engine_bz_left_ey)` and `.bz_left_ex(engine_bz_left_ex)`

### Testbenches
- `tb_fdtd_solver.sv` Test 1: expected cycle count changes from `3*GRID` to `2*GRID`

### No changes needed
- `Ey.sv`, `Ex.sv`, `Bz.sv` — unchanged
- `pml.sv` — unchanged, three instances still work the same way
- `fdtd_solver_bd_adapter.v` — unchanged, `solver_done` still fires once per iteration
- BRAM module — unchanged, same port usage pattern

---

## Before and after at a glance

```
BEFORE                              AFTER
──────────────────────────          ──────────────────────────
cycle 0..36863   Ey pass            cycle 0..36863   Ey + Ex pass (merged)
cycle 36864..73727  Ex pass         cycle 36864..73727  Bz pass
cycle 73728..110591 Bz pass
                                    solver_done at cycle 73727
solver_done at cycle 110591         (was 110591)
```
