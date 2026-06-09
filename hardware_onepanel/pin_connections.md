# Pin Connections (`hardware_onepanel` — one ESP32, one panel)

One ESP32, one directly-wired touch panel that serves both modes (no DG413, no 2nd board).
Source of truth: `overview.md`. Connector image: `../hardware/resistivetouchpanel.jpg`.

---

## Power
| Rail | Source | Feeds |
|------|--------|-------|
| **5 V** | USB | MCP6002 V+ (rail buffer + probe buffer); conducting-sheet centre |
| **CTRL_3V3** | 5 V → 1.7k/3.3k divider → MCP6002 follower | pot tops |
| **GND** | common | ESP32, MCP6002, panel, sheet edges, **PYNQ** |

Switches use the ESP32 internal pull-ups. The ESP32's own weak 3V3 pin is not the control
reference — `CTRL_3V3` (buffered) is.

## Pin map (20 pins — now with the 4 view pots)
| GPIO | Direction | Connects to |
|------|-----------|-------------|
| 18 | Output | Panel **X+ drive** (HIGH on X-layer read) |
| 32 | ADC1 in | Panel **X+ sense** → long/X axis; INPUT_PULLUP for touch detect |
| 23 | Output | Panel **X- drive** (LOW on X-layer read) |
| 25 | Output | Panel **Y+ drive** (HIGH on Y-layer read) |
| 35 | ADC1 in (input-only) | Panel **Y+ sense** → short/Y axis |
| 22 | Output | Panel **Y- drive** (LOW on Y-layer read) |
| 34 | ADC1 in (input-only) | Probe → MCP6002 buffer → 18k/33k divider |
| 13 | ADC2 | **Amplitude** pot |
| 33 | ADC1 | **Conductivity** pot |
| 4  | ADC2 | **Field-type** pot (E/B/S) |
| 27 | ADC2 | **Yaw** pot (3D view) |
| 14 | ADC2 | **Pitch** pot (3D view) |
| 26 | ADC2 | **Zoom** pot (3D view) |
| 36 | ADC1 in (input-only) | **Zscale** pot (3D view) — **GPIO36/VP, confirm it's on your board** |
| 21 | Input (pull-up) | **Mode 1/2** switch (LOW = Mode 2) |
| 19 | Input (pull-up) | **2D/3D** switch (LOW = 3D) |
| 5  | Input (pull-up) | **Wall/Source** switch (LOW = wall) — *GPIO5 strapping, OK* |
| 15 | Input (pull-up) | **Clear** button (active LOW) — *GPIO15 strapping, OK for idle-high button* |
| 17 | UART2 TX | → PYNQ Arduino header D0 (RX) |
| 16 | UART2 RX | ← PYNQ Arduino header D1 (TX) |

This **maxes out the ESP32**: 10 ADC inputs (2 panel senses + probe + 7 pots) and 10 digital.
It uses the input-only **GPIO36/VP** for the Zscale pot, and **two strapping pins** (GPIO5 =
wall, GPIO15 = clear) — both are safe choices (5 tolerates a low at boot; 15 idles high via
its pull-up). Spare: only 0, 2, 12 (strapping) and 39 (absent on your board). If GPIO36/VP is
*also* missing, ping me and I'll switch the panel to the 4-pin double-duty scheme (frees 2
pins, drops both strapping pins).

## Panel — how many ADC / DAC?
The 6 panel pins are **4 digital-output drives** (18, 23, 25, 22) + **2 ADC sense inputs**
(32, 35). **No DAC** — a drive is just `digitalWrite(HIGH)` (~3.3 V), not an analog level.
You need **2 ADC** because the floating layer you sense differs per axis (X+ for one axis,
Y+ for the other). GPIO32 must be a pin with an internal pull-up (for touch detect); GPIO35
is input-only (sense only).

## Panel connector (per the image)
pin1=Y1, pin2=X1, pin3=Y2, pin4=X2:
```
X2 (pin4) -> X+ : GPIO18 (drive) + GPIO32 (sense)
X1 (pin2) -> X- : GPIO23
Y2 (pin3) -> Y+ : GPIO25 (drive) + GPIO35 (sense)
Y1 (pin1) -> Y- : GPIO22
```
**Axis mapping:** the Y-layer (Y1/Y2) is the 16.4 cm **long** edge → reported as **X**; the
X-layer (X1/X2) is the 9.8 cm **short** edge → reported as **Y**. The firmware already swaps
this in software. (If your panel is rotated, swap the connector pairs.)

**Output = a 64 × 38 grid cell.** The firmware first maps the press to a calibrated full-scale
(**X 0–1023** long edge, **Y 0–612** short edge), then fits that to the grid, nearest cell →
**X 0–63, Y 0–37**, and sends the **grid cell** in the Panel X/Y bytes. The PS receives the grid
cell and uses it directly (no scaling). It reaches the PS over **UART2 → PS**, which then
forwards the frame as a **UDP** payload to the renderer (the ESP32 can't do UDP — WiFi is off).

**Calibration (2 corners, saved to flash):** corners read ~20–960 raw, never 0/full, so set
the range by **pressing one corner, then the opposite corner**. The firmware takes the
per-axis min/max so the corners map to the grid edges, and stores it in NVS. **Recalibrate:**
hold **Clear** (GPIO15) at power-up, or send **`c`** on the Serial Monitor. First boot with no
saved calibration runs it automatically.

## Probe / conducting sheet (Mode 1)
Sheet centre → +5 V, four edges → GND; probe wire → MCP6002 A IN+, 10 MΩ to GND; A OUT → IN-
(follower) → 18 k → node → 33 k → GND; node → GPIO34. The conducting sheet lies on the panel
so the panel reads the probe's XY while GPIO34 reads V(x,y).

## UART to PYNQ
One board → one UART: GPIO17 (TX) → PYNQ D0 (RX); GPIO16 (RX) ← PYNQ D1 (TX); common GND.
PYNQ header is **3.3 V** — never 5 V.

## Hard wiring rules
1. **Common GND** across ESP32, MCP6002, panel, sheet edges, PYNQ.
2. **3.3 V only on the PYNQ header.**
3. **WiFi OFF** (ADC2 channels in use).
4. Conducting sheet: centre = +5 V, edges = GND; probe ≤5 V scaled to ≤3.3 V by 18k/33k.
