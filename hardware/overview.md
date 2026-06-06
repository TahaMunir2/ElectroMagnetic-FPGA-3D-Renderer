# EE2 FDTD EM Wave Simulator — Overview

> Canonical design overview for the Analog/MCU subsystem. This captures the full design of
> the **ESP32 input/microcontroller subsystem** and how it fits into the wider project.
> Read this fully before editing firmware or the UART protocol.
>
> **Last updated 2026-06-05:** added the buffered `CTRL_3V3` power rail (5 V → MCP6002),
> and switched the Mode-1 conducting sheet to a centre-fed 5 V / edge-grounded geometry.

---

## 1. What this project is

An interactive teaching tool that visualises electromagnetic fields in real time. An
FDTD (Finite-Difference Time-Domain) solver runs on a **PYNQ-Z1 FPGA** (Xilinx
Zynq-7020) and outputs to an HDMI monitor. An **ESP32-WROOM-32** reads all the physical
controls and sensors and streams them to the PYNQ over UART. A physical toggle switch
selects between two operating modes.

- Institution: Imperial College London — EE2 Design Project.
- Teams: Analog (Run, Marzouk), FPGA (Yi, Taha), Rendering (Mingze, Cyril).
- **This document and the firmware below are the Analog/MCU subsystem.**

---

## 2. Platform / toolchain

| Item | Detail |
|---|---|
| Microcontroller | ESP32-WROOM-32 DevKit (AZ-Delivery, 38-pin). Original ESP32 (dual Xtensa LX6), **not** C3/C6/S3. |
| MCU IDE | Arduino IDE 2.x, board = **"ESP32 Dev Module"** (esp32 by Espressif core). USB-serial via CH340. |
| FPGA | PYNQ-Z1 (Zynq-7020), Vivado 2022.2, Python on the ARM PS. |
| Display | HDMI 640×480 @ 60 Hz. |
| Grid | 64×64 cells, Q3.13 fixed point, fields Ex/Ey/Bz (2D TE-mode Maxwell). |
| MCU↔FPGA link | UART2, 115200 8N1, ~50 Hz packet. |
| Power | PYNQ USB port → ESP32 USB (5 V power **only**, not data). Controls run off a buffered 3.3 V rail (`CTRL_3V3`) derived from 5 V via an MCP6002 — see §6. |

---

## 3. System data flow

```
 Probe / 2 touch panels / pots / switches
              │  (analog + digital)
              ▼
        ESP32-WROOM-32        ── reads all inputs, packs a binary frame
              │  UART2 @ 115200, ~50 Hz
              ▼
     PYNQ-Z1  (ARM PS, Python)  ── parses frame, writes FDTD/render registers
              │  AXI
              ▼
     FDTD engine + renderer (PL) ── 64×64 grid, PML boundary
              │  AXI-Stream → VDMA → HDMI
              ▼
        HDMI monitor (640×480)
```

The ESP32 is the only thing this firmware controls. Everything downstream of the UART
is the FPGA/rendering teams' responsibility, but the protocol (section 10) is the
contract between us.

---

## 4. The two operating modes

A toggle (encoded with the 2D/3D switch — see section 8) selects the mode.

### Mode 1 — Real field measurement
- Simulates the **static potential** distribution: Laplace's equation ∇²V = 0.
- A self-made conducting sheet (conductive carbon paint airbrushed onto a thin flexible
  plastic board, target 1–50 kΩ/sq) is driven from its **centre electrode at +5 V** — a
  small copper-tape pad with a soldered wire — while all **four edges are grounded** (copper
  tape → GND). This sets up a 2-D Laplace potential V(x,y) that falls from ~5 V at the centre
  to ~0 V at the grounded edges.
- A separate probe wire reads the local potential V(x,y); **touch panel 1**, placed under the
  conducting sheet, reads the probe's XY position.
- FDTD runs with real c, so it converges to the same Laplace solution the paper solves
  physically. The probe value becomes the FDTD boundary value (`bc_val`).

### Mode 2 — Interactive wave simulation
- Simulates **time-dependent wave propagation** (full Maxwell). Shows interference,
  diffraction, reflection.
- A stylus on **touch panel 2** sets the wave-source / wall / erase position.
- FDTD runs with **normalised c** (wavelength ≈ 10 cells). The **conductivity knob**
  (pot 6) scales the wave-speed coefficient so the user can vary the speed of light /
  medium live.

---

## 5. ESP32 firmware — responsibilities

