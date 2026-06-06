#!/usr/bin/env python3
"""
EE2 FDTD EM Wave Simulator -- enclosure generator (trimesh).

Builds a single-piece, open-bottom console cover:
  * recessed window for touch panel 1 (164 x 98 mm) with a supporting lip,
  * a large open bay so the PYNQ-Z1 FPGA stays uncovered/accessible,
  * a front strip of holes for the 7 pots, 3 toggle switches and the clear button,
  * a cable slot in the back wall.

The same dimensions are mirrored in `enclosure_fusion360.py` and `enclosure.scad`.
Run with a Python that has trimesh + manifold3d:  python enclosure_build.py
Outputs enclosure.stl next to this file. All units are millimetres.
"""
import os
import trimesh

# ---------------- parameters (mm) -------------------------------------------
WALL        = 3.0      # side-wall thickness
TOP_T       = 5.0      # top-plate thickness
H           = 55.0     # overall height (internal clearance ~ H - TOP_T)

PANEL_W     = 164.0    # touch panel 1 outline (16.4 cm)
PANEL_H     = 98.0     # touch panel 1 outline (9.8 cm)
PANEL_RECESS= 2.6      # depth of the top recess the panel drops into (>= panel thickness)
PANEL_LIP   = 4.0      # width of the shelf that supports the panel edge

FPGA_W      = 120.0    # open bay for the PYNQ-Z1 (exposed)
FPGA_D      = 90.0

POT_D       = 7.0      # pot bushing hole
TOGGLE_D    = 6.0      # mini SPDT toggle hole
BUTTON_D    = 12.0     # momentary clear button hole

EDGE        = 8.0      # margin from inner wall to features
GAP         = 12.0     # gap between panel window and FPGA bay
FRONT_STRIP = 46.0     # depth of the front control strip
MID_GAP     = 12.0     # gap between control strip and panel
BACK_MARGIN = 10.0     # margin behind the panel / FPGA bay
CTRL_FRONT  = 24.0     # control-row centre, measured back from the inner front wall

CABLE_W     = 40.0     # back-wall cable slot width
CABLE_H     = 22.0     # back-wall cable slot height

# control layout, left -> right (name, hole diameter)
CONTROLS = [
    ("yaw", POT_D), ("pitch", POT_D), ("zoom", POT_D), ("zscale", POT_D),
    ("amp", POT_D), ("cond", POT_D), ("field", POT_D),
    ("mode", TOGGLE_D), ("disp", TOGGLE_D), ("wall", TOGGLE_D),
    ("clear", BUTTON_D),
]

# ---------------- derived footprint -----------------------------------------
PANEL_CX = WALL + EDGE + PANEL_W / 2
FPGA_CX  = WALL + EDGE + PANEL_W + GAP + FPGA_W / 2
W        = FPGA_CX + FPGA_W / 2 + EDGE + WALL

PANEL_CY = WALL + FRONT_STRIP + MID_GAP + PANEL_H / 2
BACK_EDGE = PANEL_CY + PANEL_H / 2
FPGA_CY  = BACK_EDGE - FPGA_D / 2
D        = BACK_EDGE + BACK_MARGIN + WALL

CTRL_Y   = WALL + CTRL_FRONT


def box(size, center):
    m = trimesh.creation.box(extents=size)
    m.apply_translation(center)
    return m


def cyl(d, h, center):
    m = trimesh.creation.cylinder(radius=d / 2.0, height=h, sections=64)
    m.apply_translation(center)
    return m


