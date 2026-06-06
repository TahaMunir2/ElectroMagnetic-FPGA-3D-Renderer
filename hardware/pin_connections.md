# ESP32-WROOM-32 Pin Connections

Authoritative wiring reference for the EE2 FDTD EM Wave Simulator — Analog/MCU subsystem.
Source of truth: `overview.md` §6. Do not rewire; fix orientation/mirroring in software.

---

## Power Rails

| Rail | Source | Feeds |
|------|--------|-------|
| **5 V** | PYNQ USB feed | MCP6002 V+; divider that makes `CTRL_3V3`; **centre electrode of the Mode-1 conducting sheet** |
| **CTRL_3V3** | 5 V → divider → MCP6002 unity-gain follower | tops of all pots, the mode/2D-3D R/2R ladder, switch & button pull-ups |
| **GND** | common | everything above, the four grounded edges of the conducting sheet, ESP32, PYNQ |

The ESP32 **3V3 pin sags to ~2.9 V and is weak**, so it is not used as the control
reference. The buffered `CTRL_3V3` rail keeps every pot/encoder/switch full-scale aligned
with the ADC full-scale. Touch-panel X+/Y+ HIGH drive comes from **GPIOs**, not this rail.

---

## ADC Inputs

| GPIO | ADC Channel | Connected Hardware | Active Mode |
|------|-------------|-------------------|-------------|
| 32 | ADC1 | Panel 1 **X+** (conn. pin 4 = X2) — drives HIGH (X read) / senses Y-coord (Y read) / touch detect | Mode 1 |
| 33 | ADC1 | Panel 1 **Y+** (conn. pin 3 = Y2) — drives HIGH (Y read) / senses X-coord (X read) | Mode 1 |
| 25 | ADC2 (also DAC1, unused) | Panel 2 **X+** — drives HIGH (X read) / senses Y-coord (Y read) / touch detect | Mode 2 |
| 26 | ADC2 (also DAC2, unused) | Panel 2 **Y+** — drives HIGH (Y read) / senses X-coord (X read) | Mode 2 |
| 34 | ADC1 (input-only) | Probe tip → MCP6002 unity-gain buffer → 18kΩ/33kΩ divider → ESP32 | Mode 1 only |
| 35 | ADC1 (input-only) | Mode + 2D/3D encoder (10kΩ/20kΩ R/2R ladder, 4 levels: 0=M1/2D, 1=M1/3D, 2=M2/2D, 3=M2/3D) | Both |
| 36 | ADC1 (input-only) | Field-type **potentiometer** (no 3-position switch available) — 3 zones: 0–⅓=Ex, ⅓–⅔=Bz, ⅔–1=\|S\| (Poynting) | Mode 2 only |
| 39 | ADC1 (input-only) | Potentiometer: **yaw** (3D view) | Both |
| 27 | ADC2 | Potentiometer: **pitch** (3D view) | Both |
| 14 | ADC2 | Potentiometer: **zoom** (3D view) | Both |
| 13 | ADC2 | Potentiometer: **Zscale** (3D view) | Both |
| 4  | ADC2 | Potentiometer: **amplitude** (Mode 2 source amplitude) | Mode 2 |
| 15 | ADC2 (strapping*) | Potentiometer: **conductivity** (Mode 2 wave-speed / c) | Mode 2 |

\* GPIO15 strapping pin idles HIGH (required boot state). A pot is safe; worst case a low
value at power-up produces a verbose boot log but the board still boots.

---

## Digital I/O

| GPIO | Direction | Connected Hardware | Active Mode |
|------|-----------|-------------------|-------------|
| 23 | Output | Panel 1 **X−** (conn. pin 2 = X1) drive (LOW during X-read, Hi-Z otherwise) | Mode 1 |
| 22 | Output | Panel 1 **Y−** (conn. pin 1 = Y1) drive (LOW during Y-read, Hi-Z otherwise) | Mode 1 |
| 21 | Output | Panel 2 **X−** drive | Mode 2 |
| 19 | Output | Panel 2 **Y−** drive | Mode 2 |
| 5  | Input (pull-up) | Wall / Source SPDT switch — LOW = wall, HIGH = source | Mode 2 |
| 18 | Input (pull-up) | Clear-everything momentary button — active LOW | Mode 2 |
| 17 | Output (UART2 TX) | → PYNQ Arduino header **D0 (RX)** | Both |
| 16 | Input  (UART2 RX) | ← PYNQ Arduino header **D1 (TX)** | Both |

---

## Reserved / Spare Pins

| GPIO | Reason unused |
|------|---------------|
| 0 | Boot-strapping pin — leave floating/pulled-up |
| 2 | Boot-strapping pin |
| 12 | Boot-strapping pin (must be LOW at boot for 3.3 V flash) |
| 1 | UART0 TX — USB Serial Monitor debug output |
| 3 | UART0 RX — USB Serial Monitor |

