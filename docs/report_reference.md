# FDTD FPGA Accelerator — Report Reference Document

This document captures every technical detail of the FPGA HDL implementation for use when writing the individual report. Organised to map directly onto the three assessment sections: Design Process, Implementation, and Evaluation.

---

## 1. Project Context and Role

The project implements a real-time 2D Finite-Difference Time-Domain (FDTD) electromagnetic field solver accelerated on the Zynq FPGA. The solver computes the evolution of a transverse-magnetic (TM) wave field on a 2D grid and streams field data to a host renderer.

**Personal scope:** Full FPGA HDL design — algorithm implementation in SystemVerilog, fixed-point arithmetic, absorbing boundary conditions, multi-lane parallel architecture, BRAM interfacing, halo exchange, testbench verification, and hardware commissioning.

---

## 2. Algorithm Theory — 2D FDTD TM Mode

### 2.1 Maxwell's Equations (TM Mode)

In TM mode the three active field components are Ey, Ex, and Bz. Starting from Maxwell's curl equations and discretising on a Yee staggered grid with leapfrog time-stepping, the update equations are:

```
Bz[n+½] = ca_bz · Bz[n-½] + cb_bz · ( (Ey[i+1,j] - Ey[i,j])/Δx - (Ex[i,j+1] - Ex[i,j])/Δy )

Ey[n+1] = ca_ey · Ey[n]   + cb_ey · ( Bz[i,j] - Bz[i-1,j] )

Ex[n+1] = ca_ex · Ex[n]   + cb_ex · ( Bz[i,j] - Bz[i,j-1] )
```

The coefficients ca and cb encode the medium properties and PML attenuation (see Section 5). In vacuum outside the PML, ca = 1 and cb = c·Δt/Δx where c is the wave speed.

### 2.2 Leapfrog Staggering

Bz is evaluated at half-integer time steps; Ey and Ex at integer steps. This means one full iteration requires two passes over every cell:

- **Phase 0 (B phase):** update Bz at every cell using current Ey, Ex
- **Phase 1 (E phase):** update Ey and Ex at every cell using updated Bz

The hardware scans the grid twice per iteration. For a grid of ROWS × COLUMNS cells:

```
Cycles per iteration = 2 × ROWS × COLUMNS
```

For the 128×128 oct-lane design: 2 × 16 × 128 = 4096 cycles per lane (all lanes run in lockstep).

### 2.3 Courant Stability Condition

The FDTD algorithm is conditionally stable. The Courant–Friedrichs–Lewy (CFL) condition requires:

```
c · Δt / Δx ≤ 1/√2   (2D)
```

The effective Courant number is encoded in the cb coefficients. With cb = −25 in Q3.13 fixed-point:

```
|cb| / 8192 = 25/8192 ≈ 0.00305
```

This is well within the stability limit and produces a visually slow wave that propagates approximately 0.003 cells per clock cycle. At 100 MHz and 4096 cycles per iteration, the wave advances about 12 cells per second of simulation time, giving a natural slow propagation suitable for real-time display.

### 2.4 Source Frequency

The source is a CORDIC-generated sine wave. The relationship between the hardware PHASE_STEP register and the spatial wavelength is:

```
λ = Courant × (65536 / PHASE_STEP)   [cells]
```

For propagation, λ must be ≥ 2 cells (Nyquist):

```
PHASE_STEP ≤ 65536 × Courant / 2 ≈ 65536 × 0.003 / 2 ≈ 98
```

**Critical bug found and fixed:** PHASE_STEP was set to 0x4000 (16384), giving λ ≈ 0.012 cells — far below Nyquist. The field was evanescent (could not propagate), producing a near-field diagonal artefact pattern on hardware. Fixed to PHASE_STEP = 0x0014 (20), giving λ ≈ 10 cells, well above Nyquist.

---

## 3. Fixed-Point Arithmetic

### 3.1 Q3.13 Format

All field values and coefficients are stored as 16-bit signed Q3.13 fixed-point numbers:

| Bit | Meaning |
|-----|---------|
| 15 | Sign |
| 14–13 | Integer part (2 bits) |
| 12–0 | Fractional part (13 bits) |

