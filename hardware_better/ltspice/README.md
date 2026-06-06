# LTSpice — `hardware_better` (DG413 two-panel)

Sectioned schematics for the improved front-end. Each `.asc` is self-contained and runs a
`.op` on open. Where a section needs the buffered rail, a local `CTRL_3V3` source stands in
for it (built for real in `power_3v3_rail.asc`). Layout uses wide gaps so the auto
InstName/Value labels and net flags don't overlap.

## Schematics
| File | Section |
|------|---------|
| `dg413_panel_mux.asc` | **The new bit** — the DG413 routing the shared X+/Y+ lines to Panel 1 (Mode 1) or Panel 2 (Mode 2), with X-/Y- common. Modelled as **2 NC + 2 NO** manual switches on one select (`sel`). Two simple panel networks show the active one conducts and the idle one is isolated. |
| `pots.asc` | The 3 fitted pots (amplitude, conductivity, field-type) off `CTRL_3V3`. |
| `switches.asc` | Mode (21), 2D/3D (26), Wall (27) switches + Clear (14) button, pulled up to `CTRL_3V3`. |
| `power_3v3_rail.asc` | 5 V → 18k/33k → MCP6001 follower → `CTRL_3V3` (copied from `../../hardware/ltspice`). |
| `probe_sheet.asc` | Mode-1 conducting sheet + probe buffer + 18k/33k divider → GPIO34. |

## The DG413 model
The real part is a DG413 (quad SPST: 2 normally-closed + 2 normally-open). Here it is built
from the `MANUAL_SPST_NC` / `MANUAL_SPST_NO` models so it simulates without a vendor SPICE
file: `XNC`/`YNC` (Panel 1) and `XNO`/`YNO` (Panel 2), all driven by one parameter `sel`
(= the mode line / GPIO19):
- `sel = 0` → NC closed, NO open → **Panel 1** (Mode 1)
- `sel = 1` → NC open, NO closed → **Panel 2** (Mode 2)

On the real board: tie all four DG413 control inputs to MUX_SEL; power the DG413 from **5 V**
(signals 0–3.3 V sit inside that); its TTL logic inputs accept the 3.3 V select. *Confirm the
NC/NO polarity against the DG413 truth table and flip `sel`/`MUX_SEL` if needed.*

## Tuning knobs (`.param`)
- `dg413_panel_mux.asc`: `sel` (0/1), `TOUCH1`/`TOUCH2` (0/1), `RPANEL`, `RCONTACT`.
- `pots.asc`: `wiper` (0–1).
- `switches.asc`: set a switch's `STATE`/`PRESS` to 1 to simulate it active.

## Libraries & symbols (shared, copied from the base design)
`MCP6001.lib` + `MCP6001.asy` (op-amp), `ManualSwitch.lib` + `MANUAL_*.asy` (switch/button
models — also used to model the DG413). Model files load automatically via each symbol's
`ModelFile` attribute, so no `.include` is needed.

See `../overview.md` §3/§6 and `../pin_connections.md` for the wiring this represents.
