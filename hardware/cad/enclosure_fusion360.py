"""
EE2 FDTD EM Wave Simulator -- enclosure for Fusion 360.

HOW TO RUN
  Fusion 360 -> Utilities tab -> ADD-INS -> Scripts and Add-Ins -> Scripts ->
  green "+" -> pick this file -> Run.  It builds the console cover as a solid body
  in a new design.  Tweak the numbers in the PARAMETERS block and re-run to resize.

WHAT IT BUILDS  (single-piece, open-bottom cover; print it upside-down, top on the bed)
  * recessed window for touch panel 1 (164 x 98 mm) with a supporting lip,
  * a large open bay so the PYNQ-Z1 FPGA stays uncovered,
  * a front row of holes: 7 pots, 3 toggle switches, 1 clear button,
  * a cable slot in the back wall.

Dimensions match enclosure_build.py (trimesh) and enclosure.scad.  All values mm.
Fusion's API works in centimetres, so every length is multiplied by MM (=0.1).
"""
import adsk.core, adsk.fusion, traceback

MM = 0.1  # cm per mm  (Fusion API internal unit is cm)

# ---------------- parameters (mm) -------------------------------------------
WALL         = 3.0
TOP_T        = 5.0
H            = 55.0

PANEL_W      = 164.0
PANEL_H      = 98.0
PANEL_RECESS = 2.6
PANEL_LIP    = 4.0

FPGA_W       = 120.0
FPGA_D       = 90.0

POT_D        = 7.0
TOGGLE_D     = 6.0
BUTTON_D     = 12.0

EDGE         = 8.0
GAP          = 12.0
FRONT_STRIP  = 46.0
MID_GAP      = 12.0
BACK_MARGIN  = 10.0
CTRL_FRONT   = 24.0

CABLE_W      = 40.0
CABLE_H      = 22.0

CONTROLS = [
    ("yaw", POT_D), ("pitch", POT_D), ("zoom", POT_D), ("zscale", POT_D),
    ("amp", POT_D), ("cond", POT_D), ("field", POT_D),
    ("mode", TOGGLE_D), ("disp", TOGGLE_D), ("wall", TOGGLE_D),
    ("clear", BUTTON_D),
]

# ---------------- derived footprint -----------------------------------------
PANEL_CX  = WALL + EDGE + PANEL_W / 2
FPGA_CX   = WALL + EDGE + PANEL_W + GAP + FPGA_W / 2
W         = FPGA_CX + FPGA_W / 2 + EDGE + WALL
PANEL_CY  = WALL + FRONT_STRIP + MID_GAP + PANEL_H / 2
BACK_EDGE = PANEL_CY + PANEL_H / 2
FPGA_CY   = BACK_EDGE - FPGA_D / 2
D         = BACK_EDGE + BACK_MARGIN + WALL
CTRL_Y    = WALL + CTRL_FRONT


def run(context):
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        doc = app.documents.add(adsk.core.DocumentTypes.FusionDesignDocumentType)
        design = app.activeProduct
        root = design.rootComponent
        tbm = adsk.fusion.TemporaryBRepManager.get()

        xd = adsk.core.Vector3D.create(1, 0, 0)
        yd = adsk.core.Vector3D.create(0, 1, 0)

        def obox(cx, cy, cz, sx, sy, sz):
            c = adsk.core.Point3D.create(cx * MM, cy * MM, cz * MM)
            obb = adsk.core.OrientedBoundingBox3D.create(c, xd, yd, sx * MM, sy * MM, sz * MM)
            return tbm.createBox(obb)

        def ocyl(cx, cy, cz, dia, h):
            p0 = adsk.core.Point3D.create(cx * MM, cy * MM, (cz - h / 2) * MM)
            p1 = adsk.core.Point3D.create(cx * MM, cy * MM, (cz + h / 2) * MM)
            return tbm.createCylinderOrCone(p0, (dia / 2) * MM, p1, (dia / 2) * MM)

        # solid shell (outer minus cavity), and all cutting tools
        outer  = obox(W / 2, D / 2, H / 2, W, D, H)
        cavity = obox(W / 2, D / 2, ((H - TOP_T) - 1) / 2, W - 2 * WALL, D - 2 * WALL, (H - TOP_T) + 1)

        tools = [cavity]
        tools.append(obox(PANEL_CX, PANEL_CY, H + (1 - PANEL_RECESS) / 2,
                          PANEL_W + 0.8, PANEL_H + 0.8, PANEL_RECESS + 1))            # panel recess
        tools.append(obox(PANEL_CX, PANEL_CY, H - TOP_T / 2,
                          PANEL_W - 2 * PANEL_LIP, PANEL_H - 2 * PANEL_LIP, TOP_T + 2))  # panel window
        tools.append(obox(FPGA_CX, FPGA_CY, H - TOP_T / 2, FPGA_W, FPGA_D, TOP_T + 2))   # FPGA bay
        n = len(CONTROLS)
        x0, x1 = WALL + 18.0, W - WALL - 18.0
        for i, (_name, dia) in enumerate(CONTROLS):
            x = x0 + (x1 - x0) * i / (n - 1)
            tools.append(ocyl(x, CTRL_Y, H - TOP_T / 2, dia, TOP_T + 4))               # control holes
        tools.append(obox(W / 2, D - WALL / 2, H - TOP_T - CABLE_H / 2,
                          CABLE_W, WALL + 2, CABLE_H))                                  # cable slot

        # add the temp bodies to the design inside one base feature
        base = root.features.baseFeatures.add()
        base.startEdit()
        outerBody = root.bRepBodies.add(outer, base)
        toolBodies = adsk.core.ObjectCollection.create()
        for t in tools:
            toolBodies.add(root.bRepBodies.add(t, base))
        base.finishEdit()

        # subtract all tools from the shell
        combineInput = root.features.combineFeatures.createInput(outerBody, toolBodies)
        combineInput.operation = adsk.fusion.FeatureOperations.CutFeatureOperation
        combineInput.isKeepToolBodies = False
        root.features.combineFeatures.add(combineInput)

        design.rootComponent.bRepBodies.item(0).name = "EE2_enclosure"
        app.activeViewport.fit()
        ui.messageBox("EE2 enclosure built: {:.0f} x {:.0f} x {:.0f} mm.\n"
                      "Print upside-down (top face on the bed).".format(W, D, H))

    except:  # noqa: E722
        if ui:
            ui.messageBox("Failed:\n{}".format(traceback.format_exc()))