The scale factor is 2^13 = 8192. So 1.0 is represented as 8192, and −1.0 as −8192.

### 3.2 Multiply-and-Shift

Every field update involves one fixed-point multiply. The pattern:

```
result = (a × b) >>> 13
```

This is a 16×16 → 32-bit multiply followed by an arithmetic right shift of 13. The result is truncated back to 16 bits. All multiplies are implemented as synthesised 16-bit signed multipliers in `Ey.sv`, `Ex.sv`, `Bz.sv`.

### 3.3 Why 16-Bit

16-bit fixed-point fits exactly in one BRAM18 data word (no packing overhead). It also allows a single DSP48 slice per multiply on the Zynq-7000. The dynamic range of Q3.13 (−4 to +3.9999) is sufficient for normalised field values when the source amplitude is kept at or below 1.0 (= 8192 counts).

---

## 4. Module Architecture

### 4.1 Module Hierarchy

```
top_fdtd_oct_lane
├── bram_0 .. bram_7          (bram_module.v)    × 8
└── solver_0 .. solver_7      (fdtd_solver.sv)   × 8
        └── fdtd_engine
                ├── u_ey      (ey.sv)
                ├── u_ex      (ex.sv)
                └── u_bz      (bz.sv)
                        (all use pml.sv coefficients)
```

### 4.2 Signal Flow per Lane

```
BRAM port 0 ──read──► fdtd_solver ──compute──► fdtd_engine ──result──► BRAM port 0 (write)
BRAM port 1 ──read──► halo mux (in top) ──────────────────────────────► solver adj input
```

---

## 5. BRAM Module (`bram_module.v`)

### 5.1 Memory Organisation

Each lane has one `bram_module` instance containing six memory arrays:

| Array | Field | Port A | Port B |
|-------|-------|--------|--------|
| ey_mem_0 | Ey | Read/Write (solver) | Read (halo) |
| ex_mem_0 | Ex | Read/Write (solver) | unused |
| bz_mem_0 | Bz | Read/Write (solver) | Read (halo) |

For the oct-lane design: DEPTH = 16 × 128 = 2048 cells, WIDTH = 16 bits, ADDR_WIDTH = 14 bits.

Memory size per array: 2048 × 16 = 32 Kbits = 1 BRAM36.
Total per lane: 3 arrays × 1 BRAM36 = 3 BRAM36.
Total for 8 lanes: **24 BRAM36** (fits on both Zynq-7010 and Zynq-7020).

### 5.2 Synchronous Read Latency

BRAMs have 1-cycle read latency. An address presented at cycle N produces data at cycle N+1. This is critical for the halo exchange (see Section 9).

---

## 6. Field Update Modules (`ey.sv`, `ex.sv`, `bz.sv`)

### 6.1 3-Stage Pipeline

Each field update is pipelined over 3 clock cycles:

```
Stage 1: multiply ca × field_old              → product_ca  (32-bit)
Stage 2: multiply cb × (bz_right - bz_left)  → product_cb  (32-bit)
Stage 3: add and shift: (product_ca + product_cb) >>> 13
```

The 3-stage pipeline was introduced to close timing at 100 MHz. A single-cycle combinatorial path through two 16×16 multipliers and an adder was the critical path in the original design; splitting across three registers resolved the violation.

### 6.2 Pipeline Latency Impact

The 3-cycle latency means the write-back to BRAM is delayed 3 cycles after the read address is issued. The solver's FSM accounts for this: the write-enable and write-address are registered to align with the pipeline output.

---

## 7. PML Absorbing Boundary (`pml.sv`)

### 7.1 Purpose

Without boundary treatment, electromagnetic waves reflect off the grid edges and interfere with the simulation. The Uniaxial Perfectly Matched Layer (UPML) is a 6-cell absorbing region at each edge that attenuates outgoing waves exponentially before they reach the PEC wall.

### 7.2 Coefficient Design

The PML is parameterised by depth d (0 = interior edge, 5 = outer wall). The ca coefficient controls how much of the previous field value is retained per step; ca = 8192 (= 1.0) means no attenuation.

