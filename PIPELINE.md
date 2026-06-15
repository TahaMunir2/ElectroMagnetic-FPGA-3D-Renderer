# PIPELINE.md — Stage-by-Stage Pipeline Reference

All stages share a single clock domain (`clk_pix`, 25 MHz in board mode).  
Fixed-point format throughout: **signed Q3.13** (16-bit: 1 sign + 3 integer + 13 fractional). `1.0 = 16'sd8192`.

---

## Stage 0 — Source Wave Generation

**Module**: `cordic_source_adapter` (wraps Vivado `cordic_0` IP)  
**Files**: `rtl/cordic_source_adapter.v`, Vivado CORDIC IP `cordic_0`

### Inputs
| Signal | Width | Source |
|--------|-------|--------|
| `sample_req` | 1 | `mvp2_hdmi_top` (tied to `~core_rst`) |
| `phase_step_q313` | 16 signed | Top-level parameter (`DEFAULT_PHASE_STEP_Q313 = 256`) |
| `amplitude_q313` | 16 signed | Top-level parameter (`DEFAULT_AMPLITUDE_Q313 = 4096`) |
| `m_axis_dout_tdata` | 32 | CORDIC IP output (sin=bits[31:16], cos=bits[15:0], fix16.14) |
| `m_axis_dout_tvalid` | 1 | CORDIC IP handshake |

### Outputs
| Signal | Width | Destination |
|--------|-------|-------------|
| `source_q313` | 16 signed | `fdtd_solver_bd_adapter` |
| `source_valid` | 1 | `fdtd_solver_bd_adapter` |
| `s_axis_phase_tdata` | 16 signed | CORDIC IP input |
| `s_axis_phase_tvalid` | 1 | CORDIC IP handshake |

### What it does
Maintains a phase accumulator (wraps ±π in Q3.13). On each `sample_req` pulse, advances the phase by `phase_step_q313`, sends it to the CORDIC IP, waits for the AXI-Stream result, scales the sin output by `amplitude_q313`, saturates to 16-bit, and emits `source_q313/source_valid`.

**Latency**: Variable — CORDIC IP has a pipeline of ~12–20 cycles (Vivado CORDIC v6). One sample per CORDIC invocation.  
**Output registered**: Yes — `source_q313` and `source_valid` are registered outputs.

---

## Stage 1 — 2D FDTD Solve

**Modules**: `fdtd_solver_bd_adapter` → `fdtd_solver` → `fdtd_engine` → `ey` / `ex` / `bz`  
**Files**: `rtl/fdtd_solver_bd_adapter.v`, `rtl/fdtd_solver_import/fdtd_solver.sv`, `fdtd_engine.sv`, `Ey.sv`, `Ex.sv`, `Bz.sv`, `pml.sv`

### Inputs (to `fdtd_solver_bd_adapter`)
| Signal | Width | Source |
|--------|-------|--------|
| `clk`, `rst` | 1 | Clock/reset |
| `solver_enable` | 1 | Top (`~core_rst`) |
| `mag_mode` | 1 | Top (`DEFAULT_MAG_MODE = 1` → Poynting |S|) |
| `source_q313` | 16 | `cordic_source_adapter` |
| `source_valid` | 1 | `cordic_source_adapter` |
| `ey_douta`, `ey_doutb` | 16 each | Ey BRAM port A (read), port B (adj read) |
| `ex_douta` | 16 | Ex BRAM port A (read) |
| `bz_douta`, `bz_doutb` | 16 each | Bz BRAM port A (read), port B (adj read) |
| `s_mag_douta` | 16 | s_mag BRAM (unused by solver, used during mag scan) |

### Outputs (from `fdtd_solver_bd_adapter`)
| Signal | Width | Destination |
|--------|-------|-------------|
| `solver_done` | 1 | `field_magnitude_bd_adapter` (trigger) |
| `solver_checksum` | 32 | Debug/BD port |
| `source_latched` | 1 | Debug/BD port |
| `ey_addra/ena/wea/dina`, `ey_addrb/enb/web/dinb` | 16/1/1/16 each | Ey BRAM |
| `ex_addra/ena/wea/dina`, `ex_addrb/enb/web/dinb` | 16/1/1/16 each | Ex BRAM |
| `bz_addra/ena/wea/dina`, `bz_addrb/enb/web/dinb` | 16/1/1/16 each | Bz BRAM |
| `s_mag_addra/ena/wea/dina` | 16/1/1/16 | s_mag BRAM (written during mag scan inside adapter) |
| `mag_busy`, `mag_done` | 1 each | `field_magnitude_bd_adapter` arbiter |

