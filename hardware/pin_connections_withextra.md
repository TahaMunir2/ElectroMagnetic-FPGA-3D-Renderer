# Pin Connections — "extra-pins" panel scheme + shared-panel mux

Companion to `pin_connections.md`. This documents the wiring used by
`arduino/panel1_extrapins_test.ino/panel1_extrapins_test.ino`, where the touch panel's
**drive and sense are split onto separate pins** (instead of the double-duty "+" pins of the
main firmware), and answers: *do we have enough GPIOs for two panels, and if not, how do we
share pins between them?*

---

## A. Panel 1 wiring as tested (drive/sense separated)

Each "+" terminal is wired to **two** ESP32 pins — a push-pull **drive** pin and an
**ADC sense** pin. The "−" terminals are single drive pins. Y+ is driven by **DAC1** (a
plain digital HIGH also works; the DAC is optional).

| Panel terminal | Connector pin* | ESP32 **drive** | ESP32 **sense (ADC)** | Notes |
|---|---|---|---|---|
| **X+** | 4 (X2) | GPIO18 (HIGH on X-read) | GPIO32 (reads Y-coord; has pull-up → touch detect) | 2 pins on one terminal |
| **X−** | 2 (X1) | GPIO23 (LOW on X-read) | — | |
| **Y+** | 3 (Y2) | GPIO25 / DAC1 (~3.3 V on Y-read) | GPIO35 (reads X-coord; input-only, no pull-up) | 2 pins on one terminal |
| **Y−** | 1 (Y1) | GPIO22 (LOW on Y-read) | — | |

\* Connector pins from `resistivetouchpanel.jpg` (pin1=Y1, pin2=X1, pin3=Y2, pin4=X2).
"+/−" within a pair only sets coordinate **direction** — flip in software if mirrored.

**Pins per panel = 6** (4 drive + 2 sense), versus **4** for the double-duty scheme in
`pin_connections.md`. Why one might want it: the sense lines can sit on the clean
input-only ADC pins (34–39) and stay configured as ADC, and the drive is a separate
push-pull pin. The cost is **+2 pins per panel**.

---

## B. Are the pins enough?  → **No, not for two panels this way**

Full input set with the 6-pin scheme on **both** panels:

| Block | Pins |
|---|---:|
| Panel 1 (6-pin) | 6 |
| Panel 2 (6-pin) | 6 |
| 7 pots (yaw, pitch, zoom, Zscale, amp, cond, field) | 7 |
| Mode/2D-3D encoder (R/2R, 1 ADC) | 1 |
| Probe (1 ADC) | 1 |
| Wall switch + Clear button | 2 |
| UART2 to PYNQ (TX/RX) | 2 |
| **Total needed** | **25** |

The ESP32-WROOM-32 has 26 usable GPIOs (excluding flash 6–11), and you must keep GPIO1/3
for the USB serial console → **~24 practical**. So **25 > 24 — it does not fit**, and that
is before the harder constraints bite:

- Only **4 input-only ADC pins** (34, 35, 36, 39), yet this scheme wants many ADC inputs
  (4 panel senses + 7 pots + encoder + probe = **13 ADC**).
- The two **touch-detect** senses need an **internal pull-up**, so they cannot use 34–39 —
  they must be 32/33 or ADC2 pins.
- You'd be forced onto every strapping pin (0, 2, 12, 15), which is fragile at boot.

Conclusion: two independent 6-pin panels is over budget. (Note the original **4-pin
double-duty** scheme *does* fit two panels in 8 pins — see `pin_connections.md` — so one
option is simply to use that. The rest of this doc solves it for the 6-pin scheme.)

---

## C. Shared-panel mux (only one panel is live at a time)

You only ever read **panel 1 (Mode 1)** or **panel 2 (Mode 2)**, never both — so route one
ESP32 "panel port" to whichever panel the mode selects, with an **analog switch** steered by
a single mode line. Both panels then share the same 6 ESP32 pins.

### Minimal version — mux only the two "+" lines (recommended)
The "−" lines (X−, Y−) can be **tied common** to both panels; the idle panel is inert
because *its* X+/Y+ are disconnected (no current path, senses floating). So you only need to
switch **X+ and Y+** → a single **dual-SPDT** analog switch.

```
                 ┌──────── analog switch (dual SPDT) ────────┐
 GPIO18 drive ┐  │  SEL ── mode line (GPIO, 0=Mode1 / 1=Mode2)│
 GPIO32 sense ┴──┤ X+ common ──► Panel1.X+ (SEL=0)            │
                 │             └► Panel2.X+ (SEL=1)            │
 GPIO25 drive ┐  │                                            │
 GPIO35 sense ┴──┤ Y+ common ──► Panel1.Y+ / Panel2.Y+        │
                 └────────────────────────────────────────────┘
 GPIO23 (X−) ───────── both panels' X−   (common, no switch)
 GPIO22 (Y−) ───────── both panels' Y−   (common, no switch)
```

- **Switch select** is driven by the ESP32 from the decoded mode (1 GPIO out), so routing
  always matches the mode automatically — no manual sync.
- **Parts:** a low-Ron bilateral dual-SPDT such as **TI TS5A23159** (Ron ≈ 1 Ω, 3.3 V,
  bidirectional) — best, because the "+" line also carries drive current. The cheaper
  **74HC4053** (triple SPDT, Ron ≈ 100 Ω) works too; its series Ron just adds a *linear*
  offset that calibration/`analogReadMilliVolts` absorbs (lower Ron = more usable range).
- **Sense** rides the same muxed line (the ADC tap is high-impedance, so Ron there is
  irrelevant). Touch-detect's pull-up on GPIO32 still works through the switch.

### Conservative version — mux all four lines
If you'd rather not share X−/Y−, switch all four terminals → **two** dual-SPDT chips (or a
74HC4053 ×2), all selects tied to the one mode line. Costs an extra IC, no extra GPIO.

### Zero-IC alternative
Use a **mechanical 4PDT** (or DPDT for just X+/Y+) slide/toggle switch to route the lines
by hand. Costs **0 GPIOs and 0 ICs**, but the operator must set it to match the mode.

---

## D. Full-system pin budget **with the shared-panel mux**

| Function | GPIO | Type |
|---|---|---|
| Panel X+ drive | 18 | digital out |
| Panel X+ sense | 32 | ADC1 (pull-up → touch detect) |
| Panel X− drive (common) | 23 | digital out |
| Panel Y+ drive | 25 / DAC1 | out (DAC optional) |
| Panel Y+ sense | 35 | ADC1 (input-only) |
| Panel Y− drive (common) | 22 | digital out |
| **Mux select (= mode)** | 5 | digital out |
| Mode/2D-3D encoder | 36 | ADC1 (input-only) |
| Probe | 34 | ADC1 (input-only) |
| Pot ×7 (yaw,pitch,zoom,Zscale,amp,cond,field) | 33, 39, 4, 13, 14, 27, 26 | ADC |
| Wall switch | 19 | digital in (pull-up) |
| Clear button | 21 | digital in (pull-up) |
| UART2 TX / RX | 17 / 16 | UART |

**Total = 20 pins** of ~24 practical → fits, with 0/2/12/15 left spare. The mux saves the
5 pins that put the two-panel design over budget.

> Firmware change (when you implement it): decode the mode, set the **mux-select GPIO**,
> wait a settle, then run the existing read/touch routines on the single shared port — the
> idle/tri-state logic still applies. Encoder moves off GPIO35 (now a panel sense) to
> GPIO36. Calibrate with `panel1_test` per panel and store both sets.
