#!/usr/bin/env python3
# contour_golden.py
# Generates a synthetic 64x64 signed Q2.13 heightmap (heightmap.hex, row-major
# addr = iy*64+ix) and the expected RGB stream (golden.txt) for the full
# 640x480 active region in raster order. Bit-exact with contour_unit.sv.

import math

W, H = 640, 480
GRID_N = 64
H_W, H_I = 16, 2
H_F = H_W - 1 - H_I            # 13 fractional bits (Q2.13)
SH, RX, RY = 14, 1639, 2185    # MUST match contour_unit.sv

PALETTE = [
    (0,   0,   255), (0,   80,  255), (0,   160, 255), (0,   255, 255),
    (0,   255, 160), (0,   255, 80),  (0,   255, 0),   (128, 255, 0),
    (200, 255, 0),   (255, 255, 0),   (255, 200, 0),   (255, 160, 0),
    (255, 100, 0),   (255, 40,  0),   (255, 0,   0),   (180, 0,   0),
]

def to_q(x):
    """float -> signed Q2.13, clamped to the representable range, 16-bit two's-comp."""
    v = int(round(x * (1 << H_F)))
    lo, hi = -(1 << (H_W-1)), (1 << (H_W-1)) - 1
    v = max(lo, min(hi, v))
    return v & 0xFFFF

def make_heightmap():
    """Smooth terrain: a couple of gaussian bumps + a tilt. Range ~[-3.5, 3.5)."""
    mem = [0]*(GRID_N*GRID_N)
    for iy in range(GRID_N):
        for ix in range(GRID_N):
            u = ix / (GRID_N-1)
            v = iy / (GRID_N-1)
            z  = 2.5*math.exp(-(((u-0.30)**2 + (v-0.65)**2)/0.05))
            z -= 2.0*math.exp(-(((u-0.70)**2 + (v-0.30)**2)/0.04))
            z += 1.2*math.sin(3.1*u)*math.cos(2.7*v)
            z += 1.5*(u - 0.5)            # gentle tilt
            mem[iy*GRID_N + ix] = to_q(z)
    return mem

def scale_idx(p, recip):
    raw = (p * recip) >> SH
    return GRID_N-1 if raw >= GRID_N else raw

def band_of(h16):
    """offset-binary top 4 bits, identical to {~h[15],h[14:12]}."""
    return ((h16 ^ 0x8000) >> 12) & 0xF

def main():
    mem = make_heightmap()
    with open("heightmap.hex", "w") as f:
        for w in mem:
            f.write(f"{w:04x}\n")

    with open("golden.txt", "w") as f:
        for py in range(H):
            iy = scale_idx(py, RY)
            for px in range(W):
                ix = scale_idx(px, RX)
                h  = mem[iy*GRID_N + ix]
                r, g, b = PALETTE[band_of(h)]
                f.write(f"{px} {py} {r} {g} {b}\n")

    print(f"wrote heightmap.hex ({len(mem)} words) and golden.txt ({W*H} pixels)")

if __name__ == "__main__":
    main()