1. Read the active touch panel's X/Y and touch state.
2. Read the probe (Mode 1 only).
3. Read 6 potentiometers (yaw, pitch, zoom, Zscale, amplitude, conductivity).
4. Decode the mode + 2D/3D switch (R/2R-encoded, 1 ADC pin) and the field-type pot.
5. Read the wall/source switch and the clear button.
6. Pack everything into a binary frame and send over UART2 at ~50 Hz.

The ESP32 does **no** physics — it is purely an input concentrator.

---

## 6. Final pin map (authoritative)

WiFi is **OFF** (it would disable the ADC2 pins, several of which are in use). No DACs are
used. The two touch panels are wired **independently** (no shared rails) and the idle
panel is tri-stated each loop.

### Power rails
The ESP32's on-board **3V3 pin sags to ~2.9 V and is weak** (limited current), so it is
**not** used as the analog reference for the controls. Instead a clean **3.3 V control rail
(`CTRL_3V3`)** is generated from the **5 V** pin: a resistor divider sets ~3.3 V and one half
of an **MCP6002** op-amp buffers it as a unity-gain follower into a low-impedance rail. Every
potentiometer top, the mode/2D-3D encoder ladder, and all switch/button pull-ups reference
`CTRL_3V3`, so each control's full travel maps to the full ADC range (no sag, no wasted
span). The **other half of the same MCP6002** is the Mode-1 probe buffer — one dual package
does both jobs.

| Rail | Source | Feeds |
|---|---|---|
| **5 V** | PYNQ USB feed | MCP6002 V+; the divider that makes `CTRL_3V3`; the **centre electrode of the Mode-1 conducting sheet** |
| **CTRL_3V3** | 5 V → divider → MCP6002 follower | tops of all pots, encoder R/2R ladder, switch & button pull-ups |
| **GND** | common | all of the above, the four edges of the conducting sheet, ESP32, and the PYNQ |

- The touch-panel **X+/Y+ terminals are driven directly by GPIOs**, not from `CTRL_3V3`.
- The probe can reach ~5 V at the sheet centre; the **18k/33k divider scales it to ≤3.3 V**
  before GPIO34. Never feed raw 5 V into any ESP32 ADC pin or the PYNQ Arduino header.

### ADC inputs

| GPIO | ADC | Connects to | Active in |
|---|---|---|---|
| 32 | ADC1 | Panel 1 **X+** (connector pin 4 = X2) — drives HIGH (X read) / senses Y-coord (Y read) / touch | Mode 1 |
| 33 | ADC1 | Panel 1 **Y+** (connector pin 3 = Y2) — drives HIGH (Y read) / senses X-coord (X read) | Mode 1 |
| 25 | ADC2 | Panel 2 **X+** | Mode 2 |
| 26 | ADC2 | Panel 2 **Y+** | Mode 2 |
| 34 | ADC1 (input-only) | Probe → MCP6002 buffer → 18k/33k divider | Mode 1 only |
| 35 | ADC1 (input-only) | Mode + 2D/3D encoder (10k/20k R/2R network, 4 levels) | both |
| 36 | ADC1 (input-only) | Field-type **pot** — E / B / S zones (pot used; no 3-position switch) | Mode 2 only |
| 39 | ADC1 (input-only) | Pot: yaw | both |
| 27 | ADC2 | Pot: pitch | both |
| 14 | ADC2 | Pot: zoom | both |
| 13 | ADC2 | Pot: Zscale | both |
| 4  | ADC2 | Pot: amplitude | Mode 2 |
| 15 | ADC2 (strapping*) | Pot: **conductivity** (Mode 2 wave-speed / c) | Mode 2 |

\* GPIO15 is a strapping pin but idles HIGH (its required boot state); a pot there is
safe. Worst case a low setting at power-up gives a verbose boot log, still boots.

### Digital pins

| GPIO | Connects to | Active in |
|---|---|---|
| 23 | Panel 1 **X−** (connector pin 2 = X1) drive (LOW / Hi-Z) | Mode 1 |
| 22 | Panel 1 **Y−** (connector pin 1 = Y1) drive | Mode 1 |
| 21 | Panel 2 **X−** drive | Mode 2 |
| 19 | Panel 2 **Y−** drive | Mode 2 |
| 5  | Wall / Source switch (LOW = wall, HIGH = source) | Mode 2 |
| 18 | Clear-everything button (active LOW) | Mode 2 |
| 17 | UART2 **TX** → PYNQ Arduino header **D0 (RX)** | both |
| 16 | UART2 **RX** ← PYNQ Arduino header **D1 (TX)** | both |

