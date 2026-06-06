# EE2 FDTD EM Wave Simulator — Overview (`hardware_better`)

> Improved variant of the Analog/MCU subsystem. Two differences from `../hardware`:
> 1. **6-pin split drive/sense** panel wiring (cleaner, linear coordinates).
> 2. A **DG413 analog switch** lets **both touch panels share one ESP32 panel port**,
>    selected by the mode. To fit the pin budget, the **yaw/pitch/zoom/Zscale** view pots
>    are removed (amplitude, conductivity and field-type remain).
>
> Read this before editing the firmware or the UART protocol. Connector pinout image is
> shared with the base design: `../hardware/resistivetouchpanel.jpg`.

---

## 1. What this project is
An interactive teaching tool that visualises EM fields in real time. An FDTD solver runs on
a **PYNQ-Z1 FPGA** and outputs HDMI; an **ESP32-WROOM-32** reads the physical controls and
streams them to the PYNQ over UART. A toggle selects between two modes (Mode 1 = real field
measurement, Mode 2 = interactive wave). Imperial College London EE2 Design Project.

## 2. Platform / toolchain
| Item | Detail |
|---|---|
| Microcontroller | ESP32-WROOM-32 DevKit (original ESP32, dual Xtensa LX6) |
| MCU IDE | Arduino IDE 2.x, board **"ESP32 Dev Module"** |
| FPGA | PYNQ-Z1 (Zynq-7020), Vivado, Python on the ARM PS |
| Display | HDMI 640×480 @ 60 Hz |
| Grid | 64×64 cells, Q3.13 fixed point, Ex/Ey/Bz (2D TE-mode) |
| MCU↔FPGA link | UART2, 115200 8N1, ~50 Hz, 21-byte frame |
| **Panel mux** | **DG413** quad analog switch (2 NC + 2 NO), powered from **5 V** |
| Power | USB 5 V; controls on a buffered 3.3 V rail (`CTRL_3V3`); DG413 on 5 V |

## 3. The two panels share one port (DG413)
Only one panel is ever read at a time (Mode 1 → Panel 1, Mode 2 → Panel 2), so a single
**6-pin panel port** on the ESP32 is routed to whichever panel the mode selects:

```
                  DG413 (2 NC + 2 NO = two SPDT, one select line)
ESP32 X+ (drive+sense) ──COM──┬─ NC ─► Panel1 X+ (Mode 1)
                              └─ NO ─► Panel2 X+ (Mode 2)
ESP32 Y+ (drive+sense) ──COM──┬─ NC ─► Panel1 Y+
                              └─ NO ─► Panel2 Y+
ESP32 X- ───────────────────────────► Panel1 X-  AND  Panel2 X-   (common)
ESP32 Y- ───────────────────────────► Panel1 Y-  AND  Panel2 Y-   (common)
MUX_SEL (GPIO19) ─► all DG413 control inputs   (LOW=Panel1, HIGH=Panel2)
```
- Only the two **"+"** lines are switched; **X-/Y- are tied common** (the idle panel's "+"
  lines are open, so it is electrically inert).
- The DG413's **2 NC + 2 NO** mix gives the two changeovers from a **single select line —
  no inverter needed.** Firmware drives `MUX_SEL` from the mode bit.
- **DG413 supply = 5 V** (it is not a 3.3 V part; min single supply ≈ 5 V). Signals are
  0–3.3 V, well inside 0–5 V. Its logic inputs are TTL, so the 3.3 V `MUX_SEL` is fine.
  Ron ≈ 35 Ω and flat → negligible range loss, stays linear. *Confirm the select polarity
  from the DG413 truth table; if reversed, swap the `MUX_SEL` logic in firmware.*