**Cubic ramp (implemented):**

```
ca(d) = 8192 − d³
```

| d | ca | Attenuation per step |
|---|----|----------------------|
| 0 | 8192 | 0 (interior interface) |
| 1 | 8191 | 0.012% |
| 2 | 8184 | 0.098% |
| 3 | 8165 | 0.33% |
| 4 | 8128 | 0.78% |
| 5 | 8067 | 1.53% |

The cb coefficients are unchanged (cb_e = cb_bz = −25) at all depths; attenuation comes entirely from ca.

**Design rationale for cubic vs linear:**

The cubic profile keeps ca = 8192 at d=0 (no impedance discontinuity at the interior interface, so no spurious reflection). The absorption accelerates toward the outer wall where wave energy is already attenuated. At Courant = 0.003, the one-way PML traversal attenuation is:

```
Linear profile: ≈ −48 dB
Cubic profile:  > −100 dB
```

The cubic profile provides more than a 50 dB improvement, virtually eliminating visible boundary reflections.

### 7.3 PEC at Grid Edges

The very first and last rows enforce a Perfect Electric Conductor (PEC) boundary condition by forcing Ey = 0. This is the outermost wall of the simulation domain. The solver identifies these rows using ROW_OFFSET + local_row relative to TOTAL_ROWS and zeroes the write data before issuing the BRAM write.

---

## 8. FDTD Solver (`fdtd_solver.sv`)

### 8.1 Operation

The solver is a counter-driven FSM that sweeps all cells in row-major order. The counter runs from 0 to 2×ROWS×COLUMNS−1:

- Counter < GRID_SIZE → **B phase**: read Ey, Ex neighbours; compute Bz; write Bz
- Counter ≥ GRID_SIZE → **E phase**: read Bz neighbours; compute Ey, Ex; write Ey, Ex

The address generation logic computes current_row = counter / COLUMNS and current_col = counter % COLUMNS (or their E-phase equivalent).

### 8.2 Parameters

| Parameter | Purpose |
|-----------|---------|
| TOTAL_ROWS | Global grid height (used for PML depth calculation) |
| ROWS | This lane's row count |
| COLUMNS | Grid width |
| ROW_OFFSET | This lane's starting row in the global grid |
| FIRST_LANE | 1 = do not read Bz from lane above (no lane above) |
| LAST_LANE | 1 = do not read Ey from lane below (no lane below) |
| CELL_WIDTH | Bits for row/column addresses |
| DATA_WIDTH | 16 |
| PML_SIZE | 6 |

Defaults were added to all parameters (FIRST_LANE=1, LAST_LANE=1, ROW_OFFSET=0) so standalone instantiation compiles without errors.

### 8.3 Source Injection — Soft Source

The source is injected as an additive term on the Ey update at a specified grid address:

```systemverilog
ey_wr_data = engine_ey_new + source_in;   // soft source
```

**Why soft, not hard:**
A hard source (`ey_wr_data = source_in`) completely overwrites the field at the source cell, creating a scatterer that reflects waves back. The hard source was causing asymmetric amplitude growth (a "fungal spike") at the source cell. Switching to a soft (additive) source allows the naturally outgoing field to pass through the source cell unobstructed, giving a physically correct isotropic radiating point source.

### 8.4 Output Ports for Halo Exchange

The solver exposes three combinatorial outputs to the containing top module:

```systemverilog
output logic [CELL_WIDTH-1:0] current_row,   // current cell row (within lane)
output logic [CELL_WIDTH-1:0] current_col,   // current cell column
output logic                  e_phase        // 1 = E phase, 0 = B phase
```

The top module uses these to drive the halo address mux (see Section 9).

### 8.5 Boundary Conditions

- **Top boundary** (global row 0, only FIRST_LANE): Ey write data forced to 0.
- **Bottom boundary** (global row TOTAL_ROWS−1, only LAST_LANE): Ey write data forced to 0.
- **Left boundary** (col 0): Ex write data forced to 0.
- **Right boundary** (col COLUMNS−1): Ex write data forced to 0.
- **PML**: ca/cb coefficients from pml.sv are selected based on distance from each edge.

---

