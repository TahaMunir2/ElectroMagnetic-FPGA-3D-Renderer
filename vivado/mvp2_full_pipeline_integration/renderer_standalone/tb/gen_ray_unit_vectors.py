#!/usr/bin/env python3
"""
gen_ray_unit_vectors.py
-----------------------
End-to-end Python golden reference for ray_unit.

Runs the full pipeline (ray_gen -> marcher -> normal -> shader) in Python,
bit-exactly matching the SV behaviour, and emits:
    heightmap.hex      : the heightmap loaded into both BRAM-port arrays
    ray_unit_vectors.hex : test records (px, py, expected R, G, B)

Camera setup matches the manual trace we did:
    O = (1.0, 1.0, 1.0)  (on the corner of the world)
    target = (0, 0, 0)
    fwd = (-0.577, -0.577, -0.577)
    right, up = computed from fwd and world_up = (0,0,1)
    sun = (0, 0, 1)  (hardcoded in SV shader)

Q-format: Q2.13 throughout (POS_I=2, H_I=2, DIR_I=2).
World: WORLD_HALF = 1.0  (= 8192 in Q2.13).

Heightmap is 4x4 with a plateau (h=0.25 in cells (1,1),(1,2),(2,1),(2,2)).
But the SV uses GRID_N=256 so we pad with zeros to 256x256.

To start simple we only test a couple of pixels by hand.
"""

import math
import random

# ----- Parameters (must match ray_unit.sv defaults) -----
W       = 4              # tiny screen for manual test
H       = 4
POS_W   = 16
POS_I   = 2
POS_F   = POS_W - 1 - POS_I    # = 13

DIR_W   = 16
DIR_I   = 2
DIR_F   = DIR_W - 1 - DIR_I    # = 13

UV_W    = 16
UV_I    = 1
UV_F    = UV_W - 1 - UV_I      # = 14

K_W     = 16
K_F     = K_W - 1              # = 15

GRID_N  = 4                    # tiny grid for manual test
IDX_W   = int(math.ceil(math.log2(GRID_N)))  # = 2

H_W     = 16
H_I     = 2
H_F     = H_W - 1 - H_I        # = 13

N_STEPS = 4
STEP_W  = int(math.ceil(math.log2(N_STEPS + 1)))  # = 3

PX_W    = int(math.ceil(math.log2(W)))   # = 2
PY_W    = int(math.ceil(math.log2(H)))   # = 2

WORLD_HALF = 1 << POS_F        # = 8192 = 1.0

DT = (2 * WORLD_HALF) // GRID_N   # = 4096 = 0.5  (one cell per step)

ST_MARCHING = 0
ST_HIT      = 1
ST_OFFGRID  = 2

# K_U / K_V picked for 4x4 / 90deg FOV / aspect=1
# K = (2/W) * tan(45) * aspect = (2/4)*1*1 = 0.5
# In Q0.15:  0.5 * 32768 = 16384
K_U = 16384
K_V = 16384

# Shader knobs
SKY_R, SKY_G, SKY_B = 135, 206, 235
PALE_R, PALE_G, PALE_B = 192, 192, 192
AMBIENT = 64


# =============================================================================
# Helpers
# =============================================================================

def to_signed(v, w):
    m = (1 << w) - 1
    v &= m
    if v & (1 << (w-1)):
        v -= (1 << w)
    return v

def sat_signed(v, w):
    return to_signed(v & ((1 << w) - 1), w)

def to_hex(v, w):
    m = (1 << w) - 1
    return f"{v & m:0{(w + 3) // 4}x}"

def arsh(v, sh):
    if sh <= 0:
        return v << (-sh)
    return v >> sh

def clamp_u8(v):
    if v < 0:    return 0
    if v > 255:  return 255
    return v & 0xff

def fq(x, F):
    """Convert float to signed Q-format integer with F fractional bits."""
    return int(round(x * (1 << F)))


# =============================================================================
# ray_gen model
# =============================================================================