## 4. Why 6 pins per panel (split drive/sense)
Each "+" terminal gets a **push-pull drive pin** and a **separate ADC sense pin**, rather
than one double-duty pin. The senses sit on the **input-only ADC pins (34–39)**, which have
no output driver or pull-ups bonded to the pad → very low leakage. Because the panel sense
is a high-impedance, position-dependent source, low pad leakage keeps the reading **linear**
(a normal GPIO's leakage would bow the curve). Coordinates are also read with
`analogReadMilliVolts()` (chip-calibrated, linearised) — together these give a straight
position→value response.

Pins per panel-port = 6: `X+ drive, X+ sense, X- drive, Y+ drive, Y+ sense, Y- drive`.
With the DG413 those 6 serve **both** panels (+1 select line).

## 5. The two operating modes
- **Mode 1 — real field:** conducting sheet (carbon paint on plastic, centre = +5 V, four
  edges = GND) sets up a 2-D Laplace V(x,y); a probe reads V, Panel 1 reads the probe XY.
  Probe → MCP6002 buffer → 18k/33k divider → GPIO34. FDTD converges to the same solution.
- **Mode 2 — interactive wave:** a stylus on Panel 2 places the source/wall/erase; full
  Maxwell. Amplitude pot = source amplitude; conductivity pot = wave speed (c); field pot
  picks E/B/|S|.

## 6. Pin map (authoritative)
WiFi **OFF** (ADC2 in use). The 7 view/extra pots of the base design are reduced to 3.

### Shared panel port (via DG413) + control
| GPIO | Role | Type |
|---|---|---|
| 18 | Panel **X+ drive** (HIGH on X-read) | digital out |
| 32 | Panel **X+ sense** → Y-coord; pull-up → touch detect | ADC1 |
| 23 | Panel **X- drive** (LOW); common to both panels | digital out |
| 25 | Panel **Y+ drive** (HIGH on Y-read) | digital out |
| 35 | Panel **Y+ sense** → X-coord | ADC1 (input-only) |
| 22 | Panel **Y- drive** (LOW); common to both panels | digital out |
| 19 | **MUX_SEL** → DG413 (LOW=Panel1, HIGH=Panel2) | digital out |

### Other inputs
| GPIO | Connects to | Active in |
|---|---|---|
| 34 | Probe → MCP6002 buffer → 18k/33k divider | Mode 1 |
| 21 | **Mode 1/2 switch** (digital, internal pull-up) | both |
| 26 | **2D/3D switch** (digital, internal pull-up) | both |
| 4  | Field-type pot — E/B/S zones | Mode 2 |
| 39 | Amplitude pot | Mode 2 |
| 33 | Conductivity pot (wave speed / c) | Mode 2 |
| 27 | Wall/Source switch (LOW = wall, HIGH = source) | Mode 2 |
| 14 | Clear button (active LOW) | Mode 2 |
| 17 | UART2 TX → PYNQ D0 (RX) | both |
| 16 | UART2 RX ← PYNQ D1 (TX) | both |

**Connector pinout** (`../hardware/resistivetouchpanel.jpg`): pin1=Y1, pin2=X1, pin3=Y2,
pin4=X2. So each panel: **X2(pin4)→X+, X1(pin2)→X-, Y2(pin3)→Y+, Y1(pin1)→Y-** — the X+/Y+
go to the DG413, X-/Y- to the common ESP32 drives.

### Removed vs base design
**yaw, pitch, zoom, Zscale** pots are not fitted (no 3-D camera control in this build).
Their UART slots are sent as 0. **Mode and 2D/3D are now two separate switch pins** (GPIO21,
GPIO26) instead of one R/2R-encoded ADC pin — so the R/2R network is gone. Everything else
is intact.

### Pin budget
6 (panel) + 1 (MUX_SEL) + 1 (probe) + 2 (mode + 2D/3D switches) + 3 (pots) + 2 (wall+clear)
+ 2 (UART) = **17 pins** of ~24 usable → comfortable, all on non-strapping GPIOs, ~2 spare.
(Splitting mode/2D-3D off the single R/2R pin costs +1 pin; the 4 view pots stay cut.)

### Power rails
- **5 V** (USB): DG413 V+, and the Mode-1 conducting-sheet centre electrode.
- **CTRL_3V3** (5 V → divider → MCP6002 follower): tops of the pots (the ESP32 3V3 pin is
  weak ~2.9 V). The mode/2D-3D/wall/clear switches use the ESP32 internal pull-ups.
- **GND** common to ESP32, DG413, both panels, sheet edges, and the PYNQ.
- Touch-panel X+/Y+ HIGH drive comes from GPIOs (through the DG413), not `CTRL_3V3`.

## 7. Coordinate output (calibrated on the ESP32)
X → **0–1023** over 16.4 cm, Y → **0–612** over 9.8 cm (≈6.24 counts/mm both axes → square
gestures). The firmware **auto-calibrates per panel**: it learns each axis's raw min/max
(in mV) from firm presses, maps with a 6% edge-margin clamp (so the noisy boundary reads a
steady 0/full), and stores a separate calibration set for Panel 1 and Panel 2. Sweep each
panel's edges once after boot. No manual paste. The PYNQ just scales 0–1023 / 0–612 → the
64×64 grid.

## 8. UART protocol (ESP32 → PYNQ)
Identical 21-byte frame to the base design (so the FPGA parser is unchanged). Header `0xAA`;
flags byte (bit0 mode, bit1 2D/3D, bits2-3 field, bit4 wall, bit5 clear, bit6 touch-valid);
Panel X (calibrated 0–1023), Panel Y (0–612), amplitude, conductivity, probe; **yaw/pitch/
zoom/Zscale bytes are 0** in this build; byte 20 = XOR checksum of bytes 1..19. When touch
is invalid (incl. before a panel is calibrated), Panel X/Y are 0 and bit6 is clear.

## 9. Firmware
Canonical source: `arduino/esp32_inputs_dg413/esp32_inputs_dg413.ino` (Arduino IDE,
"ESP32 Dev Module"). It reads the mode & 2D/3D switches, sets `MUX_SEL`, settles, reads the active
panel on the shared 6-pin port (split sense + `analogReadMilliVolts` + per-panel auto-cal),
reads the 3 pots + probe + wall + clear, and sends the 21-byte frame at ~50 Hz.

## 10. PYNQ side
Open the serial device, sync on `0xAA`, verify the XOR checksum, unpack per §8, scale the
panel coords (`gx = X*63/1023`, `gy = Y*63/612`) and pots, and write the FDTD/render
registers; only act on a source/boundary when bit6 (touch-valid) is set. Ignore the zeroed
yaw/pitch/zoom/Zscale slots (use a fixed 3-D view, or defaults).

## 11. Key decisions
| Decision | Why |
|---|---|
| DG413 to share one panel port | Only one panel is live at a time; 2 NC+2 NO = two SPDT from one select line, no inverter; Ron ≈ 35 Ω flat (linear). |
| Mux only X+/Y+, share X-/Y- | Idle panel's "+" lines open → inert; needs just one quad switch. |
| Mode & 2D/3D on separate switch pins | No R/2R network; each read directly with a digital pin; costs +1 pin but still fits comfortably. |
| 6-pin split drive/sense | Sense on clean input-only ADC pins → low leakage → linear coordinates. |
| `analogReadMilliVolts` + per-panel auto-cal | Linearises the ADC and removes manual calibration; X 0–1023 / Y 0–612. |
| Drop yaw/pitch/zoom/Zscale | Keeps the pinout on non-strapping GPIOs with margin; 3-D view becomes fixed. |
| DG413 on 5 V | It is not a 3.3 V part; signals 0–3.3 V fit in 0–5 V; TTL logic accepts 3.3 V select. |

---
*Variant of the Analog/MCU subsystem. See `pin_connections.md` for the full wiring incl.
the DG413, and `../hardware/overview.md` for the original double-duty design.*
