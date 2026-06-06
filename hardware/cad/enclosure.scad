// EE2 FDTD EM Wave Simulator -- enclosure (OpenSCAD, parametric).
// Open in OpenSCAD, press F5 to preview / F6 to render, then Export as STL.
// Single-piece open-bottom cover; print upside-down (top face on the bed).
// Matches enclosure_build.py (trimesh) and enclosure_fusion360.py.  Units: mm.

// ---------------- parameters ----------------
wall         = 3;
top_t        = 5;
H            = 55;

panel_w      = 164;   // touch panel 1 (16.4 cm)
panel_h      = 98;    // touch panel 1 (9.8 cm)
panel_recess = 2.6;   // depth panel drops into
panel_lip    = 4;     // supporting shelf width

fpga_w       = 120;   // open bay for PYNQ-Z1
fpga_d       = 90;

pot_d        = 7;
toggle_d     = 6;
button_d     = 12;

edge         = 8;
gap          = 12;
front_strip  = 46;
mid_gap      = 12;
back_margin  = 10;
ctrl_front   = 24;

cable_w      = 40;
cable_h      = 22;

// ---------------- derived ----------------
panel_cx  = wall + edge + panel_w/2;
fpga_cx   = wall + edge + panel_w + gap + fpga_w/2;
W         = fpga_cx + fpga_w/2 + edge + wall;
panel_cy  = wall + front_strip + mid_gap + panel_h/2;
back_edge = panel_cy + panel_h/2;
fpga_cy   = back_edge - fpga_d/2;
D         = back_edge + back_margin + wall;
ctrl_y    = wall + ctrl_front;

dias = [pot_d,pot_d,pot_d,pot_d,pot_d,pot_d,pot_d,toggle_d,toggle_d,toggle_d,button_d];

module shell() {
    difference() {
        cube([W, D, H]);
        // cavity: open bottom, leaves top plate of top_t and walls of wall
        translate([wall, wall, -1]) cube([W-2*wall, D-2*wall, (H-top_t)+1]);
    }
}

module features() {
    // panel recess (top)
    translate([panel_cx-(panel_w+0.8)/2, panel_cy-(panel_h+0.8)/2, H-panel_recess])
        cube([panel_w+0.8, panel_h+0.8, panel_recess+1]);
    // panel through-window (leaves a lip)
    translate([panel_cx-(panel_w-2*panel_lip)/2, panel_cy-(panel_h-2*panel_lip)/2, H-top_t-1])
        cube([panel_w-2*panel_lip, panel_h-2*panel_lip, top_t+2]);
    // FPGA open bay
    translate([fpga_cx-fpga_w/2, fpga_cy-fpga_d/2, H-top_t-1])
        cube([fpga_w, fpga_d, top_t+2]);
    // control holes
    x0 = wall+18; x1 = W-wall-18; n = len(dias);
    for (i = [0:n-1])
        translate([x0+(x1-x0)*i/(n-1), ctrl_y, H-top_t-2])
            cylinder(h=top_t+4, d=dias[i], $fn=64);
    // back-wall cable slot
    translate([W/2-cable_w/2, D-wall-1, H-top_t-cable_h])
        cube([cable_w, wall+2, cable_h]);
}

difference() { shell(); features(); }

echo(str("footprint  W x D x H = ", W, " x ", D, " x ", H, " mm"));