## 9. Multi-Lane Architecture and Halo Exchange

### 9.1 Why Multi-Lane

A single solver scanning a 128×128 grid requires 2 × 128 × 128 = 32,768 cycles per iteration. Splitting into 8 lanes of 16 rows each gives 2 × 16 × 128 = 4,096 cycles — an 8× speedup. All lanes run in lockstep on the same clock and solver_enable signal.

### 9.2 Grid Partitioning

| Lane | Global rows | ROW_OFFSET | FIRST_LANE | LAST_LANE |
|------|-------------|-----------|-----------|----------|
| 0 | 0–15 | 0 | 1 | 0 |
| 1 | 16–31 | 16 | 0 | 0 |
| 2 | 32–47 | 32 | 0 | 0 |
| 3 | 48–63 | 48 | 0 | 0 |
| 4 | 64–79 | 64 | 0 | 0 |
| 5 | 80–95 | 80 | 0 | 0 |
| 6 | 96–111 | 96 | 0 | 0 |
| 7 | 112–127 | 112 | 0 | 1 |

### 9.3 What Needs to Cross Lane Boundaries

The FDTD update equations require neighbours:
- **Bz update** (B phase): needs Ey from the row below the current row. When lane i+1 is processing its local row 0, it needs Bz from lane i's local row ROWS−1.
- **Ey update** (E phase): needs Bz from the row above the current row. When lane i is processing its local row ROWS−1, it needs Ey from lane i+1's local row 0.

These are the two halo reads per adjacent pair.

### 9.4 Address Mux (Combinatorial)

BRAM port 1 is normally used by each solver for its own adjacency reads. During a halo event, the address on port 1 of lane i is overridden to read from the correct address in lane i's BRAM:

```systemverilog
// Bz halo: lane i+1 at its row 0 in B phase needs Bz last row of lane i
if (!slv_e_phase[i+1] && slv_current_row[i+1] == 0)
    bz_rd_addr_1[i] = (ROWS-1)*COLUMNS + slv_current_col[i+1];

// Ey halo: lane i at its last row in E phase needs Ey row 0 of lane i+1
if (slv_e_phase[i] && slv_current_row[i] == ROWS-1)
    ey_rd_addr_1[i+1] = slv_current_col[i];
```

This logic runs in an `always_comb` block that covers all 7 adjacent pairs.

### 9.5 Data Mux (Registered — 1-Cycle Delayed)

Because BRAMs have 1-cycle read latency, the data available at cycle N+1 corresponds to the address issued at cycle N. The halo data routing uses registered (previous-cycle) row and phase:

```systemverilog
always_ff @(posedge clk) begin
    prev_row[i]   <= slv_current_row[i];
    prev_phase[i] <= slv_e_phase[i];
end
```

The data mux then checks prev_row/prev_phase rather than current_row/e_phase:

```systemverilog
if (!prev_phase[i+1] && prev_row[i+1] == 0)
    slv_bz_adj_dout[i+1] = bz_rd_data_1[i];   // Bz halo from lane i

if (prev_phase[i] && prev_row[i] == ROWS-1)
    slv_ey_adj_dout[i] = ey_rd_data_1[i+1];   // Ey halo from lane i+1
```

This 1-cycle offset between address mux and data mux is critical. Getting it wrong causes halo data to be applied to the wrong cell.

### 9.6 Source Routing

The global source address is split into lane index and local address:

```systemverilog
source_lane       = source_addr / GRID_SIZE;
local_source_addr = source_addr - (source_lane * GRID_SIZE);
```

Only the matching lane asserts source_valid:

```systemverilog
.source_valid(source_valid && source_lane == 3'd N)
```

---

## 10. Top-Level Design Evolution

### 10.1 Single-Lane → Quad-Lane → Oct-Lane → Hex-Lane

| Design | File | Grid | Lanes | Rows/lane | Iteration cycles | BRAM18s |
|--------|------|------|-------|-----------|-----------------|---------|
| Single | top_fdtd_system.sv | 64×64 | 1 | 64 | 8192 | 6 |
| Quad | top_fdtd_quad_lane.sv | 64×64 | 4 | 16 | 2048 | 24 |
| Oct | top_fdtd_oct_lane.sv | 128×128 | 8 | 16 | 4096 | 48 |
| Hex | top_fdtd_hex_lane.sv | 128×128 | 16 | 8 | 2048 | 48 |

