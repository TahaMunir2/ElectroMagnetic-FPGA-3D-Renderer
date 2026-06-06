# Breadboard wiring — `hardware_better` (DG413 two-panel)

A `.fzz` can't be generated outside Fritzing (it bundles part GUIDs + geometry), so this is
the build/wiring recipe: drop the parts in Fritzing (or on a real breadboard) and make the
connections below. See `breadboard_diagram.svg` for the picture. Matches `pin_connections.md`.

## Parts
- ESP32-WROOM-32 DevKit (38-pin) — straddles the centre trench.
- **DG413** quad analog switch (the panel mux) — powered from **5 V**.
- **MCP6002** dual op-amp — half A = probe buffer, half B = CTRL_3V3 rail buffer.
- 3 × 10 kΩ potentiometers (amplitude, conductivity, field-type).
- 4 × switches/buttons (mode, 2D/3D, wall, clear).
- 2 × 4-wire resistive touch panels (Würth FPC breakouts).
- Resistors: 1.7 kΩ + 3.3 kΩ (rail divider), 18 kΩ + 33 kΩ (probe divider), 10 MΩ (probe
  pull-down). Caps: 100 nF across each IC's V+/GND.
- Mode-1 conducting sheet (centre = +5 V, edges = GND).

## Power rails (breadboard side strips)
| Rail | Colour | Source | Goes to |
|------|--------|--------|---------|
| **+5 V** | red | ESP32 `5V`/`VIN` pin (USB) | DG413 V+, MCP6002 V+, rail divider top, sheet centre |
| **CTRL_3V3** | orange | MCP6002 (half B) output | all pot tops |
| **GND** | black | ESP32 `GND` | everything's ground (ESP32, DG413, MCP6002, pots, switches, panels, sheet edges, PYNQ) |

> The ESP32's own 3V3 pin is **not** used as the control reference (it's weak). CTRL_3V3 is
> the MCP6002-buffered 3.3 V. Switches use the ESP32 internal pull-ups, so they don't need
> CTRL_3V3 — only the pots do.

## CTRL_3V3 rail generator (MCP6002 half B)
```
+5V ──[1.7k]──┬──[3.3k]── GND          (divider ≈ 3.24 V at the tap)
              └── MCP6002 B  IN+ (pin 5)
MCP6002 B OUT (pin 7) ── CTRL_3V3 ── wired back to MCP6002 B IN- (pin 6)   (unity follower)
MCP6002  V+ (pin 8) = +5V ,  V- (pin 4) = GND ,  100 nF across pin8–pin4
```

## Probe / conducting sheet (Mode 1) — MCP6002 half A
```
Sheet centre pad ── +5V
Sheet four edges ── GND
Probe wire ── MCP6002 A IN+ (pin 3) ── 10 MΩ ── GND        (pull-down stops a floating probe)
MCP6002 A OUT (pin 1) ── MCP6002 A IN- (pin 2)             (unity follower)
MCP6002 A OUT ──[18k]──┬──[33k]── GND                       (scales ≤5 V probe to ≤3.3 V)
                       └── ESP32 GPIO34
```

## DG413 panel mux (the heart of this build)
DG413 = 2 NC + 2 NO switches. Tie **all control inputs to ESP32 GPIO19 (MUX_SEL)**.
Power V+ = **5 V**, GND = GND, 100 nF across them.
```
ESP32 GPIO18 (X+ drive) ─┐
ESP32 GPIO32 (X+ sense) ─┴─ DG413 COM_a ─┬─ NC_a ── Panel1 X+ (conn pin4 / X2)
                                         └─ NO_a ── Panel2 X+
ESP32 GPIO25 (Y+ drive) ─┐
ESP32 GPIO35 (Y+ sense) ─┴─ DG413 COM_b ─┬─ NC_b ── Panel1 Y+ (conn pin3 / Y2)
                                         └─ NO_b ── Panel2 Y+
ESP32 GPIO23 (X-) ────────────────────────► Panel1 X- AND Panel2 X-  (conn pin2 / X1)   [direct]
ESP32 GPIO22 (Y-) ────────────────────────► Panel1 Y- AND Panel2 Y-  (conn pin1 / Y1)   [direct]
ESP32 GPIO19 (MUX_SEL) ───────────────────► DG413 control inputs (all tied)
```
GPIO18 & GPIO32 share one breadboard node (the X+ COM); GPIO25 & GPIO35 share the Y+ COM.
*LOW = Panel 1 (NC) / HIGH = Panel 2 (NO) — confirm vs the DG413 truth table.*

## Pots (3) — each a 10 kΩ pot
| Pot | Top | Wiper → ESP32 | Bottom |
|-----|-----|---------------|--------|
| Amplitude | CTRL_3V3 | GPIO39 | GND |
| Conductivity | CTRL_3V3 | GPIO33 | GND |
| Field-type | CTRL_3V3 | GPIO4 | GND |

## Switches / button (4) — one side to ESP32, other side to GND
| Control | ESP32 pin | Other side | Notes |
|---------|-----------|-----------|-------|
| Mode 1/2 | GPIO21 | GND | internal pull-up; LOW = Mode 2 |
| 2D/3D | GPIO26 | GND | internal pull-up; LOW = 3D |
| Wall/Source | GPIO27 | GND | internal pull-up; LOW = wall |
| Clear (button) | GPIO14 | GND | internal pull-up; LOW = clear |

## UART to PYNQ (crossed over)
| ESP32 | PYNQ Arduino header |
|-------|---------------------|
| GPIO17 (TX) | D0 (RX) |
| GPIO16 (RX) | D1 (TX) |
| GND | GND (shared) |
> PYNQ header is 3.3 V — never feed it 5 V.

## Full ESP32 pin list (17 used)
| GPIO | Net | | GPIO | Net |
|---|---|---|---|---|
| 18 | X+ drive (DG413 COM_a) | | 4  | Field pot wiper |
| 32 | X+ sense (DG413 COM_a) | | 39 | Amp pot wiper |
| 23 | X- bus (both panels) | | 33 | Cond pot wiper |
| 25 | Y+ drive (DG413 COM_b) | | 27 | Wall switch |
| 35 | Y+ sense (DG413 COM_b) | | 14 | Clear button |
| 22 | Y- bus (both panels) | | 21 | Mode switch |
| 19 | MUX_SEL → DG413 | | 26 | 2D/3D switch |
| 34 | Probe (from 18k/33k) | | 17 | UART TX → PYNQ D0 |
|    |                        | | 16 | UART RX → PYNQ D1 |

## Suggested build order
1. Lay the power rails; bring ESP32 5V/GND and GND to the strips.
2. Build the MCP6002 CTRL_3V3 follower; verify ~3.3 V before wiring the pots.
3. Wire the DG413 (V+, GND, control, COMs, the 4 throws); X-/Y- direct to both panels.
4. Add panels, then pots/switches, then the probe/sheet divider.
5. UART to the PYNQ last. Decoupling caps on every IC.
