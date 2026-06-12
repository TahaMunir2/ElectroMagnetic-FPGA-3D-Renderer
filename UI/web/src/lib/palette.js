// Mock palette logic for the UI. The REAL daltonisation (Machado model) will
// run on the PS later and return 16 colours; this file is the stand-in so the
// UI works today. Swapping to real data = replace computePalette() with a
// WebSocket round-trip. Nothing else changes.

// 16-entry base ramp (viridis-ish, CVD-friendlier than rainbow).
const BASE = [
  [68,1,84],[72,40,120],[62,74,137],[49,104,142],
  [38,130,142],[31,158,137],[53,183,121],[110,206,88],
  [181,222,43],[253,231,37],[255,213,0],[255,184,0],
  [255,150,0],[255,110,0],[255,60,0],[200,0,0],
];

// Crude CVD simulation matrices (illustrative, not Machado-accurate).
// Real correction happens on the PS; this just makes the bar visibly change.
const SHIFT = {
  none:         (c) => c,
  protanopia:   ([r,g,b]) => [Math.round(0.56*r+0.44*g), Math.round(0.55*g+0.45*r), b],
  deuteranopia: ([r,g,b]) => [Math.round(0.625*r+0.375*g), Math.round(0.7*g+0.3*r), b],
  tritanopia:   ([r,g,b]) => [r, Math.round(0.95*g+0.05*b), Math.round(0.567*b+0.433*g)],
};

export const CVD_TYPES = ["none", "protanopia", "deuteranopia", "tritanopia"];

export function computePalette(cvd) {
  const f = SHIFT[cvd] || SHIFT.none;
  return BASE.map(f).map(([r,g,b]) => [
    Math.max(0, Math.min(255, r)),
    Math.max(0, Math.min(255, g)),
    Math.max(0, Math.min(255, b)),
  ]);
}