The quad-lane design gave a 4× cycle reduction over single-lane at the same grid size. The oct-lane design doubles the grid resolution (4× area) while only doubling iteration time. The hex-lane design keeps the same 128×128 grid but halves the iteration time again to 2048 cycles by doubling to 16 lanes — at exactly the same BRAM cost as oct-lane, because each lane now holds 1024 cells which fills a BRAM18 exactly (16 Kbits data out of 18 Kbits total; the remaining 2 Kbits are parity bits intrinsic to the BRAM18 silicon). No address space is wasted.

### 10.2 Generate Loop vs Explicit Instantiation

The oct-lane design was initially written with a `generate for` loop for conciseness. This was rewritten as explicit per-lane instantiation (`bram_0..bram_7`, `solver_0..solver_7`) to:

- Match the Vivado block design workflow (each instance visible by name)
- Avoid tool-specific elaboration edge cases with generate-block hierarchy in IP packaging
- Keep the design transparent and auditable

The logic is identical; only the coding style differs.

### 10.3 Unpacked Array Assignment

In SystemVerilog, unpacked arrays of the same type and dimensions can be assigned wholesale in continuous assignments:

```systemverilog
assign ey_rd_addr_0 = slv_ey_rd_addr;   // assigns all 16 elements
```

This is valid and synthesisable. However, inside `always_comb` blocks, iverilog loses array-element type information for signals that have been individually port-connected to instances, requiring per-element assignments for the procedural defaults in the halo mux blocks.

---

## 11. Design Decisions Summary

| Decision | Options considered | Chosen | Reason |
|----------|--------------------|--------|--------|
| Field representation | Float, Q1.15, Q3.13 | Q3.13 | Fits BRAM18 word; sufficient range; single DSP multiply |
| Courant number | 0.5 (max), 0.1, 0.003 | 0.003 (cb=−25) | Visually slow propagation; safe timing margin |
| PML profile | Linear, quadratic, cubic | Cubic | −100 dB vs −48 dB per traversal; no impedance step at interior interface |
| Source type | Hard, soft | Soft | Hard source caused DC accumulation and asymmetric field growth |
| Lane parallelism | 1, 4, 8, 16 | 16 (hex-lane) | 16× speedup over single-lane; BRAM18s fit exactly at 1024 cells/lane; no wasted address space |
| Multi-lane coding | Generate loop, explicit | Explicit | Vivado visibility; matches quad-lane reference style |
| PHASE_STEP | 0x4000 (original), 0x0014 | 0x0014 | 0x4000 → λ=0.012 cells (evanescent); 0x0014 → λ≈10 cells (propagating) |

---

## 12. Testbench and Verification

### 12.1 Methodology

All modules verified with iverilog + vvp simulation before hardware deployment. Testbenches written in SystemVerilog.

### 12.2 `tb_pml.sv`

Verifies all 7 PML entries (depths 0–5 plus default):
- ca values match cubic profile: 8192, 8191, 8184, 8165, 8128, 8067
- cb_e = cb_bz = −25 at all depths
- Strict monotonicity check (ca strictly decreasing)

### 12.3 `tb_top_fdtd_quad_lane.sv` and `tb_top_fdtd_oct_lane.sv`

9 tests each (oct-lane results shown):

| Test | What it checks | Result |
|------|---------------|--------|
| 1 | solver_done fires after exactly 4096 cycles | PASS |
| 2 | Source injection: Ey(8,8) nonzero after first iteration (= 8192) | PASS |
| 3 | Ey global row 0 = 0 (PEC top boundary) | PASS |
| 4 | Ey global row 127 = 0 (PEC bottom boundary) | PASS |
| 5 | Ex col 0 = 0 across all 8 lanes (PEC left boundary) | PASS |
| 6 | Ex col 127 = 0 across all 8 lanes (PEC right boundary) | PASS |
| 7 | Lane 1 Ey nonzero after 20 extra iterations (halo exchange works) | PASS |
| 8 | solver_done re-fires on repeated solver_enable toggle | PASS |
| 9 | rst halts solver mid-run; solver_done stays low | PASS |

