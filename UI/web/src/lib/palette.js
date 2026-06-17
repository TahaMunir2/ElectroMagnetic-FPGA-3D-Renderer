// Real validated palettes from the FDTD notebook. NORMAL = rainbow; the three
// CVD palettes are perceptually-separated ramps (PuOr / coolwarm / RdBu) with
// documented min band-separation. The PS writes these same 16 colours to the
// PALETTE registers; the UI draws the matching colour-bar.

export const PALETTES = {
  none: [
    [0,0,255],[0,80,255],[0,160,255],[0,255,255],[0,255,160],[0,255,80],
    [0,255,0],[128,255,0],[200,255,0],[255,255,0],[255,200,0],[255,160,0],
    [255,100,0],[255,40,0],[255,0,0],[180,0,0],
  ],
  protanopia: [
    [127,59,8],[162,78,7],[194,102,11],[224,130,20],[243,166,73],[253,197,127],
    [254,224,182],[249,239,225],[237,237,243],[216,218,235],[191,187,218],
    [161,152,197],[128,115,172],[99,64,148],[71,26,116],[45,0,75],
  ],
  deuteranopia: [
    [59,76,192],[79,105,217],[100,133,236],[123,159,249],[147,181,254],
    [170,199,253],[192,212,245],[212,219,230],[229,216,209],[242,203,183],
    [247,184,156],[245,160,129],[238,132,104],[224,101,79],[204,64,58],[180,4,38],
  ],
  tritanopia: [
    [103,0,31],[153,16,39],[190,48,54],[214,96,77],[234,142,112],[247,183,153],
    [253,219,199],[249,238,231],[234,241,245],[209,229,240],[167,208,228],
    [120,180,213],[67,147,195],[44,117,180],[24,84,147],[5,48,97],
  ],
};

export const CVD_TYPES = ["none", "protanopia", "deuteranopia", "tritanopia"];

export function computePalette(cvd) {
  return PALETTES[cvd] || PALETTES.none;
}