def build():
    # shell: outer solid minus inner cavity (open bottom, TOP_T plate on top)
    outer = box([W, D, H], [W / 2, D / 2, H / 2])
    inner = box([W - 2 * WALL, D - 2 * WALL, (H - TOP_T) + 1],
                [W / 2, D / 2, ((H - TOP_T) - 1) / 2])
    shell = outer.difference(inner)

    cuts = []
    # panel recess pocket (top surface) + through window with a supporting lip
    cuts.append(box([PANEL_W + 0.8, PANEL_H + 0.8, PANEL_RECESS + 1],
                    [PANEL_CX, PANEL_CY, H - PANEL_RECESS + (PANEL_RECESS + 1) / 2]))
    cuts.append(box([PANEL_W - 2 * PANEL_LIP, PANEL_H - 2 * PANEL_LIP, TOP_T + 2],
                    [PANEL_CX, PANEL_CY, H - TOP_T / 2]))
    # FPGA open bay (through the top)
    cuts.append(box([FPGA_W, FPGA_D, TOP_T + 2], [FPGA_CX, FPGA_CY, H - TOP_T / 2]))
    # control holes (through the top)
    n = len(CONTROLS)
    x0, x1 = WALL + 18.0, W - WALL - 18.0
    for i, (name, dia) in enumerate(CONTROLS):
        x = x0 + (x1 - x0) * i / (n - 1)
        cuts.append(cyl(dia, TOP_T + 4, [x, CTRL_Y, H - TOP_T / 2]))
    # back-wall cable slot
    cuts.append(box([CABLE_W, WALL + 2, CABLE_H],
                    [W / 2, D - WALL / 2, H - TOP_T - CABLE_H / 2]))

    body = shell.difference(trimesh.util.concatenate(cuts))
    return body


def write_top_svg(path, s=2.0):
    """Top-view layout preview (y drawn downward = front at top)."""
    def R(x, y, w, h, **kw):
        a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
        return f'<rect x="{x*s:.1f}" y="{y*s:.1f}" width="{w*s:.1f}" height="{h*s:.1f}" {a}/>'
    el = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W*s+40:.0f}" height="{D*s+60:.0f}">',
          f'<g transform="translate(20,20)">',
          R(0, 0, W, D, fill="#f4f4f4", stroke="#222", stroke_width=1.5),
          R(WALL, WALL, W - 2 * WALL, D - 2 * WALL, fill="none", stroke="#bbb", stroke_width=1)]
    el.append(R(PANEL_CX - PANEL_W / 2, PANEL_CY - PANEL_H / 2, PANEL_W, PANEL_H,
                fill="#cfe8ff", stroke="#2b6cb0", stroke_width=1.2))
    el.append(R(PANEL_CX - (PANEL_W - 2 * PANEL_LIP) / 2, PANEL_CY - (PANEL_H - 2 * PANEL_LIP) / 2,
                PANEL_W - 2 * PANEL_LIP, PANEL_H - 2 * PANEL_LIP, fill="#fff", stroke="#2b6cb0",
                stroke_width=1, stroke_dasharray="4 3"))
    el.append(f'<text x="{PANEL_CX*s:.0f}" y="{PANEL_CY*s:.0f}" font-size="11" text-anchor="middle">panel 1 164x98</text>')
    el.append(R(FPGA_CX - FPGA_W / 2, FPGA_CY - FPGA_D / 2, FPGA_W, FPGA_D,
                fill="#ffe6cc", stroke="#c05621", stroke_width=1.2))
    el.append(f'<text x="{FPGA_CX*s:.0f}" y="{FPGA_CY*s:.0f}" font-size="11" text-anchor="middle">FPGA bay (open)</text>')
    n = len(CONTROLS)
    x0, x1 = WALL + 18.0, W - WALL - 18.0
    for i, (name, dia) in enumerate(CONTROLS):
        x = x0 + (x1 - x0) * i / (n - 1)
        el.append(f'<circle cx="{x*s:.1f}" cy="{CTRL_Y*s:.1f}" r="{dia/2*s:.1f}" fill="#ddd" stroke="#333"/>')
        el.append(f'<text x="{x*s:.1f}" y="{(CTRL_Y+12)*s:.1f}" font-size="9" text-anchor="middle">{name}</text>')
    el.append(R(W / 2 - CABLE_W / 2, D - WALL, CABLE_W, WALL, fill="#333"))
    el.append(f'<text x="{(W/2)*s:.0f}" y="{(D+10)*s:.0f}" font-size="9" text-anchor="middle">cable slot</text>')
    el.append("</g></svg>")
    with open(path, "w") as f:
        f.write("\n".join(el))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    mesh = build()
    out = os.path.join(here, "enclosure.stl")
    mesh.export(out)
    write_top_svg(os.path.join(here, "enclosure_layout_top.svg"))
    print(f"footprint  W x D x H = {W:.1f} x {D:.1f} x {H:.1f} mm")
    print(f"watertight = {mesh.is_watertight}   winding_ok = {mesh.is_winding_consistent}")
    print(f"volume = {mesh.volume/1000:.1f} cm^3   triangles = {len(mesh.faces)}")
    print(f"bounds = {mesh.bounds.tolist()}")
    print(f"wrote {out}")
