# EE2 FDTD EM Wave Simulator — Overview (`hardware_onepanel`)

> Simplest variant of the Analog/MCU subsystem: **one ESP32, one touch panel** for both
> modes. Because only one mode runs at a time, a single panel serves both — so there is **no
> DG413 mux** (vs `../hardware_better`) and **no second board** (vs `../hardware_2boards`).
> Connector image: `../hardware/resistivetouchpanel.jpg`.

---

## 1. The idea
Only one mode is ever active, and both modes just need an XY touch position from a panel:
- **Mode 1** — the conducting sheet lies **on top of** the panel; you press the probe through
  it, the panel reports the probe's **XY**, and the probe's ADC reports the local potential
  V(x,y).
- **Mode 2** — a stylus on the **same** panel sets the source / wall / erase position.

So one physical panel covers both. One ESP32 reads that panel + all the controls and sends
the 21-byte frame to the PYNQ. No mux, no two-board UART arbitration, no pin pressure.

## 2. Platform
ESP32-WROOM-32 ×1, Arduino IDE 2.x ("ESP32 Dev Module"). PYNQ-Z1 over UART2 @ 115200 8N1,
21-byte frame @ ~50 Hz (same protocol as the base design). WiFi OFF (ADC2 in use). Controls
run off the buffered **CTRL_3V3** rail (5 V → MCP6002).

## 3. Controls (all on the one board)
| Control | Pins | Active in |
|---|---|---|
| **Touch panel** (4-wire, 6-pin split sense) | 18/32/23/25/35/22 | both |
| **Probe** + conducting sheet | 34 | Mode 1 |
| **Amplitude / Conductivity / Field-type** pots | 13 / 33 / 4 | Mode 2 |
| **Yaw / Pitch / Zoom / Zscale** pots (3D view) | 27 / 14 / 26 / 36 | both |
| **Wall/Source** switch, **Clear** button | 5 / 15 | Mode 2 |
| **Mode 1/2** switch, **2D/3D** switch | 21 / 19 | both |
| UART2 TX / RX | 17 / 16 | both |

The panel is read every loop; the **mode switch** tells the PYNQ how to interpret the touch
(probe boundary in Mode 1, source/wall in Mode 2). All 7 pots are fitted (the 3D-view pots
are read in both modes). Fitting them maxes out the board — see §4.

## 4. Pin map
| GPIO | Role | Type |
|---|---|---|
| 18 | Panel X+ drive | digital out |
| 32 | Panel X+ sense → long/X axis; pull-up → touch detect | ADC1 |
| 23 | Panel X- drive | digital out |
| 25 | Panel Y+ drive | digital out |
| 35 | Panel Y+ sense → short/Y axis | ADC1 (input-only) |
| 22 | Panel Y- drive | digital out |
| 34 | Probe → MCP6002 buffer → 18k/33k | ADC1 (input-only) |
| 13 | Amplitude pot | ADC2 |
| 33 | Conductivity pot | ADC1 |
| 4  | Field-type pot (E/B/S) | ADC2 |
| 27 | Yaw pot (3D view) | ADC2 |
| 14 | Pitch pot (3D view) | ADC2 |
| 26 | Zoom pot (3D view) | ADC2 |
| 36 | Zscale pot (3D view) | ADC1 (input-only, **VP**) |
| 21 | Mode 1/2 switch (LOW = Mode 2) | digital in (pull-up) |
| 19 | 2D/3D switch (LOW = 3D) | digital in (pull-up) |
| 5  | Wall/Source switch (LOW = wall) | digital in (pull-up) — **strapping** |
| 15 | Clear button (active LOW) | digital in (pull-up) — **strapping** |
| 17 / 16 | UART2 TX / RX → PYNQ | UART |

**20 pins** of ~24 usable — this **maxes out the board**: 10 ADC inputs (2 panel senses +
probe + 7 pots) and 10 digital. It uses **GPIO36/VP** (input-only) for the Zscale pot and
**two strapping pins** (GPIO5 = wall, GPIO15 = clear) — both safe (5 tolerates a low at boot;
15 idles high via its pull-up). The panel still needs **2 ADC** (senses on 32 & 35) and
**0 DAC**. Power: 5 V (USB), CTRL_3V3 (MCP6002), GND common (incl. the PYNQ).
*Confirm GPIO36/VP exists on your board (sibling of GPIO39/VN, which yours lacks); if not,
the 4-pin double-duty panel scheme frees 2 pins and drops the strapping pins.*

