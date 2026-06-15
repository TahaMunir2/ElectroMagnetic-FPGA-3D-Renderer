# PML Integration — Developer Notes

**Author**: Taha  
**Affects**: `fdtd_solver.sv`, `fdtd_engine.sv`, `Ey.sv`, `Ex.sv`, `Bz.sv`  
**New file**: `src/hdl/pml.sv`

---

## What changed and why

Previously the solver used two global constants `C_E` and `C_B` (Q3.13 fixed-point) applied identically to every cell. This caused waves to reflect off the grid boundaries.

UPML (Uniaxial Perfectly Matched Layer) fixes this by replacing those constants with position-dependent coefficients. Cells near the boundary get a damping factor that progressively absorbs the wave, preventing reflections. The 6 outermost rows and columns on each side are the PML region.

**`C_E` and `C_B` have been removed as ports from `fdtd_solver`, `top_fdtd_system`, and `top_fdtd_hardware_wrapper`.** The adapter (`fdtd_solver_bd_adapter.v`) has been updated accordingly — remove those ports from any Vivado block design connections that previously drove them.

---

## New module: `pml.sv`

```
src/hdl/pml.sv
```

A combinational ROM. Given a depth `d` (0 = innermost PML edge, 5 = outermost wall), outputs the corresponding Q3.13 coefficients.

### Port list

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `d` | input | `[CELL_WIDTH-1:0]` | Depth into PML layer (0–5) |
| `ca` | output | `[DATA_WIDTH-1:0]` | Decay coefficient (Q3.13) |
| `cb_e` | output | `[DATA_WIDTH-1:0]` | E-field curl coefficient (Q3.13, negative) |
| `cb_bz` | output | `[DATA_WIDTH-1:0]` | Bz curl coefficient (Q3.13, negative) |

### Coefficient table

| d | ca | cb_e | cb_bz | Notes |
|---|-----|------|-------|-------|
| 0 | 8192 | −717 | −2867 | Innermost — identical to old C_E/C_B |
| 1 | 7862 | −703 | −2809 | |
| 2 | 6949 | −663 | −2649 | |
| 3 | 5637 | −605 | −2420 | |
| 4 | 4141 | −540 | −2158 | |
| 5 | 2635 | −474 | −1895 | Outermost — max damping |

All values are Q3.13 fixed-point (1.0 = 8192). At `d=0`, `ca=8192` means no decay — interior cells are unaffected. At `d=5`, `ca=2635` ≈ 0.32, so fields lose ~68% per cycle near the wall.

`pml.sv` is purely combinational — no clock, no state.

---

## How it fits into the hierarchy

```
fdtd_solver
├── pml_ey  (pml.sv)  — d_ey  → ca_ey,  cb_ey
├── pml_ex  (pml.sv)  — d_ex  → ca_ex,  cb_ex
├── pml_bz  (pml.sv)  — d_bz  → ca_bz,  cb_bz
└── fdtd_engine
    ├── u_ey (Ey.sv)  — ca_ey, cb_ey
    ├── u_ex (Ex.sv)  — ca_ex, cb_ex
    └── u_bz (Bz.sv)  — ca_bz, cb_bz
```

Three `pml` instances run in parallel inside `fdtd_solver`, one per field component. The depth inputs `d_ey`, `d_ex`, `d_bz` are computed each cycle from the current write cell's row/column position:

- `d_ey` — based on row (Ey is damped by proximity to top/bottom walls)
- `d_ex` — based on column (Ex is damped by proximity to left/right walls)
- `d_bz` — `max(d_ey, d_ex)` (whichever wall is closest)

---

## What changed in the existing modules

### `Ey.sv`, `Ex.sv`, `Bz.sv`

`C_E` and `C_B` hardcoded constants replaced by `ca` and `cb` input ports. The update equations are now:

```
Ey_new = ca * Ey_old + cb * (Bz_right - Bz_left)
Ex_new = ca * Ex_old - cb * (Bz_right - Bz_left)   // cb is negative so this adds
Bz_new = ca * Bz_old + cb * ((Ey_right - Ey_left) - (Ex_right - Ex_left))
```

No change to port names for clk, field values, or write outputs.

### `fdtd_engine.sv`

Removed `C_E`, `C_B` inputs. Added six inputs: `ca_ey`, `cb_ey`, `ca_ex`, `cb_ex`, `ca_bz`, `cb_bz`. Passes each pair down to the corresponding submodule.

### `fdtd_solver.sv`

- Added `PML_SIZE = 6` parameter
- Removed `C_E`, `C_B` from port list
- Instantiates three `pml` modules internally
- Computes `d_ey`, `d_ex`, `d_bz` from write address each cycle
- All BRAM-facing ports (`ey_rd_addr`, `bz_adj_rd_addr`, etc.) and control ports (`solver_enable`, `solver_done`) are unchanged

### `fdtd_solver_bd_adapter.v`

- Removed `C_E_Q313` and `C_B_Q313` localparam declarations
- Removed `.C_E()` and `.C_B()` from the `fdtd_solver` instantiation
- Everything else (BRAM port fanout, magnitude pass, checksum, source latch) is unchanged

---

## Vivado block design impact

The only change to external connections is the removal of `C_E` and `C_B`. If your block design had constant IP blocks driving those ports on the adapter or solver, delete those connections and the constants. No new external ports were added — the PML logic is entirely internal to `fdtd_solver`.

Files needed in Vivado project (add if not already present):
```
src/hdl/pml.sv
src/hdl/Ey.sv          (updated)
src/hdl/Ex.sv          (updated)
src/hdl/Bz.sv          (updated)
src/hdl/fdtd_engine.sv (updated)
src/hdl/fdtd_solver.sv (updated)
src/hdl/fdtd_solver_bd_adapter.v (updated)
```