### Reserved / spare
GPIO 0, 2, 12 — left unused (boot-strapping pins). GPIO 1, 3 — kept free for the USB
serial console so the Serial Monitor keeps working. ~5 pins spare on the 26-GPIO board.

### Hard wiring rules
- Common ground across panels, pots, switches, ESP32, **and** the PYNQ (the USB power
  cable already shares GND).
- The PYNQ Arduino header is **3.3 V** — never feed 5 V into it.
- UART crosses over: ESP32 TX(17) → PYNQ RX(D0); ESP32 RX(16) ← PYNQ TX(D1).
- On the PYNQ, D0/D1 go to the PL fabric — the FPGA design must instantiate a UART
  (e.g. AXI UARTLite) on those pins; it then appears as a Linux serial device.

---

## 7. Touch-panel theory (so the firmware makes sense)

A 4-wire resistive panel is two resistive sheets with a gap. Each sheet has bus-bar
electrodes on two opposite edges. Reading position is a two-phase voltage-divider trick:

- **Read X-coordinate:** drive the X-layer as a ladder (X+ = HIGH, X− = LOW), let the
  Y-layer float, and ADC-read the contact-point voltage on a Y terminal. Voltage ∝ X.
- **Read Y-coordinate:** swap — drive the Y-layer (Y+ = HIGH, Y− = LOW), float the
  X-layer, read on an X terminal. Voltage ∝ Y.
- **Touch detect:** drive Y− LOW, read an X-layer terminal through an internal pull-up.
  Untouched → pull-up holds it HIGH; touched → the sheets short and it drops LOW.

### Panel connector pinout (from `resistivetouchpanel.jpg`)
The 4-wire flex has electrodes **X2 (top), X1 (bottom), Y1 (left), Y2 (right)**; the
connector order is:

| Conn. pin | Electrode | Panel-1 wire → ESP32 | Role |
|---|---|---|---|
| 1 | Y1 | GPIO22 | Y− |
| 2 | X1 | GPIO23 | X− |
| 3 | Y2 | GPIO33 | Y+ |
| 4 | X2 | GPIO32 | X+ |

X1/X2 are the X-layer pair, Y1/Y2 the Y-layer pair. Which terminal of a pair is "+" only
sets the coordinate **direction** — if an axis reads mirrored, swap that pair or flip in
software (never rewire to fix orientation).

### Independent panels + tri-stating (interference-free)
Both panels are wired to **separate** pins. Each loop, the firmware sets *every pin of
the idle panel to INPUT (Hi-Z)*, so it shares no driven node with the active panel and
cannot inject anything. Only the panel the mode selects is ever driven. This is why there
are no shared "rails" — an earlier shared-rail idea would have merged the two panels'
sense readings.

### Double-duty "+" pins (why no DACs)
Each panel's **X+ and Y+** are ADC-capable GPIOs that do two jobs: drive their terminal
HIGH during one read phase, and ADC-sense it during the other. X− and Y− are plain
digital drives. So a panel needs only 4 pins and no DAC. The "+" pins must be normal ADC
GPIOs (not the input-only pins 34–39, which cannot drive and have no pull-ups).

---

## 8. Switch / encoder / pot scheme

- **Mode + 2D/3D** are combined onto one ADC pin (GPIO35) with a **10k / 20k R/2R
  network** acting as a 2-bit DAC driven by two SPDT switches. Four levels at 0,
  ⅓, ⅔, 1 of full scale → `0=Mode1/2D, 1=Mode1/3D, 2=Mode2/2D, 3=Mode2/3D`. Mode is the
  MSB (10k = bigger weight), display is the LSB (20k).
- **Field type** (E / B / S) is a **potentiometer** (GPIO36) read as three equal zones:
  `0–⅓ = Ex, ⅓–⅔ = Bz, ⅔–1 = |S| (Poynting)`. Mode 2. A pot is used here because **no
  3-position switch was available** — turning the pot into one of three zones gives the same
  result with a part we have.
- **Pots:** yaw, pitch, zoom, Zscale (3D view controls, both modes), amplitude (Mode 2
  source amplitude), conductivity (Mode 2 wave speed / c).
- **Wall/Source** is a single SPDT switch (GPIO5); **Clear** is a momentary button
  (GPIO18). These replace the old 3-position interaction rotary.

---

## 9. Design conventions (IMPORTANT for all code)

- **WiFi must never be enabled.** ADC2 pins (4, 13, 14, 15, 25, 26, 27) are in use and
  WiFi disables ADC2.
- **No DACs.** Panels are GPIO-driven; calibration on the PYNQ absorbs the small
  GPIO-high vs ideal-3.3V offset.