def ray_gen_model(px, py, fwd, right, up):
    # u = (px - W/2) * K_U   -> Q1.14
    # v = (H/2 - py) * K_V
    px_c = px - (W // 2)
    py_c = (H // 2) - py
    UV_SHIFT = K_F - UV_F   # = 1
    u_raw = px_c * K_U
    v_raw = py_c * K_V
    u = sat_signed(arsh(u_raw, UV_SHIFT), UV_W)
    v = sat_signed(arsh(v_raw, UV_SHIFT), UV_W)
    # D = fwd + u*right + v*up (each component)
    SUM_SHIFT = UV_F     # = 14
    D = []
    for i in range(3):
        ur = u * right[i]
        vu = v * up[i]
        ur_aln = sat_signed(arsh(ur, SUM_SHIFT), DIR_W)
        vu_aln = sat_signed(arsh(vu, SUM_SHIFT), DIR_W)
        D.append(sat_signed(fwd[i] + ur_aln + vu_aln, DIR_W))
    return tuple(D)


# =============================================================================
# march_step model (one step)
# =============================================================================

def dt_times(d):
    raw = DT * d
    return sat_signed(arsh(raw, DIR_F), POS_W)

def world_to_grid(p):
    s = p + WORLD_HALF
    sh = POS_F + 1 - int(math.ceil(math.log2(GRID_N)))   # = POS_F + 1 - 2 = 12
    return arsh(s, sh)

def march_step_model(st, heightmap):
    """One iteration. st is a dict, returns updated dict."""
    Px, Py, Pz = st['Px'], st['Py'], st['Pz']
    Dx, Dy, Dz = st['Dx'], st['Dy'], st['Dz']
    status     = st['status']
    prev_below = st['prev_below']
    h_hit      = st['h_hit']
    ix_hit     = st['ix_hit']
    iy_hit     = st['iy_hit']
    step_count = st['step_count']

    # Stage A: advance
    if status == ST_MARCHING:
        PxA = sat_signed(Px + dt_times(Dx), POS_W)
        PyA = sat_signed(Py + dt_times(Dy), POS_W)
        PzA = sat_signed(Pz + dt_times(Dz), POS_W)
    else:
        PxA, PyA, PzA = Px, Py, Pz
    statA = status

    # Stage B: indices
    ix_raw = world_to_grid(PxA)
    iy_raw = world_to_grid(PyA)
    offgrid = (ix_raw < 0) or (ix_raw >= GRID_N) or \
              (iy_raw < 0) or (iy_raw >= GRID_N)
    ix_B = ix_raw & ((1 << IDX_W) - 1)
    iy_B = iy_raw & ((1 << IDX_W) - 1)

    if statA != ST_MARCHING:
        statB = statA
    elif offgrid:
        statB = ST_OFFGRID
    else:
        statB = ST_MARCHING

    if statA == ST_MARCHING and not offgrid:
        ixHitB = ix_B
        iyHitB = iy_B
    else:
        ixHitB = ix_hit
        iyHitB = iy_hit

    if statA == ST_MARCHING:
        stepCountB = (step_count + 1) & ((1 << STEP_W) - 1)
    else:
        stepCountB = step_count

    # Stage C: BRAM data
    if statA == ST_MARCHING and not offgrid:
        h_C = heightmap[iy_B][ix_B]
    else:
        h_C = 0

    # Stage D: crossing
    H_ALIGN_SHIFT = POS_F - H_F     # = 0 here
    h_aligned = h_C << H_ALIGN_SHIFT if H_ALIGN_SHIFT >= 0 else h_C >> (-H_ALIGN_SHIFT)
    h_aligned = sat_signed(h_aligned, POS_W)
    below_D = (PzA < h_aligned)
    # Bug 2 fix: step_count_C != 0
    crossed = (statB == ST_MARCHING) and (below_D != prev_below) and (stepCountB != 0)

    if statB == ST_MARCHING and crossed:
        new_status = ST_HIT
        new_h_hit  = h_C
    else:
        new_status = statB
        new_h_hit  = h_hit

    if statB == ST_MARCHING:
        new_prev = 1 if below_D else 0
    else:
        new_prev = prev_below

    return {
        'Px': PxA, 'Py': PyA, 'Pz': PzA,
        'Dx': Dx, 'Dy': Dy, 'Dz': Dz,
        'status':     new_status,
        'prev_below': new_prev,
        'h_hit':      new_h_hit,
        'ix_hit':     ixHitB,
        'iy_hit':     iyHitB,
        'step_count': stepCountB,
    }


def marcher_model(Ox, Oy, Oz, Dx, Dy, Dz, heightmap):
    """Chain N_STEPS march_steps."""
    st = {
        'Px': Ox, 'Py': Oy, 'Pz': Oz,
        'Dx': Dx, 'Dy': Dy, 'Dz': Dz,
        'status':     ST_MARCHING,
        'prev_below': 0,
        'h_hit':      0,
        'ix_hit':     0,
        'iy_hit':     0,
        'step_count': 0,
    }
    for _ in range(N_STEPS):
        st = march_step_model(st, heightmap)
    return st


# =============================================================================
# normal model
# =============================================================================

def clamp_dec(v):
    return 0 if v == 0 else v - 1

def clamp_inc(v):
    return v if v == GRID_N - 1 else v + 1


def normal_model(status, ix, iy, heightmap):
    ix_m = clamp_dec(ix); ix_p = clamp_inc(ix)
    iy_m = clamp_dec(iy); iy_p = clamp_inc(iy)
    h_xm = heightmap[iy][ix_m]
    h_xp = heightmap[iy][ix_p]
    h_ym = heightmap[iy_m][ix]
    h_yp = heightmap[iy_p][ix]

    dx_h = h_xp - h_xm
    dy_h = h_yp - h_ym

    # Shift to DIR_F (saturating)
    if DIR_F >= H_F:
        dx_shifted = dx_h << (DIR_F - H_F)
        dy_shifted = dy_h << (DIR_F - H_F)
    else:
        dx_shifted = dx_h >> (H_F - DIR_F)
        dy_shifted = dy_h >> (H_F - DIR_F)

    SAT_POS = (1 << (DIR_W - 1)) - 1
    SAT_NEG = -(1 << (DIR_W - 1))

    def sat_and_neg(v):
        if v > SAT_POS:    return -SAT_POS
        elif v < SAT_NEG:  return -SAT_NEG
        else:              return sat_signed(-v, DIR_W)

    Nx_calc = sat_and_neg(dx_shifted)
    Ny_calc = sat_and_neg(dy_shifted)
    Nz_const = 1 << DIR_F

    if status == ST_HIT:
        return Nx_calc, Ny_calc, Nz_const
    else:
        return 0, 0, Nz_const


# =============================================================================
# shader model
# =============================================================================

def shader_model(status, h_hit, step_count, Nx, Ny, Nz):
    # Block A: simplified, sun=(0,0,1) so bright_q = Nz (zero-extended)
    if Nz <= 0:
        bright_q = 0
    else:
        bright_q = Nz   # padded with zeros; bit 31 always 0

    # Block B
    if bright_q >= (1 << DIR_F):
        bright_tmp = 255
    elif DIR_F >= 8:
        bright_tmp = arsh(bright_q, DIR_F - 8)
    else:
        bright_tmp = bright_q << (8 - DIR_F)
    bright_u8 = clamp_u8(bright_tmp)

    # 16-bit ambient blend (the fix we made)
    light_u8 = clamp_u8(AMBIENT + (((255 - AMBIENT) * bright_u8) >> 8))

    # Block C: altitude
    if H_F >= 7:
        altitude_shifted = arsh(h_hit, H_F - 7) + 128
    else:
        altitude_shifted = (h_hit << (7 - H_F)) + 128
    altitude_u8 = clamp_u8(altitude_shifted)

    base_r = altitude_u8
    base_b = clamp_u8(255 - altitude_u8)
    if altitude_u8 > 127:
        diff = (altitude_u8 - 127) << 1
    else:
        diff = (127 - altitude_u8) << 1
    # Note: known overflow bug at extremes; not fixing here for bit-exactness
    diff_8bit = diff & 0xFF
    inner = (255 - diff_8bit) & 0xFF
    base_g = clamp_u8(32 + (inner >> 2))

    # Block D: fog
    fog_int = (step_count * 255) // N_STEPS if N_STEPS > 1 else 0
    fog_u8 = clamp_u8(fog_int)

    # Block E: mix + mul
    def mix(a, b, t):
        return clamp_u8(((255 - t) * a + t * b) >> 8)
    def mul(a, b):
        return clamp_u8((a * b) >> 8)

    fogged_r = mix(base_r, PALE_R, fog_u8)
    fogged_g = mix(base_g, PALE_G, fog_u8)
    fogged_b = mix(base_b, PALE_B, fog_u8)

    lit_r = mul(fogged_r, light_u8)
    lit_g = mul(fogged_g, light_u8)
    lit_b = mul(fogged_b, light_u8)

    if status == ST_HIT:
        return lit_r, lit_g, lit_b
    else:
        return SKY_R, SKY_G, SKY_B


# =============================================================================
# End-to-end pixel rendering
# =============================================================================

def render_pixel(px, py, O, fwd, right, up, heightmap):
    D = ray_gen_model(px, py, fwd, right, up)
    mc = marcher_model(O[0], O[1], O[2], D[0], D[1], D[2], heightmap)
    Nx, Ny, Nz = normal_model(mc['status'], mc['ix_hit'], mc['iy_hit'], heightmap)
    r, g, b = shader_model(mc['status'], mc['h_hit'], mc['step_count'], Nx, Ny, Nz)
    return r, g, b, mc


# =============================================================================
# Test setup
# =============================================================================

def main():
    # Build heightmap: 4x4 with a plateau in the middle 2x2
    plateau_h = fq(0.25, H_F)   # 0.25 in Q-format
    hm_small = [[0]*GRID_N for _ in range(GRID_N)]
    for y in range(GRID_N):
        for x in range(GRID_N):
            if x in (1, 2) and y in (1, 2):
                hm_small[y][x] = plateau_h
            else:
                hm_small[y][x] = 0

    # Write heightmap.hex
    with open("heightmap.hex", "w") as f:
        for y in range(GRID_N):
            for x in range(GRID_N):
                f.write(to_hex(hm_small[y][x], H_W) + "\n")
    print(f"Wrote heightmap.hex with {GRID_N*GRID_N} entries.")

    # Camera setup (the one we manually traced)
    # O at (1.0, 1.0, 1.0)
    O = (fq(1.0, POS_F), fq(1.0, POS_F), fq(1.0, POS_F))

    # fwd = normalize(target - O) where target = (0,0,0)
    # = (-1,-1,-1) / sqrt(3) = (-0.577, -0.577, -0.577)
    inv_sqrt3 = 1.0 / math.sqrt(3)
    fwd = tuple(fq(-inv_sqrt3, DIR_F) for _ in range(3))

    # right = normalize(cross(fwd, world_up)) where world_up = (0, 0, 1)
    # cross((-1,-1,-1), (0,0,1)) = (-1*1 - -1*0, -1*0 - -1*1, -1*0 - -1*0) = (-1, 1, 0)
    # normalized = (-1, 1, 0)/sqrt(2)
    inv_sqrt2 = 1.0 / math.sqrt(2)
    right = (fq(-inv_sqrt2, DIR_F), fq(inv_sqrt2, DIR_F), 0)

    # up = cross(right, fwd) = cross((-1,1,0)/sqrt2, (-1,-1,-1)/sqrt3)
    # = (1*(-1) - 0*(-1), 0*(-1) - (-1)*(-1), (-1)*(-1) - 1*(-1)) / (sqrt2*sqrt3)
    # = (-1, -1, 2) / sqrt(6)
    inv_sqrt6 = 1.0 / math.sqrt(6)
    up = (fq(-inv_sqrt6, DIR_F), fq(-inv_sqrt6, DIR_F), fq(2*inv_sqrt6, DIR_F))

    print(f"Camera setup:")
    print(f"  O     = {O}")
    print(f"  fwd   = {fwd}")
    print(f"  right = {right}")
    print(f"  up    = {up}")

    # Render every pixel
    print(f"\nRendering {W}x{H} image:")
    print(f"{'px':>3} {'py':>3}  {'R':>3} {'G':>3} {'B':>3}  status step ix iy h_hit")

    records = []
    for py in range(H):
        for px in range(W):
            r, g, b, mc = render_pixel(px, py, O, fwd, right, up, hm_small)
            stat_str = ['MISS', 'HIT', 'OFFGRID', '???'][mc['status']]
            print(f"{px:3d} {py:3d}  {r:3d} {g:3d} {b:3d}  {stat_str:>7s} {mc['step_count']:3d} "
                  f"{mc['ix_hit']:2d} {mc['iy_hit']:2d} {mc['h_hit']:4d}")
            records.append((px, py, r, g, b))

    # Write vectors: each record is (px, py, r, g, b)
    # 16-bit fields each, 5 fields per record
    VPR = 5
    with open("ray_unit_vectors.hex", "w") as f:
        f.write(f"// {len(records)} records, {VPR} fields each: px py r g b\n")
        for (px, py, r, g, b) in records:
            f.write(to_hex(px, 16) + "\n")
            f.write(to_hex(py, 16) + "\n")
            f.write(to_hex(r, 16) + "\n")
            f.write(to_hex(g, 16) + "\n")
            f.write(to_hex(b, 16) + "\n")

    print(f"\nWrote ray_unit_vectors.hex with {len(records)} records.")
    print(f"\nCamera params (for the SV testbench):")
    print(f"  Ox={O[0]} Oy={O[1]} Oz={O[2]}")
    print(f"  fwd_x={fwd[0]} fwd_y={fwd[1]} fwd_z={fwd[2]}")
    print(f"  right_x={right[0]} right_y={right[1]} right_z={right[2]}")
    print(f"  up_x={up[0]} up_y={up[1]} up_z={up[2]}")


if __name__ == "__main__":
    main()
