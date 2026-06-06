# ESP32-WROOM-32 Pin Connections (`hardware_better` — DG413 two-panel)

Wiring reference for the improved build: **6-pin split drive/sense** panels, both panels
sharing one ESP32 port through a **DG413** analog switch, with the yaw/pitch/zoom/Zscale
pots removed. Source of truth: `overview.md`. Connector image:
`../hardware/resistivetouchpanel.jpg`. Do not rewire to fix orientation — fix in software.

---

## Power Rails
| Rail | Source | Feeds |
|------|--------|-------|
| **5 V** | USB | DG413 V+; Mode-1 conducting-sheet centre electrode |
| **CTRL_3V3** | 5 V → divider → MCP6002 follower | pot tops (mode/2D-3D/wall/clear use the ESP32 internal pull-ups) |
| **GND** | common | ESP32, DG413, both panels, sheet edges, PYNQ |

The ESP32 3V3 pin is weak (~2.9 V) so it is not the control reference. Panel X+/Y+ HIGH
drive comes from GPIOs (through the DG413), not `CTRL_3V3`.

---

## Shared panel port (DG413 routes it to the active panel)
| GPIO | Direction | Role |
|------|-----------|------|
| 18 | Output | **X+ drive** — HIGH during X-read |
| 32 | ADC1 in | **X+ sense** → Y-coord; INPUT_PULLUP for touch detect |
| 23 | Output | **X- drive** — LOW during X-read (common to both panels) |
| 25 | Output | **Y+ drive** — HIGH during Y-read |
| 35 | ADC1 in (input-only) | **Y+ sense** → X-coord |
| 22 | Output | **Y- drive** — LOW during Y-read (common to both panels) |
| 19 | Output | **MUX_SEL** → DG413 control (LOW = Panel 1, HIGH = Panel 2) |

X+ and Y+ each carry **both** their drive and sense pin on one ESP32 node; that node is the
DG413 **COM**. Read X drives the X layer and senses on GPIO35; read Y drives the Y layer and
senses on GPIO32; touch detect drives Y- low and reads GPIO32 through its pull-up.

---

## Other inputs
| GPIO | Direction | Connects to | Active in |
|------|-----------|-------------|-----------|
| 34 | ADC1 (input-only) | Probe → MCP6002 buffer → 18k/33k divider | Mode 1 |
| 21 | Input (pull-up) | **Mode 1/2 switch** (LOW = Mode 2) | both |
| 26 | Input (pull-up) | **2D/3D switch** (LOW = 3D) | both |
| 4  | ADC2 | Field-type pot — E/B/S zones | Mode 2 |
| 39 | ADC1 (input-only) | Amplitude pot | Mode 2 |
| 33 | ADC1 | Conductivity pot (wave speed / c) | Mode 2 |
| 27 | Input (pull-up) | Wall/Source switch (LOW = wall, HIGH = source) | Mode 2 |
| 14 | Input (pull-up) | Clear button (active LOW) | Mode 2 |
| 17 | UART2 TX | → PYNQ Arduino header D0 (RX) | both |
| 16 | UART2 RX | ← PYNQ Arduino header D1 (TX) | both |

**Changed vs base design:** yaw/pitch/zoom/Zscale pots removed (no 3-D camera control;
their UART slots are sent as 0). **Mode and 2D/3D are now two separate switches** (GPIO21,
GPIO26) instead of one R/2R-encoded ADC pin — the R/2R network is gone.

**Spare:** non-strapping 13, 36; strapping 0, 2, 5, 12, 15.

---

## DG413 wiring (the mux)
DG413 = quad SPST, **2 normally-closed (NC) + 2 normally-open (NO)** → two SPDT from one
select line. **Power V+ = 5 V, V- / GND = 0 V.** Decouple V+ with 100 nF.

```
 ESP32 X+ node (GPIO18 + GPIO32) ── DG413 COM(a) ─┬─ NC(a) ─► Panel1 X+  (conn pin4 / X2)
                                                  └─ NO(a) ─► Panel2 X+
 ESP32 Y+ node (GPIO25 + GPIO35) ── DG413 COM(b) ─┬─ NC(b) ─► Panel1 Y+  (conn pin3 / Y2)
                                                  └─ NO(b) ─► Panel2 Y+
 GPIO23 (X-) ──────────────────────────────────────► Panel1 X- AND Panel2 X-  (conn pin2 / X1)
 GPIO22 (Y-) ──────────────────────────────────────► Panel1 Y- AND Panel2 Y-  (conn pin1 / Y1)
 GPIO19 (MUX_SEL) ─► all DG413 control inputs (tie NC/NO pairs together)
```
- LOW on `MUX_SEL` closes the NC switches → **Panel 1**; HIGH closes the NO switches →
  **Panel 2**. *Confirm against the DG413 truth table; if reversed, flip the `MUX_SEL`
  logic in firmware (one line).*
- Make each SPDT by joining one NC terminal and one NO terminal = the COM (ESP32 side).
- DG413 logic inputs are TTL (VINH ≈ 2.4 V) → the 3.3 V `MUX_SEL` drives them reliably even
  though V+ = 5 V. Ron ≈ 35 Ω, flat over the signal range → ~10% range loss, stays linear.

---

## Connector pinout (per panel)
From `../hardware/resistivetouchpanel.jpg` (electrodes X2 top, X1 bottom, Y1 left, Y2 right):

| Conn. pin | Electrode | Goes to |
|-----------|-----------|---------|
| 1 | Y1 | Y- bus (GPIO22, common) |
| 2 | X1 | X- bus (GPIO23, common) |
| 3 | Y2 | Y+ → DG413 (per-panel) |
| 4 | X2 | X+ → DG413 (per-panel) |

"+/-" within a pair only sets coordinate **direction** — flip in software if mirrored.

---

## Coordinate output (calibrated on the ESP32, per panel)
X → **0–1023** over 16.4 cm, Y → **0–612** over 9.8 cm (≈6.24 counts/mm both axes). The
firmware reads coordinates with `analogReadMilliVolts()` (linearised) and **auto-calibrates
each panel separately**: it learns the raw min/max from firm presses and maps with a 6%
edge-margin clamp. Sweep each panel's edges once after boot. The PYNQ scales 0–1023 / 0–612
→ the 64×64 grid (no calibration needed there).

---

## Hard wiring rules
1. **Common GND** across ESP32, DG413, both panels, sheet edges, PYNQ.
2. **DG413 on 5 V**, not 3.3 V (min supply ~5 V). Panel signals 0–3.3 V fit inside 0–5 V.
3. **3.3 V only on the PYNQ Arduino header** — never 5 V.
4. **UART crossover:** ESP32 TX(17) → PYNQ D0(RX); ESP32 RX(16) ← PYNQ D1(TX).
5. **WiFi OFF** — ADC2 channels (GPIO4, and others) are in use.
6. **Idle panel is inert** automatically (its X+/Y+ are open at the DG413); only the active
   panel is driven.