## 5. Panel read, grid output & calibration
Per loop: touch-detect (drive Y- low, read X+ via pull-up), then read the two coordinates by
driving one layer and ADC-sensing the floating layer (`analogReadMilliVolts()`, linearised).
The raw mV is mapped in two steps: first to a **calibrated full-scale** (**X 0–1023** over the
16.4 cm long edge, **Y 0–612** over the 9.8 cm short edge), then **fitted to a 64 × 38 grid**,
nearest cell → **X 0–63, Y 0–37**. The PS receives that **grid cell**. So a press nearest cell
(3, 4) is sent as X=3, Y=4. (`X_FULL`/`Y_FULL` and `GRID_X`/`GRID_Y` are #defines at the top.)

**Two-corner calibration:** a resistive panel never reaches 0 / full at the edges (corners
read ~20–960 raw), so the firmware learns the range from two presses — **press one corner,
then the opposite corner.** It takes the per-axis min/max of those two reads, so the corners
map to the grid extremes. The calibration is **saved to flash (NVS)** and reloaded on boot.
**Recalibrate** by holding the **Clear** button at power-up, or sending **`c`** on the Serial
Monitor. (On first boot with no saved calibration it runs automatically.)

## 6. UART protocol & transport to the PS
**Transport:** ESP32 → **UART2 (115200 8N1)** → PYNQ **PS**. The PS reads the frame and
**forwards it as the UDP payload** to the renderer. The ESP32 can't send UDP itself (that needs
WiFi, which is off because ADC2 is in use), so the UDP step lives on the PS.

Same 21-byte frame as the base design (header `0xAA`, flags, Panel X/Y, amplitude,
conductivity, probe, yaw/pitch/zoom/Zscale, XOR checksum) — but **Panel X/Y now carry the
64×38 grid cell (X 0–63, Y 0–37)** instead of 0–1023/0–612, so the PS uses them directly (no
scaling). The byte layout (also the UDP payload):

| Byte | Field | Range |
|---|---|---|
| 0 | header `0xAA` | — |
| 1 | flags: b0 mode2, b1 3D, b2-3 field (0=E 1=B 2=S), b4 wall, b5 clear, **b6 touch-valid** | — |
| 2-3 | **Panel X grid cell** | 0–63 |
| 4-5 | **Panel Y grid cell** | 0–37 |
| 6-7 | amplitude | 0–1023 |
| 8-9 | conductivity | 0–1023 |
| 10-11 | probe (Mode 1) | 0–1023 |
| 12-13 / 14-15 / 16-17 / 18-19 | yaw / pitch / zoom / Zscale | 0–1023 each |
| 20 | checksum = XOR of bytes 1–19 | — |

When **touch-valid (b6) is 0**, Panel X/Y are 0 → the PS should not place a point. One board
fills everything: mode/2D-3D/field/wall/clear/touch + Panel X-Y; probe in Mode 1,
amplitude/conductivity in Mode 2; yaw/pitch/zoom/Zscale carry the 3D-view pots; it transmits
every frame. *(Coordinate the grid-cell byte meaning with the FPGA team.)*

## 7. Firmware
`arduino/esp32_inputs/esp32_inputs.ino` (one sketch). Plus `arduino/panel_extrapins_test/`
and `arduino/controls_test/` for bring-up. Each loop: read the mode/2D-3D switches, read the
panel (split sense + `analogReadMilliVolts`, quantise to the 64×38 grid using the saved
2-corner calibration), read the pots/probe/switches, send the frame at ~50 Hz.

## 8. Key decisions
| Decision | Why |
|---|---|
| One panel for both modes | Only one mode runs at a time; in Mode 1 the sheet lies on the panel. Removes the 2nd panel, the DG413 mux, and the 2nd board. |
| One ESP32 | All inputs fit in 16 pins; one UART, one frame, no arbitration. |
| 6-pin split drive/sense, `analogReadMilliVolts` | Linear, repeatable panel coordinates. |
| Output a 64×38 grid cell, 2-corner calibration (saved to NVS) | The ESP32 does the quantising; corners map to grid extremes; survives reboots. |
| Mode/2D-3D on separate switch pins | Read directly, no R/2R network. |

---
*One-board / one-panel variant. See `pin_connections.md` for wiring; `../hardware_better`
(DG413, two panels) and `../hardware_2boards` (two boards) for the alternatives.*
