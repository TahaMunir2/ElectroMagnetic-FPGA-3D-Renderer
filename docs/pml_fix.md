# PML Boundary Fix

## The symptom

With a point source at the centre of the grid, the circular wavefronts were clean in the interior but noisy at the left and right edges. The top and bottom edges were unaffected. The noise was Nyquist-frequency interference (alternating cells) caused by partial reflections from the left and right PML boundary layers.

---

## TE_z field equations

The 2D FDTD solver uses the TE_z mode with three field components: Ex, Ey, Bz. Their continuous-time update equations are:

```
∂Ey/∂t =  (1/ε) ∂Bz/∂x      — Ey driven by x-direction curl
∂Ex/∂t = −(1/ε) ∂Bz/∂y      — Ex driven by y-direction curl
∂Bz/∂t = −(∂Ey/∂x − ∂Ex/∂y)
```

The direction of the curl determines which boundary each field needs to be absorbed at:

| Field | Curl direction | Must be absorbed at |
|-------|---------------|---------------------|
| Ey    | x (columns)   | left / right boundary |
| Ex    | y (rows)      | top / bottom boundary |
| Bz    | both          | all four boundaries |

---

## How the PML works

The PML (perfectly matched layer) is a damping region near each edge. It replaces the standard update coefficient `ca = 1` with `ca < 1`, attenuating the field over each timestep. The attenuation depth `d` controls how strongly each cell is damped:

- `d = 0` → interior cell, `ca = 1` (no damping)  
- `d > 0` → PML cell, `ca < 1` (damping increases with depth)

Two depth signals are computed from the write address:

```
d_ey  = distance to nearest top or bottom edge   (row-based)
d_ex  = distance to nearest left or right edge   (column-based)
d_bz  = max(d_ey, d_ex)                          (all four edges)
```

---

## The bug

The PML instances were connected as:

```verilog
pml_ey: .d(d_ey)   // row-based depth → ca_ey < 1 only near top/bottom
pml_ex: .d(d_ex)   // col-based depth → ca_ex < 1 only near left/right
```

`pml_ey` received `d_ey` (row depth). At the left and right boundary columns, `d_ey = 0` for all interior rows, so `ca_ey = 1` — no damping on Ey at all. When the wave reached the left or right wall, Ey passed through the PML zone without being absorbed and reflected back into the domain.

The same problem applies to Ex at the top/bottom boundaries, but Ey carries the dominant energy for a circular wave in this mode, so the left/right reflections were the most visible.

---

## The fix

Swap the depth signals so each field is absorbed at the correct boundary:

```verilog
// before
pml_ey: .d(d_ey)
pml_ex: .d(d_ex)

// after
pml_ey: .d(d_ex)   // col-based depth → ca_ey < 1 near left/right ✓
pml_ex: .d(d_ey)   // row-based depth → ca_ex < 1 near top/bottom ✓
pml_bz: .d(d_bz)   // unchanged
```

With `pml_ey` now receiving `d_ex`, `ca_ey` decreases as the wave approaches the left or right wall. Ey is progressively attenuated before it reaches the physical boundary and cannot reflect back. The same applies to Ex at the top and bottom.

In the corner regions both `d_ex > 0` and `d_ey > 0`, so Ey is damped (via `d_ex`) and Ex is damped (via `d_ey`) simultaneously — corners are correctly absorbed with no extra treatment needed.

---

## Summary of changes

**File:** `src/hdl/fdtd_solver.sv`

| Instance | Port | Before | After |
|----------|------|--------|-------|
| `pml_ey` | `.d` | `d_ey` | `d_ex` |
| `pml_ex` | `.d` | `d_ex` | `d_ey` |
| `pml_bz` | `.d` | `d_bz` | `d_bz` (unchanged) |

No other files were modified. All seven testbench tests continue to pass after the change.