- **Controls reference the buffered `CTRL_3V3` rail, not the weak 3V3 pin.** This keeps
  pot/encoder/switch full-scale aligned with the ADC full-scale (see §6 Power rails). The
  panel X+/Y+ HIGH drive still comes from GPIOs, not this rail.
- **Everything is normalised.** Every transmitted value is a raw ADC count in the range
  0–1023, treated downstream as a **normalised fraction of full scale (value / 1023 ∈
  [0,1])**. Firmware thresholds are expressed as fractions of `ADC_MAX`, never as a
  specific voltage. **The probe channel is the only semantic exception:** its value
  represents the *physically measured* field potential V(x,y) on the conducting paper
  (a real voltage, scaled by the 18k/33k divider) and is used directly as the FDTD
  boundary value `bc_val`. Do not introduce hard-coded volt constants anywhere else.
- **Panel orientation / mirror** (X↔Y swap, direction flips) is corrected in software
  (here or on the PYNQ), never by rewiring.
- **Panel X/Y are calibrated on the ESP32** to a **physically-proportional** grid:
  **X → 0–1023 over 16.4 cm, Y → 0–612 over 9.8 cm** (≈ 6.24 counts/mm on *both* axes, so
  a square gesture reads square). The ESP32 `map()`s each axis from its measured raw min/max
  (per-panel calibration constants in the firmware — set them with `panel1_test`). Pots and
  the probe are still sent as raw counts. The PYNQ only has to scale 0–1023 / 0–612 onto the
  64×64 grid (no min/max calibration needed there any more).

---

## 10. UART protocol (ESP32 → PYNQ)

Binary frame, **21 bytes**, sent at ~50 Hz. 115200 baud, 8N1. This supersedes the older
17-byte format in the original project memo — it adds explicit slots for amplitude,
conductivity, and probe so no field is mode-multiplexed. **Coordinate this with the FPGA
team's parser.**

| Byte | Field | Notes |
|---|---|---|
| 0 | Header `0xAA` | discard frame if not 0xAA |
| 1 | Flags bitmask | see below |
| 2–3 | Panel X | calibrated **0–1023** (16.4 cm), high byte first |
| 4–5 | Panel Y | calibrated **0–612** (9.8 cm), high byte first |
| 6–7 | Amplitude pot | 10-bit (Mode 2 source amplitude) |
| 8–9 | Conductivity pot | 10-bit (Mode 2 wave speed / c) |
| 10–11 | Probe | 10-bit (Mode 1 measured potential, `bc_val`) |
| 12–13 | Yaw pot | 10-bit |
| 14–15 | Pitch pot | 10-bit |
| 16–17 | Zoom pot | 10-bit |
| 18–19 | Zscale pot | 10-bit |
| 20 | Checksum | XOR of bytes 1..19; discard frame if mismatch |

**Flags byte (byte 1):**

| Bit | Meaning |
|---|---|
| 0 | Mode (0 = Mode 1, 1 = Mode 2) |
| 1 | Display (0 = 2D, 1 = 3D) |
| 2–3 | Field type (0 = Ex, 1 = Bz, 2 = \|S\|) |
| 4 | Interaction (0 = source, 1 = wall) — Mode 2 |
| 5 | Clear pressed |
| 6 | Touch valid (panel currently pressed) |
| 7 | reserved |

When bit 6 (touch valid) is clear, bytes 2–5 are 0 and the PYNQ should not place a
source/boundary that frame.

---

## 11. Firmware source (ESP32 / Arduino)

The **canonical, up-to-date firmware lives in the repo**, not inline here (the previous
inline copy was removed to avoid drift — edit the `.ino` files directly):

- `arduino/esp32_inputs/esp32_inputs.ino` — the full input concentrator (21-byte UART
  frame @ ~50 Hz).
- `arduino/panel1_test/panel1_test.ino` — standalone Panel-1 bring-up / calibration tool.

Build in Arduino IDE 2.x, board **"ESP32 Dev Module"**. Key behaviours (see §6 / §9 / §10):

- Reads the active panel (idle panel tri-stated), 6 pots + the field-type pot, the mode /
  2D-3D R/2R encoder, the wall/source switch and the clear button; packs the 21-byte
  frame (§10). WiFi stays **off** (ADC2 in use).
- **Panel X/Y are calibrated on-chip** to a physically-proportional grid —
  **X → 0–1023 (16.4 cm), Y → 0–612 (9.8 cm)** — via per-panel raw min/max constants in
  the `Panel` struct (`xRawMin/xRawMax/yRawMin/yRawMax`). Pots and the probe stay raw.