### What it does
`fdtd_solver_bd_adapter` latches the source sample, then hands control to `fdtd_solver`. The solver runs a three-pass scan over all 192²=36864 cells:

| Counter range | Field updated | BRAM reads |
|---------------|---------------|------------|
| 0 … 36863 | Ey | ey[cell], bz[cell], bz[cell−192] (adj) |
| 36864 … 73727 | Ex | ex[cell], bz[cell] |
| 73728 … 110591 | Bz | bz[cell], ey[cell], ey[cell+192] (adj) |

For each cell, `fdtd_engine` computes new field values using:
- `ey`: `Ey_new = ca_ey×Ey_old + cb_ey×(Bz_right − Bz_left)` (3-stage pipeline: subtract, multiply, add)
- `ex`: `Ex_new = ca_ex×Ex_old − cb_ex×(Bz_right − Bz_left)` (3-stage pipeline)
- `bz`: `Bz_new = ca_bz×Bz_old + cb_bz×((Ey_right−Ey_left) − (Ex_right−Ex_left))` (3-stage pipeline)

PML coefficients (`ca`, `cb_e`, `cb_bz`) from `pml.sv` are selected combinationally based on distance from the nearest wall (6-layer LUT, 0=inner wall, 5=outer wall).

Write-back is registered (3 cycles after reading, `write_valid` gates the write enable).  
Source injection: if `source_valid` and `wr_cell == SOURCE_ADDR (18528)`, override `ey_wr_data` with `source_q313`.  
Boundary forcing: row 0 / row 191 → Ey=0; col 0 / col 191 → Ex=0 (perfect electric boundary).

When counter reaches 3×GRID_SIZE−1, `solver_done` pulses for one cycle.

**Latency per full iteration**: 110592 cycles (≈ 4.4 ms at 25 MHz, 1.1 ms at 100 MHz)  
**Output registered**: `solver_done` is a registered one-cycle pulse.

---

## Stage 2 — Field Magnitude Computation

**Module**: `field_magnitude_bd_adapter`  
**File**: `rtl/field_magnitude_bd_adapter.v`

### Inputs
| Signal | Width | Source |
|--------|-------|--------|
| `start` | 1 | `solver_done` pulse from `fdtd_solver_bd_adapter` |
| `mag_mode` | 1 | Top (`1` = Poynting |S|) |
| `ey_douta`, `ex_douta`, `bz_douta` | 16 each | Ey/Ex/Bz BRAM port A (read during mag scan) |
| Solver BRAM signals (pass-through) | — | Forwarded to BRAMs when `mag_active=0` |

### Outputs
| Signal | Width | Destination |
|--------|-------|-------------|
| `busy` | 1 | BD arbiter |
| `done` | 1 | `s_mag_to_renderer_bridge` (trigger) |
| `s_mag_addra/ena/wea/dina` | 16/1/1/16 | s_mag BRAM write |
| BRAM mux outputs for Ey/Ex/Bz | — | To BRAMs (arbitrates between solver and mag scan) |

### What it does
Triggered by rising edge of `start` (= `solver_done`). Scans all 192² cells in order, reading Ey, Ex, Bz from the field BRAMs simultaneously. 3-stage compute pipeline:
- **Stage 1**: Latch Ex, Ey, Bz from BRAM read-data
- **Stage 2**: `|E| ≈ max(|Ex|,|Ey|) + min/2` (Manhattan approximation)
- **Stage 3**: `mag_mode=1` → `|S| = |E| × |Bz| >> 13`; `mag_mode=0` → `|E|` directly

Writes result to `s_mag_bram` at the corresponding address. When last address written, pulses `done`.

**Latency**: 192² + pipeline fill ≈ 36867 cycles  
**Output registered**: `done` is a registered one-cycle pulse.

---

## Stage 3 — Heightmap Bridge (Downsample)

