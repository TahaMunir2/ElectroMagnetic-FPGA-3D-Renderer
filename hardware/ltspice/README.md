# LTSpice — EE2 Analog/MCU section schematics

Sectioned schematics for the ESP32 input subsystem. Each `.asc` is self-contained and
runs a `.op` out of the box (open in LTSpice and hit Run). Where a section depends on the
buffered 3.3 V control rail, a local `CTRL_3V3` source stands in for it — the real rail is
built in `power_3v3_rail.asc`.

## Whole circuit
| File | Contents |
|------|----------|
| `circuit_design_manual.asc` | **The complete front-end on one sheet** — power rail, all 7 pots, mode/2D-3D encoder, conducting-sheet + probe buffer, both touch panels, and the wall/clear switches. Nets are named by ESP32 GPIO number; `VDD3V3` is the buffered rail. Runs `.op`. The section files below are the same blocks split out for focused study. |

## Section schematics
| File | Section | Notes |
|------|---------|-------|
| `power_3v3_rail.asc` | 5 V → buffered **CTRL_3V3** | 1.7k/3.3k divider + MCP6001 follower. The MCP6001 is one half of the MCP6002; the other half is the probe buffer. |
| `potentiometers.asc` | 7 control pots | yaw/pitch/zoom/Zscale/amp/conductivity + field-type, modelled as top/bottom dividers off `CTRL_3V3`. `.param wiper` sets position. |
| `mode_encoder.asc` | Mode + 2D/3D on one ADC pin | Two SPDT switches → 10k (MSB) / 20k (LSB) weighted DAC into GPIO35. Levels 0, ⅓, ⅔, 1 of 3.3 V. |
| `switches_buttons.asc` | Wall/Source switch + Clear button | Pulled up to `CTRL_3V3`; idle HIGH, active LOW. |
| `touch_panel.asc` | 4-wire resistive panel | Resistor-network model with a touch bridge; shown in the read-X phase. Panel 2 is identical on GPIO25/26/21/19. |
| `probe_paper.asc` | Mode-1 conducting sheet + probe | Centre electrode +5 V, edges GND; MCP6001 buffer + 18k/33k divider → GPIO34. |

## Libraries & symbols (shared)
| File | Purpose |
|------|---------|
| `MCP6001.lib` | Microchip MCP6001 op-amp model (P. Cheung). Two instances = one MCP6002. |
| `MCP6001.asy` | Schematic symbol for the above (pins: In+ In- V+ V- OUT). |
| `ManualSwitch.lib` | Parameter-controlled ideal switch/button models (STATE / PRESS). |
| `MANUAL_SPST_NO/NC`, `MANUAL_PUSH_NO/NC`, `MANUAL_SPDT` `.asy` | Symbols for the manual switches/buttons. |

Model files are pulled in automatically via each symbol's `ModelFile` attribute — no manual
`.include` needed (adding one would duplicate the subckt).

## Tuning knobs (`.param`)
- `potentiometers.asc`: `wiper` (0–1) — wiper fraction.
- `mode_encoder.asc` / `switches_buttons.asc`: set `STATE` / `PRESS` per switch instance.
- `touch_panel.asc`: `RPANEL`, `KX`, `KY` (touch position), `TOUCH` (0/1), `RCONTACT`.
- `probe_paper.asc`: `RSHEET`, `FRAC` (probe distance centre→edge; V(PROBE)=5·(1−FRAC)).

See `../overview.md` §6 (Power rails) and §15, and `../pin_connections.md` for the wiring.
