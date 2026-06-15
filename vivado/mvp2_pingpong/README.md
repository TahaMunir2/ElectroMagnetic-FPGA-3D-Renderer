# MVP2 Pingpong — PYNQ-Z1 Testing Guide

2D FDTD electromagnetic wave simulator running on the PYNQ-Z1 PL fabric,
controlled and read back from the PS via AXI GPIO.

---

## What the design does

1. **CORDIC source** — generates a continuous sinusoidal wave at a configurable
   frequency and amplitude, injected at any cell in the 64×64 grid
2. **FDTD solver** — 64×64 2D Maxwell solver (Ey, Ex, Bz fields) with PML
   absorbing boundaries; Taha's MVP3 solver (Ey+Ex computed in parallel,
   73 728 cycles per iteration)
3. **Field magnitude** — after every solver iteration, computes |E| at all
   4096 cells and writes the result to the inactive ping-pong BRAM
4. **Ping-pong BRAMs** — double-buffer so the PS always reads a completed,
   tear-free frame while the PL writes the next one
5. **PS reads** — all control and data access is via four AXI GPIO blocks

---

## Hardware required

| Item | Detail |
|---|---|
| Board | PYNQ-Z1 (Zynq-7020) |
| PYNQ image | v2.7 or v3.0 |
| Connection | Ethernet or USB-UART to Jupyter |

---

## Step 1 — Copy the bitstream to the board