~5 additional GPIOs remain spare on the 38-pin DevKit.

---

## Hard Wiring Rules

1. **Common GND** — panels, pots, switches, ESP32, and PYNQ must all share ground. The
   USB power cable between PYNQ and ESP32 already ties their GNDs together.
2. **3.3 V only on PYNQ Arduino header** — never connect 5 V signals to D0/D1 or any
   other PYNQ Arduino header pin.
3. **UART crossover** — ESP32 TX (GPIO17) → PYNQ D0 (RX); ESP32 RX (GPIO16) ← PYNQ D1 (TX).
4. **PYNQ UART IP** — D0/D1 go to the PL fabric. The Vivado design must instantiate an
   AXI UARTLite (or equivalent) on those pins so Linux sees a `/dev/ttyUL*` device.
5. **Controls run off `CTRL_3V3`, not the 3V3 pin** — the buffered 3.3 V rail (5 V →
   divider → MCP6002 follower) feeds all pot tops, the R/2R ladder, and switch/button
   pull-ups. The weak ~2.9 V 3V3 pin is not used as the control reference.
6. **GPIO25/26 DAC function unused** — these pins are silicon-capable DACs (DAC1/DAC2)
   but are used here purely as ADC2 + digital GPIO output. The touch panel only needs a
   clean digital HIGH, not a specific analog voltage. Never call `dacWrite()` on them.
7. **WiFi must remain OFF** — enabling WiFi disables all ADC2 channels (GPIO 4, 13, 14,
   15, 25, 26, 27).
8. **No DACs for the panels** — panels are driven by GPIOs; the small GPIO-HIGH vs
   ideal-3.3 V offset is absorbed by calibration on the PYNQ.
9. **Panel idle = Hi-Z** — every pin of the non-active panel is set to INPUT each loop
   to prevent cross-talk. Never drive an idle panel's terminals.

---

## Probe Signal Chain (Mode 1)

```
Conducting sheet (airbrushed carbon paint on thin plastic, 1–50 kΩ/sq)
   centre copper-tape pad  ──  +5 V        (input electrode)
   four edges copper tape  ──  GND         (grounded boundary)
  Probe wire reads local potential V(x,y)  (~5 V at centre → ~0 V at edges)
    → MCP6002 op-amp, half A, unity-gain follower  (Rin > 10¹² Ω)
    → 18kΩ / 33kΩ resistor divider  (scales ≤5 V probe to ≤3.3 V)
    → 10 MΩ pull-down to GND        (prevents floating probe reading)
    → GPIO34 (ADC1, input-only)
```

Sheet lies on touch panel 1, which reports the probe's XY position (see Touch Panel
Wiring below). Half B of the same MCP6002 buffers the `CTRL_3V3` rail (see Power Rails).

Probe value is transmitted raw (0–1023) and used directly as `bc_val` on the PYNQ.
It is the **only** channel that represents a real measured voltage; all others are
normalised fractions of full scale.

---

## Touch Panel Wiring (per panel)

Each panel uses 4 pins. The "+" pins (X+, Y+) are normal ADC GPIOs that also drive
HIGH — input-only pins (34–39) cannot be used for "+" lines.

```
Panel 1 (Mode 1):  X+ = GPIO32,  Y+ = GPIO33,  X− = GPIO23,  Y− = GPIO22
Panel 2 (Mode 2):  X+ = GPIO25,  Y+ = GPIO26,  X− = GPIO21,  Y− = GPIO19
```

**Connector pinout** (from `resistivetouchpanel.jpg` — electrodes X2 top, X1 bottom,
Y1 left, Y2 right). X1/X2 are the X layer, Y1/Y2 the Y layer:

| Conn. pin | Electrode | Panel-1 wire → | Role |
|-----------|-----------|----------------|------|
| 1 | Y1 | GPIO22 | Y− |
| 2 | X1 | GPIO23 | X− |
| 3 | Y2 | GPIO33 | Y+ |
| 4 | X2 | GPIO32 | X+ |

Which terminal of a pair is "+" only sets the coordinate **direction** — if an axis reads
mirrored, swap that pair or flip in software; never rewire to fix orientation.

**Coordinate output (calibrated on the ESP32):** X → **0–1023** over 16.4 cm, Y → **0–612**
over 9.8 cm (≈ 6.24 counts/mm on both axes, so gestures stay square). The firmware `map()`s
each axis from its measured raw min/max (`panelN.xRawMin/xRawMax/yRawMin/yRawMax`); set
those with `arduino/panel1_test`. The PYNQ then just scales 0–1023 / 0–612 → the 64×64 grid.

Panel 1 has a 10kΩ / 100nF RC filter on its sense lines → 5 ms settle time.
Panel 2 has no filter → 1 ms settle time.

Connectors: Würth 68610414122 FPC ZIF (1 mm pitch, 4-pos, SMD, top-contact) on
breakout boards to 0.1″ headers.