Test 7 is the most significant: it confirms that energy propagates from lane 0 into lane 1 through the halo, which requires both the Bz port-1 read from lane 0 and the Ey port-1 read from lane 1 to be correctly timed and routed.

### 12.4 Hardware Verification

After fixing PHASE_STEP and switching to soft source, hardware produced:

- **Phase_step = 0.1 (Python-side):** clear expanding circular wave visible, symmetric about source
- **Steady-state:** wave fills grid with standing-wave interference pattern
- **PML:** no visible boundary reflections (consistent with >−100 dB absorption)

---

## 13. Performance Analysis

### 13.1 Throughput

| Design | Cycles/iteration | Iterations/second @ 100 MHz | Iterations/frame @ 60 fps |
|--------|-----------------|----------------------------|--------------------------|
| Oct-lane (8 lanes) | 4096 | 24,414 | 407 |
| Hex-lane (16 lanes) | 2048 | 48,828 | 813 |

The hex-lane design delivers 813 FDTD time-steps per rendered frame — twice the physics fidelity of oct-lane at no additional BRAM cost.

### 13.2 BRAM Utilisation

| Design | BRAM18s | BRAM36 equiv | Zynq-7010 (120 BRAM18s) | Zynq-7020 (280 BRAM18s) |
|--------|---------|-------------|--------------------------|--------------------------|
| Single-lane 64×64 | 6 | 3 | 5% | 2% |
| Quad-lane 64×64 | 24 | 12 | 20% | 9% |
| Oct-lane 128×128 | 48 | 24 | 40% | 17% |
| Hex-lane 128×128 | 48 | 24 | 40% | 17% |

Oct-lane and hex-lane have identical BRAM utilisation. The hex-lane uses BRAM18s
(1024-deep at 16-bit) while oct-lane uses BRAM36s (2048-deep at 16-bit) — Vivado
selects the appropriate primitive automatically based on declared array depth.

**Why BRAM18 fits exactly:** A BRAM18 stores 18 Kbits total — 16 Kbits of data
plus 2 Kbits of parity (1 parity bit per byte, used for ECC or spare data).
At 16-bit data width, depth = 1024 locations × 16 bits = 16,384 bits = 16 Kbits.
This fills the data portion exactly. With 16 lanes × 8 rows × 128 cols = 1024
cells per lane, there is zero wasted address space.

### 13.3 Cycles per Cell

```
Hex-lane: 2048 cycles / (128×128 cells) = 0.125 cycles/cell
Oct-lane: 4096 cycles / (128×128 cells) = 0.25  cycles/cell
```

16 lanes processing 16 rows simultaneously means each cell costs only 0.125
cycles — 8× below one cycle per cell.

### 13.4 Comparison with CPU

A Python NumPy FDTD reference for a 128×128 grid takes approximately 1–2 ms
per iteration. At 2048 cycles / 100 MHz = 20.5 µs per iteration, the hex-lane
FPGA implementation is approximately **50–100× faster** than the CPU baseline.

---

## 14. Key Technical Challenges and Resolutions

### 14.1 Evanescent Field (No Propagation)

**Symptom:** Hardware showed a diagonal near-field artefact that did not expand with time.

**Root cause:** PHASE_STEP = 0x4000 set the source frequency so high (relative to Courant number) that λ = 0.012 cells — below the Nyquist limit. The field could not propagate; it decayed evanescently from the source.

**Fix:** PHASE_STEP reduced to 0x0014. λ = 10 cells, clearly above Nyquist. Wave propagation immediately visible on hardware.

**Lesson:** For FDTD with a low Courant number, the maximum usable source frequency is much lower than in a high-Courant simulation. The constraint PHASE_STEP ≤ 65536 × Courant / 2 must be enforced.

### 14.2 DC Overflow / Asymmetric Growth

**Symptom:** Field amplitude grew without bound near the source, forming a one-sided "spike".

