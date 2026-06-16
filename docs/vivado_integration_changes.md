# FDTD Solver — Vivado Integration Changes

## Modified files

- `src/hdl/fdtd_solver.sv`
- `src/hdl/top_fdtd_quad_lane.sv`

---

## New ports

Both modules now have three new inputs at the end of their port lists. These need to be connected in the block design to AXI-lite registers (or GPIO) driven from the PS.

| Port | Width | Module |
|------|-------|--------|
| `preset` | `[1:0]` | both |
| `slit_w` | `[3:0]` | both |
| `cb_mat` | `signed [15:0]` | both |

`top_fdtd_quad_lane` fans all three out to all four `fdtd_solver` instances internally — only the top-level module needs to be connected in Vivado.

---

## What each port does

### `preset [1:0]` — wall / experiment select

Controls which wall configuration is active on the left half of the grid (column 32).

| Value | Behaviour |
|-------|-----------|
| `2'd0` | No wall — free propagation |
| `2'd1` | Single slit centred at row `TOTAL_ROWS/2`, half-width `slit_w` |
| `2'd2` | Double slit at rows `TOTAL_ROWS/4` and `3*TOTAL_ROWS/4`, half-width `slit_w` |
| `2'd3` | Diffraction grating — period 8 rows, opening width `slit_w[2:0]` cells |

The wall is a PEC boundary (Ex = Ey = 0) at column `COLUMNS/2`. Slits are gaps where the field updates normally.

### `slit_w [3:0]` — slit half-width in grid cells

Controls the opening size for presets 1–3. The full slit spans `2 × slit_w + 1` cells for presets 1 and 2. For preset 3 (grating) it controls the number of open cells per period-8 window directly (`wr_row[2:0] < slit_w[2:0]`).

Recommended starting value: `4'd4` (9-cell opening for single/double, 4-cell opening for grating). Increase to spread the diffraction pattern, decrease to narrow it.

### `cb_mat signed [15:0]` — right-half permittivity coefficient

Sets the FDTD `cb` coefficient for all cells with column ≥ `COLUMNS/2`. This implements a vertical dielectric interface at the grid centre. The value is Q3.13 signed fixed-point.

| εr | `cb_mat` value |
|----|----------------|
| 1 (free space, no refraction) | `-16'sd717` |
| 2 | `-16'sd358` |
| 4 | `-16'sd179` |
| 8 | `-16'sd90` |

Formula: `cb_mat = round(-717 / εr)`

Only `cb_ey` and `cb_ex` are switched — `cb_bz` is unaffected (Faraday's law has no εr dependence).

---

## Block design wiring

All three ports should be driven from a single AXI-lite slave register block (e.g. `axi_gpio` or a custom AXI4-Lite slave). Suggested register map:

| Register offset | Signal | Notes |
|-----------------|--------|-------|
| `0x00` | `preset` | lower 2 bits |
| `0x04` | `slit_w` | lower 4 bits |
| `0x08` | `cb_mat` | full 16-bit signed value |

The PS writes to these registers from the Jupyter notebook to switch experiments at runtime.