**Module**: `s_mag_to_renderer_bridge`  
**File**: `rtl/renderer_integration/s_mag_to_renderer_bridge.v`

### Inputs
| Signal | Width | Source |
|--------|-------|--------|
| `start` | 1 | `field_magnitude_bd_adapter.done` |
| `s_mag_dout` | 16 | s_mag BRAM read data |

### Outputs
| Signal | Width | Destination |
|--------|-------|-------------|
| `s_mag_addr` | 16 | s_mag BRAM read address |
| `s_mag_en` | 1 | s_mag BRAM enable |
| `s_mag_we` | 1 | Tied 0 (read-only) |
| `heightmap_we` | 1 | All 20 `renderer_heightmap_ram` write enables |
| `heightmap_waddr` | 12 | All 20 `renderer_heightmap_ram` write addresses |
| `heightmap_wdata` | 16 | All 20 `renderer_heightmap_ram` write data |
| `busy` | 1 | BD status |
| `done` | 1 | BD status |
| `ready` | 1 | `mvp2_hdmi_top` (gates video timing start) |

### What it does
For each of the 64²=4096 destination heightmap cells, computes source address as:
```
src_x = (dst_x × 3) + 1
src_y = (dst_y × 3) + 1
src_addr = src_y × 192 + src_x
```
Issues a synchronous BRAM read (ISSUE→WAIT→WRITE state machine to account for 1-cycle BRAM read latency), then writes the sampled magnitude to all 20 heightmap RAMs simultaneously.

`ready` stays high after the first complete transfer (signals renderer to start).

**Latency**: 4096 × ~3 cycles ≈ 12290 cycles per transfer  
**Output registered**: Yes.

---

## Stage 4 — Ray Rendering

**Module**: `renderer_bd_adapter` → `ray_unit_synth_wrapper` → `ray_unit`  
**Files**: `rtl/renderer_integration/renderer_bd_adapter.v`, `renderer_standalone/hdl/ray_unit.sv`, `ray_gen.sv`, `marcher.sv`, `march_step.sv`, `normal.sv`, `shader.sv`

### Inputs
| Signal | Width | Source |
|--------|-------|--------|
| `enable` | 1 | `renderer_heightmap_ready` from bridge |
| `heightmap_we/waddr/wdata` | 1/12/16 | From `s_mag_to_renderer_bridge` |

### Outputs
| Signal | Width | Destination |
|--------|-------|-------------|
| `rgb888` | 24 | `mvp2_hdmi_top` → `rgb2dvi_0` |
| `valid` | 1 | `mvp2_hdmi_top` → HDMI DE |
| `frame_done` | 1 | BD status |

### What it does
Free-running pixel counter generates (px, py) at 1 pixel/cycle. The `ray_unit` pipeline processes each pixel through 4 sub-stages:

**Sub-stage 4a: `ray_gen`** (4 cycles, 6 DSPs)
| I/O | Signal | Width |
|-----|--------|-------|
| In | `px_in`, `py_in` [0..639, 0..479] | 10, 9 |
| In | Camera basis vectors `fwd`, `right`, `up` (Q2.13) | 16 each |
| Out | Ray direction `Dx, Dy, Dz` (Q2.13) | 16 each signed |

Stage 0: centre pixel: `px_c = px - 320`, `py_c = 240 - py`  
Stage 1: scale: `u = px_c × K_U`, `v = py_c × K_V` (K=137, Q0.15)  
Stage 2: 6 products: `u×right_xyz`, `v×up_xyz`  
Stage 3: sum: `D = fwd + u×right + v×up`

**Sub-stage 4b: `marcher`** (64 cycles, 16 unrolled `march_step`)
Each `march_step` is 4 pipeline stages (A: advance, B: grid index + BRAM req, C: BRAM latency, D: hit test):

| I/O | Signal | Width |
|-----|--------|-------|
| In | `Dx/Dy/Dz`, origin `Ox/Oy/Oz` (Q2.13/Q2.13) | 16 each |
| In | `bram_dout[i]` — heightmap value at current position | 16 |
| Out | `status` (HIT/OFF_GRID/MARCHING), `ix_hit/iy_hit` (6 each), `h_hit` (16), `step_count` (5) | — |