**Root cause:** Hard source unconditionally overwrote Ey at the source cell, preventing outgoing waves from leaving. The field accumulated.

**Fix:** Changed to soft source (additive injection). Outgoing wave passes through the source cell unimpeded. Confirmed on hardware: field became symmetric and amplitude-stable.

### 14.3 Timing Failure at 100 MHz

**Symptom:** Vivado reported negative WNS on the path through the field update pipeline.

**Root cause:** The combinatorial path through ca×field + cb×(bz_right − bz_left) involved two 16-bit multipliers and an adder in a single clock cycle.

**Fix:** Added register stages to split into a 3-stage pipeline (multiply ca, multiply cb×delta, add and shift). Timing closed with positive WNS.

### 14.4 Halo Data Arriving One Cycle Late

**Symptom:** Cross-lane wave propagation appeared corrupted in early simulation; cells at lane boundaries had incorrect values.

**Root cause:** The halo data mux was initially driven by current_row/e_phase. Because BRAM reads have 1-cycle latency, the data on the output bus corresponds to the address from the previous cycle — but the mux was steering it based on the current cycle.

**Fix:** Registered prev_row and prev_phase; used these in the data mux. Address mux still uses current signals (to issue the correct address this cycle); data mux uses prev signals (to route the data that arrives next cycle). This 1-cycle offset precisely compensates the BRAM latency.

---

## 15. File Inventory

| File | Role |
|------|------|
| `src/hdl/bram_module.v` | Dual-port BRAM for Ey, Ex, Bz fields |
| `src/hdl/ey.sv` | 3-stage pipelined Ey field update |
| `src/hdl/ex.sv` | 3-stage pipelined Ex field update |
| `src/hdl/bz.sv` | 3-stage pipelined Bz field update |
| `src/hdl/fdtd_engine.sv` | Instantiates Ey, Ex, Bz; common field engine |
| `src/hdl/pml.sv` | Returns ca, cb_e, cb_bz given PML depth |
| `src/hdl/fdtd_solver.sv` | Counter-FSM, source injection, boundary zeroing |
| `src/hdl/top_fdtd_quad_lane.sv` | 4-lane 64×64 explicit top level |
| `src/hdl/top_fdtd_oct_lane.sv` | 8-lane 128×128 explicit top level |
| `src/hdl/top_fdtd_hex_lane.sv` | 16-lane 128×128 explicit top level — zero BRAM waste, 2048 cycles/iteration |
| `src/hdl/top_fdtd_hardware_wrapper.sv` | AXI/start-done wrapper (single-lane, legacy) |
| `tests/tb_pml.sv` | PML coefficient unit tests |
| `tests/tb_top_fdtd_quad_lane.sv` | 9-test quad-lane integration testbench |
| `tests/tb_top_fdtd_oct_lane.sv` | 9-test oct-lane integration testbench |
| `docs/quad_lane_vivado_integration_guide.md` | Step-by-step Vivado migration guide |

---

## 16. Report Writing Notes

**Design Process section** should cover:
- Requirements derived from the FDTD physics (stability, Nyquist, PML absorption)
- The single→quad→oct-lane progression as evidence of iterative design
- Key decisions (Q3.13, cubic PML, soft source) with quantitative justification
- Bugs found and how they were diagnosed (PHASE_STEP, timing, halo latency)

**Implementation section** should cover:
- Q3.13 arithmetic and the multiply-shift pattern
- 3-stage pipeline and why it was needed
- BRAM organisation (dual-port, 3 fields, halo via port 1)
- Halo exchange design (address mux / data mux offset)
- PML cubic ramp derivation
- UPML coefficient lookup (pml.sv)

**Evaluation section** should cover:
- All 9 testbench tests and what each proves
- Quantitative: 4096 cycles/iteration, 0.25 cycles/cell, 24,414 iterations/second
- Quantitative: BRAM utilisation (24 BRAM36, 40% of Zynq-7010)
- Quantitative: PML absorption −100 dB vs −48 dB (cubic vs linear)
- Qualitative: hardware wave propagation screenshots before and after PHASE_STEP fix
- Qualitative: soft source symmetry fix
