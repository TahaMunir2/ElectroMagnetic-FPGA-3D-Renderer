# LTSpice — `hardware_onepanel` (one board, one panel)

Sectioned schematics for the single-board / single-panel front-end. There's **no DG413 mux**
(only one panel, wired directly) and **no second board**. Each `.asc` is self-contained and
runs a `.op` on open; wide gaps keep labels clear. Where a section needs the buffered rail,
a local `CTRL_3V3` source stands in for it.

## Schematics
| File | Section |
|------|---------|
| `touch_panel.asc` | The one 4-wire resistive panel, 6-pin split drive/sense, directly wired. Shown in the read-X phase. |
| `power_3v3_rail.asc` | 5 V → 18k/33k → MCP6001 follower → `CTRL_3V3`. |
| `pots.asc` | Amplitude / conductivity / field-type pots off `CTRL_3V3`. |
| `switches.asc` | Mode (21), 2D/3D (26), Wall (27) + Clear (14) pulled up to `CTRL_3V3`. |
| `probe_sheet.asc` | Conducting sheet + probe buffer + 18k/33k → GPIO34 (Mode 1). |

All of these sit on the **one** board now (no mux, no per-board split).

## Tuning knobs (`.param`)
- `touch_panel.asc`: `RPANEL`, `KX`, `KY`, `TOUCH`, `RCONTACT`.
- `pots.asc`: `wiper` (0–1).
- `switches.asc`: set a switch's `STATE`/`PRESS` to 1 to simulate it active.
- `probe_sheet.asc`: `RSHEET`, `FRAC`.

## Libraries & symbols (shared)
`MCP6001.lib` + `MCP6001.asy`, `ManualSwitch.lib` + `MANUAL_*.asy`. Model files auto-load via
each symbol's `ModelFile` attribute — no `.include` needed.

See `../overview.md` and `../pin_connections.md` for the wiring this represents.
