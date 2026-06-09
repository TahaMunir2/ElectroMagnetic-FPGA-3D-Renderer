# Breadboard wiring — `hardware_onepanel` (one ESP32, one panel)

A `.fzz` can't be generated outside Fritzing (it bundles part GUIDs + geometry), so this is
the build/wiring recipe. One board, one directly-wired panel — **no DG413, no 2nd board**.
See `breadboard_diagram.svg` for the picture. Matches `pin_connections.md`.

## Parts
- 1 × ESP32-WROOM-32 DevKit.
- **MCP6002** dual op-amp — half A = probe buffer, half B = CTRL_3V3 rail buffer.
- 3 × 10 kΩ pots (amplitude, conductivity, field-type).
- 4 × switches/buttons: mode, 2D/3D, wall, clear.
- 1 × 4-wire resistive touch panel (serves both modes).
- Resistors: 1.7 k + 3.3 k (rail divider), 18 k + 33 k (probe divider), 10 M (probe
  pull-down). 100 nF across each IC's V+/GND. Conducting sheet (centre +5 V, edges GND).

## Power
| Rail | Colour | Source | Feeds |
|------|--------|--------|-------|
| **+5 V** | red | ESP32 `5V`/USB | MCP6002 V+, rail divider, sheet centre |
| **CTRL_3V3** | orange | MCP6002 (half B) | pot tops |
| **GND** | black | common | ESP32, MCP6002, panel, sheet edges, **PYNQ** |

Switches use the ESP32 internal pull-ups.

## Panel (6-pin split sense, direct — no mux)
```
Panel X+ (conn pin4/X2) -> GPIO18 (drive) + GPIO32 (sense, pull-up -> touch)
Panel X- (conn pin2/X1) -> GPIO23 (drive)
Panel Y+ (conn pin3/Y2) -> GPIO25 (drive) + GPIO35 (sense)
Panel Y- (conn pin1/Y1) -> GPIO22 (drive)
```
GPIO18+32 share one node (X+); GPIO25+35 share one node (Y+). **Axis:** Y-layer = 16.4 cm
long edge -> X (0-1023); X-layer = 9.8 cm short edge -> Y (0-612) (swapped in firmware).

## Probe / conducting sheet (Mode 1)
Sheet centre -> +5 V, edges -> GND; probe -> MCP6002 A IN+ (pin 3), 10 M to GND; A OUT (pin 1)
-> IN- (pin 2) [follower] -> 18 k -> node -> 33 k -> GND; node -> GPIO34. The sheet lies on the
panel, so the panel reads the probe's XY while GPIO34 reads V(x,y).

## CTRL_3V3 rail (MCP6002 half B)
+5 V -> 1.7 k -> node -> 3.3 k -> GND; node -> MCP6002 B IN+ (pin 5); B OUT (pin 7) = CTRL_3V3
-> B IN- (pin 6). MCP6002 V+ (8) = 5 V, V- (4) = GND, 100 nF across.

## Pots (7) — each top = CTRL_3V3, bottom = GND, wiper -> a GPIO
| Pot | Wiper GPIO | | Pot | Wiper GPIO |
|---|---|---|---|---|
| Amplitude | 13 | | Yaw | 27 |
| Conductivity | 33 | | Pitch | 14 |
| Field-type | 4 | | Zoom | 26 |
| | | | Zscale | **36 / VP** (input-only) |

## Switches / button — one side to GPIO (internal pull-up), other side to GND
- Mode 1/2: GPIO21 (LOW = Mode 2)
- 2D/3D:   GPIO19 (LOW = 3D)
- Wall/Source: GPIO5  (LOW = wall)  — *GPIO5 is a strapping pin, OK here*
- Clear button: GPIO15 (active LOW) — *GPIO15 is a strapping pin, OK for an idle-high button*

> This maxes the ESP32: Zscale uses **GPIO36/VP** (input-only) and wall/clear sit on the two
> safe strapping pins (5, 15). Confirm GPIO36/VP exists on your board (sibling of the GPIO39
> you don't have); if not, switch the panel to the 4-pin double-duty scheme to free 2 pins.

## UART to the PYNQ
GPIO17 (TX) -> PYNQ D0 (RX); GPIO16 (RX) <- PYNQ D1 (TX); common GND. One board, one UART -
no gating. PYNQ header is **3.3 V** - never 5 V.

## Build order
1. Power rails + common GND (incl. the PYNQ).
2. MCP6002 CTRL_3V3 follower (verify ~3.3 V), then probe/sheet divider.
3. Panel (6 pins), then pots/switches off CTRL_3V3.
4. UART to the PYNQ. Decoupling caps on every IC.
