#!/usr/bin/env python3
"""
gen_normal_vectors.py
---------------------
Golden reference for normal.sv.

Inputs per record:
    status_in, ix_in, iy_in, h_hit_in, step_count_in, px_in, py_in
Heightmap: shared with march_step / marcher TBs (heightmap.hex).
Outputs:
    status_out, ix_out, iy_out, h_hit_out, step_count_out,
    Nx_out, Ny_out, Nz_out, px_out, py_out

The Python mirrors normal.sv exactly:
    clamp_dec(v) = max(0, v-1)
    clamp_inc(v) = min(GRID_N-1, v+1)
    Read 4 neighbour heights from heightmap.
    dx_h = h(ix+1, iy) - h(ix-1, iy)    (signed, 17-bit)
    dy_h = h(ix, iy+1) - h(ix, iy-1)
    Nx = -hdiff_to_dir(dx_h)
    Ny = -hdiff_to_dir(dy_h)
    Nz = (1 << DIR_F)
    If status_in != HIT, Nx=Ny=0, Nz=NZ_CONST.

hdiff_to_dir: with H_F=11, DIR_F=13 (defaults), shift left by 2.
    tmp = hdiff << 2; return tmp[15:0] (slice low 16 bits, signed).
    NB: this is the buggy slice (Bug 3 from earlier analysis).
    Python mirrors it so the bit-exact comparison still works.
"""

import random

# ---- Parameters (must match tb_normal.sv & normal.sv defaults) ----
GRID_N  = 256
IDX_W   = 8

H_W     = 16
H_I     = 4
H_F     = H_W - 1 - H_I       # 11

DIR_W   = 16
DIR_I   = 2
DIR_F   = DIR_W - 1 - DIR_I   # 13

STEP_W  = 5

PX_W    = 10
PY_W    = 10

ST_MISS    = 0
ST_HIT     = 1
ST_OFFGRID = 2

NZ_CONST = 1 << DIR_F

N_TESTS = 1500
SEED    = 0xCAFE  # share with gen_marcher_vectors so heightmap.hex matches


# ---- Helpers ----

def to_signed(val, width):
    mask = (1 << width) - 1
    val &= mask
    if val & (1 << (width - 1)):
        val -= (1 << width)
    return val

def sat_signed(val, width):
    mask = (1 << width) - 1
    return to_signed(val & mask, width)

def to_unsigned_hex(val, width):
    mask = (1 << width) - 1
    return f"{val & mask:0{(width + 3) // 4}x}"


def gen_heightmap():
    """Same as gen_marcher_vectors.py — must produce identical heightmap.hex."""
    random.seed(SEED ^ 0x1234)
    coarse_n = 16
    cp = [[random.uniform(-0.8, 0.8) for _ in range(coarse_n+1)]
                                       for _ in range(coarse_n+1)]
    cell = GRID_N // coarse_n
    hm = [[0]*GRID_N for _ in range(GRID_N)]
    for y in range(GRID_N):
        for x in range(GRID_N):
            cx, cy = x // cell, y // cell
            fx, fy = (x % cell) / cell, (y % cell) / cell
            v00 = cp[cy  ][cx  ]; v10 = cp[cy  ][cx+1]
            v01 = cp[cy+1][cx  ]; v11 = cp[cy+1][cx+1]
            v0 = v00*(1-fx) + v10*fx
            v1 = v01*(1-fx) + v11*fx
            v  = v0*(1-fy) + v1*fy
            hm[y][x] = sat_signed(int(round(v * (1 << H_F))), H_W)
    return hm


# ---- The reference model (bit-exact mirror of normal.sv) ----

def clamp_dec(v):
    return 0 if v == 0 else v - 1

def clamp_inc(v):
    return v if v == GRID_N - 1 else v + 1

def hdiff_to_dir(hdiff):
    """
    Mirror of normal.sv's hdiff_to_dir.
    hdiff is a signed 17-bit value.
    Shift left by (DIR_F - H_F) = 2, then slice low DIR_W bits, signed.
    NB: this matches the SV behaviour, including the buggy truncation.
    """
    if DIR_F >= H_F:
        tmp = hdiff << (DIR_F - H_F)
    else:
        tmp = hdiff >> (H_F - DIR_F)
    return sat_signed(tmp, DIR_W)