- To calibrate: flash `panel1_test`, drag into all four corners, read the raw
  `X[min..max]` / `Y[min..max]`, and paste them into `panel1.*` in the main firmware.

---

## 12. PYNQ side — what to implement (for the agent / FPGA team)

A Python reader on the PYNQ that:
1. Opens the serial device (e.g. `serial.Serial("/dev/ttyUL0", 115200)` — confirm the
   actual node with `dmesg | grep tty` after loading the overlay; it depends on how the
   UART is brought into the PL).
2. Syncs on `0xAA`, reads 21 bytes, verifies the XOR checksum.
3. Unpacks the fields per section 10.
4. Normalises each pot to 0–1 and maps to the relevant FDTD/render register.
5. Scales the **already-calibrated** panel coords to the grid: `gx = X*63/1023`,
   `gy = Y*63/612` (X is 0–1023 / 16.4 cm, Y is 0–612 / 9.8 cm). Only act when touch-valid.
   No raw min/max calibration is needed here — the ESP32 already did it.
6. Mode 1: writes `bc_x`, `bc_y`, `bc_val` (probe). Mode 2: writes `src_x`, `src_y`,
   `src_amp` (amplitude), and the wave-speed coefficient from conductivity; honours
   wall/source and clear.

---

## 13. Open items / TODO

- [ ] Confirm the PYNQ serial device node and add the UART IP to the PL design (D0/D1).
- [ ] Bench-calibrate each panel's raw min/max per axis with `panel1_test`; paste into the
      firmware (`panelN.xRawMin/xRawMax/yRawMin/yRawMax`) so X→0–1023, Y→0–612 are accurate.
- [ ] Verify panel axis orientation (X = 16.4 cm edge, Y = 9.8 cm edge); if swapped, rotate
      the panel or swap the X/Y pin pairs (or `X_OUT_MAX`/`Y_OUT_MAX`).
- [ ] Map conductivity (0–1) → the FDTD wave-speed coefficient range with the FPGA team.
- [ ] Sync the 21-byte packet format with the FPGA parser (was 17 bytes in the old memo).
- [ ] Confirm the 10k/100nF RC filter is fitted on Panel 1's sense lines (sets the 5 ms
      settle); if absent, reduce `panel1.settleMs`.
- [ ] Tune the touch threshold (`7/10` of full scale) against measured pressed/unpressed
      levels.

---

## 14. Key decisions & rationale

| Decision | Why |
|---|---|
| ESP32 over Arduino Mega | Built-in 12-bit ADC, smaller, enough channels; programmed in Arduino IDE. |
| UART, not SPI/WiFi | 2 wires, simple Python `serial`; WiFi would kill ADC2. |
| Independent panels + tri-state idle | Guarantees zero cross-talk; shared rails merged sense readings. |
| Double-duty "+" pins, no DACs | Frees DAC pins for pots; keeps the ADC budget within safe (non-strapping) pins. |
| Mode + 2D/3D on one ADC (R/2R) | Saves a pin; 4 clean levels with wide noise margin. |
| Field type on a pot | No 3-position switch available; a pot read as 3 zones decodes cleanly. |
| Normalised values everywhere | Mode-independent scaling; only the probe is a real measured voltage. |
| Switches off GPIO1/3 | Keeps the USB Serial Monitor alive for debugging. |

---

## 15. Hardware notes (brief)

- Conducting sheet: conductive carbon paint airbrushed onto a thin flexible plastic board,
  target 1–50 kΩ/sq. **Centre** = small copper-tape pad + soldered wire driven at **+5 V DC**;
  all **four edges** = copper tape tied to **GND**. Probe potential runs from ~5 V at the
  centre to ~0 V at the edges. The sheet lies on touch panel 1, which reports the probe XY.
- Probe buffer: MCP6002 (half A) unity-gain follower (Rin > 10¹² Ω), then 18k/33k divider
  scaling the ≤5 V probe to ≤3.3 V; 10 MΩ pull-down stops a floating probe. (Half B of the
  same MCP6002 buffers the `CTRL_3V3` rail — see §6.)
- Touch panels: 4-wire resistive, via Würth 68610414122 FPC ZIF connectors (1 mm pitch,
  4-pos, SMD, top-contact) on breakout boards to 0.1″ pins.
- Approved suppliers: RS, CPC/Farnell/Onecall (fast). Order on approved accounts only.

---
*Canonical overview for the Analog/MCU subsystem — maintained in VS Code with Claude Code.
LTSpice section schematics live in `ltspice/`; the firmware in `arduino/esp32_inputs/`.*