Each step: advance `P += dt×D` (dt = 2/64 in world units), look up terrain height at new (x,y), check if ray crossed terrain (sign flip of `Pz < h`). Frozen-ray pattern: HIT or OFFGRID rays propagate unchanged through later steps.  
20 BRAM ports total: 16 for marcher + 4 for normal.

**Sub-stage 4c: `normal`** (4 cycles)
| I/O | Signal | Width |
|-----|--------|-------|
| In | `ix_hit`, `iy_hit` from marcher | 6 each |
| In | `bram_dout[0..3]` — heights at (ix±1, iy), (ix, iy±1) | 16 each |
| Out | Normal `Nx, Ny, Nz` (Q2.13) | 16 each signed |

Reads 4 neighbours, computes: `Nx = −(h[ix+1,iy]−h[ix−1,iy])`, `Ny = −(h[ix,iy+1]−h[ix,iy−1])`, `Nz = 1.0`

**Sub-stage 4d: `shader`** (5 stages — designed for 100 MHz Artix-7)
| I/O | Signal | Width |
|-----|--------|-------|
| In | `status`, `h_hit`, `step_count`, `Nx/Ny/Nz` | various |
| Out | `r_out, g_out, b_out` | 8 each |

Stage 1: `bright_q = max(Nz, 0)`, `altitude_shifted`, `fog_int = step_count×255/N_STEPS`  
Stage 2: clamp all to 8-bit  
Stage 3: `light_u8 = AMBIENT + (255−AMBIENT)×bright >> 8`, `base_r/g/b` from altitude  
Stage 4: fog mix: `fogged = (1−fog)×base + fog×PALE_GREY`  
Stage 5: `lit = fogged × light >> 8`; HIT → lit colour, else SKY colour (135, 206, 235)

**Total renderer pipeline latency**: ray_gen(4) + marcher(64) + normal(4) + shader(5) = **77 cycles**

**Throughput**: 1 pixel/cycle (fully pipelined, no stalls in demo mode)  
**Output registered**: Yes — `rgb888`, `valid`, `px_out`, `py_out` are registered outputs.

---

## Stage 5 — Video Output

**Modules**: `video_timing_640x480`, `rgb2dvi_0`  
**Files**: `renderer_standalone/wrapper/video_timing_640x480.sv` (or Vivado project copy), Digilent `rgb2dvi_0`

### What it does
`video_timing_640x480` generates `sx`, `sy`, `hsync`, `vsync`, `active_video` at pixel clock (25 MHz, 640×480 60 Hz VGA timing). In `mvp2_hdmi_top`, these are **delayed by 77 cycles** through shift registers to align with the 77-cycle renderer latency before feeding `rgb2dvi_0`.

`rgb2dvi_0` (Digilent IP, `digilentinc.com:ip:rgb2dvi:1.4`) serialises `vid_pData[23:0]`, `vid_pVDE`, `vid_pHSync`, `vid_pVSync` into 4-pair TMDS HDMI output using `clk_5x` (125 MHz, 5× the pixel clock).

**Output**: HDMI TMDS on connector J11 (PYNQ-Z1)

---

## End-to-End Timing Budget

| Stage | Module | Cycles | Notes |
|-------|--------|--------|-------|
| Source gen | `cordic_source_adapter` + CORDIC IP | ~15 | One sample per FDTD iteration |
| FDTD solve | `fdtd_solver` | 110,592 | 3 × 192² at 25 MHz = 4.4 ms/iter |
| Field mag | `field_magnitude_bd_adapter` | ~36,870 | 192² + 3 pipeline |
| Heightmap bridge | `s_mag_to_renderer_bridge` | ~12,290 | 64² × 3 states |
| **Total per frame** | Solver + mag + bridge | **~159,752 cycles** | **~6.4 ms at 25 MHz** |
| Renderer pipeline | `ray_unit` | 77 cycles latency, 1/cycle throughput | Runs continuously |
| Frame render | 640×480 pixels | 307,200 cycles | 12.3 ms at 25 MHz |

The solver loop runs at approximately **6 Hz** update rate (at 25 MHz). The renderer continuously reads the heightmap and re-renders the same frame until the bridge updates it (approximately every 159 ms). This is intentional for the demo — the visual update rate matches the EM simulation update rate.
