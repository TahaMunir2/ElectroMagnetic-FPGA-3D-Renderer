# Enclosure (3D-printable console cover)

A single-piece, open-bottom cover for the EE2 input console. The electronics mount to a
baseboard/bench; this cover drops over them and provides the panel surface and control
face. **The FPGA is left uncovered** (open bay) and the **pots/switches are exposed**
through a front row of holes.

Footprint: **318 × 172 × 55 mm** (W × D × H). See [enclosure_layout_top.svg](enclosure_layout_top.svg)
for the top-view layout.

## Files — three ways to get the model
| File | Use |
|------|-----|
| **`enclosure.stl`** | Ready-to-slice mesh (watertight, verified). Import straight into your slicer or Fusion. |
| **`enclosure_fusion360.py`** | **Fusion 360 script.** Utilities → Add-Ins → Scripts → `+` → pick this → Run. Builds the solid in a new design; edit the PARAMETERS block and re-run to resize. |
| **`enclosure.scad`** | OpenSCAD parametric model. Open, F5 preview / F6 render, Export STL. |
| `enclosure_build.py` | The trimesh generator that produced `enclosure.stl` + the SVG (needs `trimesh`+`manifold3d`). Edit + re-run to regenerate. |

All four share the **same parameter names and values**, so a change in one is easy to mirror.

## Layout (top face)
- **Touch panel 1** — recessed window, back-left. The panel (164 × 98 mm) drops into a
  `PANEL_RECESS` (2.6 mm) pocket and rests on a `PANEL_LIP` (4 mm) shelf; the active area
  shows through the window. In Mode 1 the conducting sheet lays on top of the panel.
- **FPGA open bay** — 120 × 90 mm cutout, back-right. The PYNQ-Z1 stays exposed (HDMI/USB/
  buttons accessible).
- **Control strip** — front row of 11 holes, left→right:
  `yaw pitch zoom zscale amp cond field` (7 pots, ⌀7 mm), `mode disp wall` (3 toggles,
  ⌀6 mm), `clear` (button, ⌀12 mm).
- **Cable slot** — 40 × 22 mm in the back wall for the UART / power / HDMI leads.

## Printing
- **Print upside-down** — top face on the bed. The holes and cutouts come out clean and
  no supports are needed (walls overhang nothing).
- **It is large (318 mm wide).** That exceeds a 220/256 mm bed. Options, all parametric:
  - print on a 300 mm+ bed;
  - shrink the FPGA bay (`FPGA_W/FPGA_D`) or margins (`EDGE`, `GAP`) to narrow it;
  - or split into a panel half + FPGA half (add a seam — ask and I'll parametrize it).
- Walls 3 mm, top plate 5 mm — fine in PLA/PETG at 0.2 mm layers, 3 perimeters.

## Assumptions (change these if wrong)
- **Hole diameters are nominal**: pot bushing ⌀7, mini-toggle ⌀6, button ⌀12. Measure your
  actual parts and adjust `POT_D / TOGGLE_D / BUTTON_D` — a loose pot bushing wobbles.
- **Panel thickness ~2.5 mm.** If your panel + FPC tail is thicker, raise `PANEL_RECESS`
  (and `TOP_T`, so the lip keeps ≥2 mm of material).
- **Only touch panel 1 is included** (the size you gave). Panel 2 (Mode 2) is not here —
  duplicate the panel-window block with its own `PANEL2_CX/CY` if you want it on this cover.
- **No internal standoffs** — it's a cover, not a tray. Mount boards to a baseboard, or ask
  me to add screw bosses for the ESP32 / op-amp board.
- Controls are a single front row; move/space them by editing the control loop or the
  `CTRL_FRONT` / hole-span (`x0,x1`) values.

To regenerate the STL after editing `enclosure_build.py`:
`python enclosure_build.py` (in a venv with `trimesh` and `manifold3d`).