def normal_model(status, ix, iy, heightmap):
    """Returns (Nx, Ny, Nz)."""
    ix_m = clamp_dec(ix)
    ix_p = clamp_inc(ix)
    iy_m = clamp_dec(iy)
    iy_p = clamp_inc(iy)

    h_xm = heightmap[iy][ix_m]
    h_xp = heightmap[iy][ix_p]
    h_ym = heightmap[iy_m][ix]
    h_yp = heightmap[iy_p][ix]

    dx_h = h_xp - h_xm   # signed 17-bit max
    dy_h = h_yp - h_ym

    Nx_calc = sat_signed(-hdiff_to_dir(dx_h), DIR_W)
    Ny_calc = sat_signed(-hdiff_to_dir(dy_h), DIR_W)

    if status == ST_HIT:
        return Nx_calc, Ny_calc, NZ_CONST
    else:
        return 0, 0, NZ_CONST


# ---- Generator ----

def main():
    random.seed(SEED)
    heightmap = gen_heightmap()

    # Write heightmap.hex (same as marcher's)
    with open("heightmap.hex", "w") as f:
        for y in range(GRID_N):
            for x in range(GRID_N):
                f.write(to_unsigned_hex(heightmap[y][x], 16) + "\n")
    print(f"Wrote heightmap.hex with {GRID_N*GRID_N} entries.")

    records = []

    # Directed tests
    # 1. HIT at grid centre
    records.append((ST_HIT, 128, 128, heightmap[128][128], 5, 320, 240))
    # 2. HIT at corner (clamping should engage)
    records.append((ST_HIT, 0, 0, heightmap[0][0], 1, 0, 0))
    records.append((ST_HIT, GRID_N-1, GRID_N-1, heightmap[GRID_N-1][GRID_N-1], 16, 639, 479))
    # 3. MISS (status=0) — should return Nx=Ny=0, Nz=NZ_CONST
    records.append((ST_MISS, 128, 128, 0, 16, 320, 240))
    # 4. OFFGRID — same as MISS
    records.append((ST_OFFGRID, 200, 50, 0, 8, 100, 100))

    # Random tests
    for _ in range(N_TESTS):
        st = random.choice([ST_HIT]*4 + [ST_MISS, ST_OFFGRID])
        ix = random.randint(0, GRID_N-1)
        iy = random.randint(0, GRID_N-1)
        h  = heightmap[iy][ix] if st == ST_HIT else random.randint(-100, 100)
        sc = random.randint(0, (1 << STEP_W) - 1)
        px = random.randint(0, (1 << PX_W) - 1)
        py = random.randint(0, (1 << PY_W) - 1)
        records.append((st, ix, iy, h, sc, px, py))

    # Layout per record (12 values, 16-bit each):
    #   Inputs (7):  status ix iy h_hit step_count px py
    #   Outputs (5): Nx Ny Nz   (+ status, h_hit, ix, iy, step_count, px, py
    #                            which should pass through unchanged — we don't
    #                            re-write them in vectors, the SV TB checks
    #                            pass-through against the inputs)
    VPR = 12
    with open("normal_vectors.hex", "w") as f:
        f.write(f"// {len(records)} test records, {VPR} values each\n")
        for (st, ix, iy, h, sc, px, py) in records:
            Nx, Ny, Nz = normal_model(st, ix, iy, heightmap)
            vals = [
                # inputs
                st, ix, iy, h, sc, px, py,
                # outputs (only the new ones — pass-throughs checked against inputs)
                Nx, Ny, Nz,
                # pad to VPR
                0, 0,
            ]
            for v in vals:
                f.write(to_unsigned_hex(v, 16) + "\n")

    print(f"Wrote normal_vectors.hex with {len(records)} records.")


if __name__ == "__main__":
    main()