From your laptop (replace `<board-ip>` with the board's IP address):

```bash
scp vivado/mvp2_pingpong/mvp2_pingpong.bit xilinx@<board-ip>:/home/xilinx/
```

Default PYNQ password: `xilinx`

---

## Step 2 — Open Jupyter and load the bitstream

In a Jupyter notebook on the board:

```python
from pynq import Bitstream

bs = Bitstream('/home/xilinx/mvp2_pingpong.bit')
bs.download()
print("Bitstream loaded.")
```

---

## Step 3 — Set up the GPIO helpers

```python
from pynq import MMIO
import time, numpy as np

class GPIO:
    """Thin wrapper around a dual-channel AXI GPIO block."""
    def __init__(self, base):
        self.m = MMIO(base, 0x10000)
    def ch1_w(self, v):  self.m.write(0x00, int(v) & 0xFFFFFFFF)
    def ch2_w(self, v):  self.m.write(0x08, int(v) & 0xFFFFFFFF)
    def ch1_r(self):     return self.m.read(0x00)
    def ch2_r(self):     return self.m.read(0x08)

ctrl   = GPIO(0x41200000)   # control outputs  (PS → PL)
stat   = GPIO(0x41210000)   # status inputs    (PL → PS)
smag_a = GPIO(0x41220000)   # smag_a BRAM read
smag_b = GPIO(0x41230000)   # smag_b BRAM read
```

---

## Step 4 — Configure the source and enable the solver

```python
# --- tuneable parameters ---
PHASE_STEP  = 200          # source frequency  (Q3.13; larger = faster oscillation)
AMPLITUDE   = 4096         # source amplitude  (Q3.13; 4096 = 0.5, 8192 = 1.0)
SOURCE_ROW  = 32           # grid row  (0–63)
SOURCE_COL  = 32           # grid col  (0–63)

SOURCE_ADDR = SOURCE_ROW * 64 + SOURCE_COL   # 0–4095

# CH1: {amplitude_q313[15:0], phase_step_q313[15:0]}
ctrl.ch1_w((AMPLITUDE << 16) | PHASE_STEP)

# CH2: {17'b0, sample_req, mag_mode, solver_enable, source_addr[11:0]}
#   solver_enable = bit 12
#   mag_mode      = bit 13  (0 = |E| magnitude, 1 = Poynting)
#   sample_req    = bit 14
ctrl.ch2_w((1 << 12) | SOURCE_ADDR)

print(f"Source at ({SOURCE_ROW},{SOURCE_COL}), PHASE_STEP={PHASE_STEP}, AMP={AMPLITUDE}")
```

---

## Step 5 — Probe a single cell

```python
def probe_cell(row, col):
    """Read |E| magnitude at (row, col) from the completed ping-pong buffer."""
    sel  = (stat.ch2_r() >> 5) & 1      # pp_read_sel: 0=smag_a, 1=smag_b
    gpio = smag_a if sel == 0 else smag_b
    addr = row * 64 + col
    # Write address + enable, then read back
    gpio.ch1_w((1 << 12) | addr)         # bit 12 = smag enb
    time.sleep(1e-5)                     # one BRAM read cycle
    return gpio.ch2_r() & 0xFFFF

# Verify the pipeline is alive
time.sleep(0.1)
for i in range(5):
    src  = probe_cell(SOURCE_ROW, SOURCE_COL)
    near = probe_cell(SOURCE_ROW, SOURCE_COL + 8)
    edge = probe_cell(0, 0)
    chk  = stat.ch1_r()                  # solver_checksum (changes every frame)
    print(f"source={src:5d}  +8col={near:5d}  edge={edge:5d}  checksum=0x{chk:08X}")
    time.sleep(0.05)
```

**Expected output:**
```
source= 3241  +8col=  987  edge=    2  checksum=0x3A7F21BC
source= 2109  +8col= 1203  edge=    1  checksum=0x9C4E0351
...
```
- `source` — non-zero, changes every read (wave oscillates at source)
- `+8col` — non-zero, lower than source (wave attenuated with distance)
- `edge` — near zero (PML absorbed the wave before it reached the boundary)
- `checksum` — changes every line (solver is running)

---

## Step 6 — Read a full 64×64 magnitude frame

```python
def read_frame():
    """Read all 4096 cells from the active ping-pong buffer."""
    sel  = (stat.ch2_r() >> 5) & 1
    gpio = smag_a if sel == 0 else smag_b
    frame = np.zeros(4096, dtype=np.uint16)
    for addr in range(4096):
        gpio.ch1_w((1 << 12) | addr)
        frame[addr] = gpio.ch2_r() & 0xFFFF
    return frame.reshape(64, 64)

frame = read_frame()
print(f"Frame read — max={frame.max()}  nonzero={np.count_nonzero(frame)}")
```

---

## Step 7 — Visualise (optional, requires matplotlib)

```python
import matplotlib.pyplot as plt

frame = read_frame()
plt.figure(figsize=(6, 6))
plt.imshow(frame, cmap='hot', origin='lower')
plt.colorbar(label='|E| magnitude (Q3.13)')
plt.title(f'FDTD |E| field — source at ({SOURCE_ROW},{SOURCE_COL})')
plt.xlabel('column'); plt.ylabel('row')
plt.tight_layout()
plt.savefig('fdtd_frame.png', dpi=150)
plt.show()
```

You should see a bright hot-spot at the source cell with energy radiating
outward and fading toward the edges (absorbed by the PML boundary).

---

## Register map (quick reference)

### 0x41200000 — Control (PS writes, PL reads)

| Bits | Signal | Description |
|---|---|---|
| CH1 [15:0] | `phase_step_q313` | Source frequency (Q3.13 phase increment) |
| CH1 [31:16] | `amplitude_q313` | Source amplitude (Q3.13; 8192 = 1.0) |
| CH2 [11:0] | `source_addr` | Source injection cell (row×64+col) |
| CH2 [12] | `solver_enable` | 1 = run solver continuously |
| CH2 [13] | `mag_mode` | 0 = \|E\|, 1 = Poynting magnitude |
| CH2 [14] | `sample_req` | Pulse to request new CORDIC sample |

### 0x41210000 — Status (PL drives, PS reads)

| Bits | Signal | Description |
|---|---|---|
| CH1 [31:0] | `solver_checksum` | Running XOR of all field writes; changes every iteration |
| CH2 [0] | `solver_done` | Pulses high for 1 cycle when iteration completes |
| CH2 [1] | `source_valid` | CORDIC output is valid |
| CH2 [2] | `mag_done` | Pulses high when magnitude scan completes |
| CH2 [3] | `mag_busy` | High during magnitude computation |
| CH2 [4] | `source_latched` | PS source value has been latched by solver |
| CH2 [5] | `pp_read_sel` | 0 = read smag_a, 1 = read smag_b |
| CH2 [6] | `pp_frame_ready` | Pulses when a new completed frame is available |
| CH2 [22:7] | `source_q313` | Current CORDIC output value |

### 0x41220000 / 0x41230000 — BRAM read (smag_a / smag_b)

| Bits | Signal | Description |
|---|---|---|
| CH1 [11:0] | `addrb` | BRAM read address (0–4095) |
| CH1 [12] | `enb` | BRAM read enable (set to 1 when reading) |
| CH2 [15:0] | `doutb` | BRAM data out (|E| at that cell, Q3.13) |

Always check `pp_read_sel` (status CH2 bit 5) before reading to ensure you
read from the completed buffer, not the one currently being written.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `checksum` never changes | `solver_enable` not set | Set CH2 bit 12 of ctrl GPIO |
| All magnitudes = 0 | solver_enable=0 or source amplitude too small | Increase AMPLITUDE, check solver_enable |
| `source` cell = 0 but solver running | Source injection address wrong | Verify `source_addr = row*64+col` |
| Edge cells non-zero | PML not effective — wave too strong | Reduce AMPLITUDE |
| Bitstream load fails | Wrong .bit file or PYNQ version mismatch | Rebuild from source (see below) |

---

## Rebuilding the bitstream from source

Requires Vivado 2023.2 and the PYNQ-Z1 board files installed.

```tcl
# In Vivado Tcl Console:
source vivado/mvp2_pingpong/scripts/create_mvp2_pingpong_project.tcl
source vivado/mvp2_pingpong/scripts/add_ps_integration.tcl
# Then run synthesis + implementation + write_bitstream in the GUI
# or use:
source vivado/mvp2_pingpong/scripts/write_bit.tcl
```

---

## Fixed-point format

All field values use **Q3.13** signed fixed-point:
- 16-bit signed, 13 fractional bits
- `1.0 = 16'sd8192`, `0.5 = 16'sd4096`
- Magnitude values are unsigned (absolute value of field)

---

## Design files

```
vivado/mvp2_pingpong/
├── mvp2_pingpong.bit              — pre-built bitstream (PYNQ-Z1, Vivado 2023.2)
├── rtl/
│   ├── cordic_source_adapter.v   — phase accumulator + CORDIC interface
│   ├── fdtd_solver_bd_adapter.v  — wraps Taha's solver, exposes BRAM ports
│   ├── field_magnitude_bd_adapter.v — |E| magnitude scan
│   ├── s_mag_pingpong_ctrl.v     — ping-pong buffer controller
│   ├── field_bram.v              — 4096×16 TDP block RAM
│   ├── smag_bram.v               — 4096×16 SDP block RAM
│   └── fdtd_solver_import/       — Taha's MVP3 FDTD solver
│       ├── fdtd_solver.sv
│       ├── fdtd_engine.sv
│       ├── pml.sv                — PML absorbing boundary coefficients
│       ├── Ey.sv / Ex.sv / Bz.sv — field update equations
└── scripts/
    ├── create_mvp2_pingpong_project.tcl — creates Vivado project from scratch
    ├── add_ps_integration.tcl           — adds PS7 + AXI GPIO to BD
    └── write_bit.tcl                    — generates bitstream from routed checkpoint
```
