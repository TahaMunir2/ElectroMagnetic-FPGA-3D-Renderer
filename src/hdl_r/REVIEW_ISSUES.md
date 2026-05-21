# `src/hdl_r` SystemVerilog Review Notes

## Summary

The `src/hdl_r` modules implement a streaming FPGA heightmap terrain renderer:

- `ray_gen.sv` generates one camera ray direction per input pixel.
- `marcher.sv` chains multiple `march_step.sv` instances to ray-march across a heightmap.
- `march_step.sv` advances a ray, reads the heightmap, and detects hit/off-grid conditions.
- `normal.sv` reads neighbouring heightmap samples and estimates a surface normal.
- `shader.sv` converts hit/miss results into RGB using altitude colour, fog, and approximate sun lighting.

The overall design intent is clear, but a few issues should be addressed before relying on this path for synthesis or visual correctness.

## Issues

### 1. First march sample can be reported as a false hit

**Files:** `marcher.sv`, `march_step.sv`

`marcher.sv` initializes `prev_below` to `0`:

```systemverilog
assign prev_chain[0] = 1'b0;
```

`march_step.sv` then declares a surface crossing whenever the current `below_D` value differs from `prevC`:

```systemverilog
crossed_D = (statC == ST_MARCHING) && (below_D != prevC);
```

This means the first sampled point is treated as a hit whenever `Pz < height`, even if the ray did not actually cross the surface between two sampled positions. That can produce immediate false HIT results.

**Suggested fix:** Initialize `prev_below` from the camera origin height before the first step, or add a first-sample flag so crossing detection only starts after a valid previous sample exists.

### 2. Heightmap memory port requirement is very high

**Files:** `marcher.sv`, `normal.sv`

`marcher.sv` exposes one heightmap read port per unrolled march step:

```systemverilog
output logic [IDX_W*2-1:0] bram_addr [N_STEPS],
output logic               bram_re   [N_STEPS],
input  logic signed [H_W-1:0] bram_dout [N_STEPS],
```

With the default `N_STEPS = 16`, the marcher needs 16 simultaneous reads per pixel clock. `normal.sv` then needs 4 more simultaneous neighbour reads. In total, the default pipeline expects 20 heightmap reads per cycle.

This is not available from a normal FPGA BRAM without replication, banking, or scheduling.

**Suggested fix:** Decide the intended memory architecture explicitly. Options include replicating the heightmap memory, banking by address pattern, reducing unroll factor, or time-multiplexing march steps at lower throughput.

### 3. Ray directions are not normalized

**Files:** `ray_gen.sv`, `march_step.sv`

`ray_gen.sv` computes:

```systemverilog
D = fwd + u * right + v * up;
```

The result is not normalized before being sent to the marcher. `march_step.sv` advances position by:

```systemverilog
P_new = P_in + DT * D;
```

Off-center rays therefore have larger direction magnitudes and travel farther per step than center rays. This affects hit accuracy, apparent depth, and max visible distance across the image.

**Suggested fix:** Either normalize directions before marching, precompute normalized camera rays, or document this as an intentional approximation and tune `DT`/`N_STEPS` around the worst-case screen corner.

### 4. World-to-grid conversion assumes power-of-two geometry

**File:** `march_step.sv`

`world_to_grid()` converts world coordinates to heightmap indices using a shift:

```systemverilog
return sum >>> (POS_F - $clog2(GRID_N) + $clog2(2));
```

This works for the default `GRID_N = 256` and `WORLD_HALF = 1.0`, but it silently becomes incorrect for non-power-of-two grid sizes or other world scaling choices.

**Suggested fix:** Add parameter assertions that enforce the supported configuration, or replace the shift-only conversion with a general fixed-point multiply/divide expression.

### 5. Verilator lint currently fails due to warnings

**Files:** multiple

Running Verilator lint on the five `hdl_r` modules exits nonzero because warnings are treated as fatal. Warnings include:

- Width mismatch in `DT` parameter calculation.
- Width mismatch in `world_to_grid()` comparisons against `GRID_N`.
- Width and signedness warnings in `shader.sv` arithmetic.
- Width/sign-extension warnings in `normal.sv`.

These are probably not all functional bugs, but they make automated lint less useful and may hide real issues later.

**Suggested fix:** Add explicit casts and intermediate signal widths for arithmetic expressions, then keep lint clean in CI or during review.

## Recommended Next Steps

1. Fix or intentionally document the first-sample crossing behavior.
2. Confirm the target heightmap memory architecture and whether 20 reads per cycle is acceptable.
3. Decide whether ray direction normalization is required for the visual target.
4. Add parameter assertions for assumptions such as power-of-two `GRID_N`.
5. Clean up Verilator width warnings and add at least one smoke test for the ray march hit/miss path.

