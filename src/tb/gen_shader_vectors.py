#!/usr/bin/env python3
"""
gen_shader_vectors.py
---------------------
Golden reference for shader.sv.

Bit-exact mirror of all the shader arithmetic:
    - dot product of N and L
    - brightness clamp + Q-format conversion
    - height-to-altitude colour
    - step-count fog
    - mixing + multiplying

Inputs per record (10):
    status_in, h_hit_in, step_count_in,
    Nx, Ny, Nz, sun_dx, sun_dy, sun_dz, px, py (yes 11, see layout below)
Outputs (3): r_out, g_out, b_out

For MISS / OFFGRID we expect sky colour.
"""

import random

# ---- Parameters (must match tb_shader.sv & shader.sv defaults) ----
H_W     = 16
H_I     = 4
H_F     = H_W - 1 - H_I       # 11

DIR_W   = 16
DIR_I   = 2
DIR_F   = DIR_W - 1 - DIR_I   # 13

N_STEPS = 16
STEP_W  = 5

PX_W    = 10
PY_W    = 10

SKY_R = 135
SKY_G = 206
SKY_B = 235

PALE_R = 192
PALE_G = 192
PALE_B = 192
AMBIENT = 64

ST_MISS    = 0
ST_HIT     = 1
ST_OFFGRID = 2

N_TESTS = 2000
SEED    = 0xF00D


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


def clamp_u8(v):
    if v < 0:    return 0
    if v > 255:  return 255
    return v & 0xff

def mix_u8(a, b, t):
    """((255-t)*a + t*b) >> 8 — but SV uses 'integer' so no width clamp until clamp_u8."""
    acc = ((255 - t) * a + t * b) >> 8
    return clamp_u8(acc)

def mul_u8(a, b):
    """(a*b) >> 8."""
    return clamp_u8((a * b) >> 8)

def height_to_u8(h):
    """SV: if H_F >= 7: shifted = (h >>> (H_F-7)) + 128
            else        shifted = (h <<< (7 - H_F)) + 128"""
    if H_F >= 7:
        shifted = (h >> (H_F - 7)) + 128
    else:
        shifted = (h << (7 - H_F)) + 128
    return clamp_u8(shifted)

def step_to_fog(step_count):
    if N_STEPS <= 1:
        fog = 0
    else:
        fog = (step_count * 255) // N_STEPS
    return clamp_u8(fog)

def bright_to_u8(bright_q):
    """
    SV:
      if (bright_q[2*DIR_W-1])    tmp = 0;        // negative
      else if (bright_q >= (1 <<< DIR_F)) tmp = 255;
      else if (DIR_F >= 8) tmp = bright_q >>> (DIR_F - 8);
      else                  tmp = bright_q <<< (8 - DIR_F);
    bright_q is a signed (2*DIR_W) value.
    """
    if bright_q < 0:
        tmp = 0
    elif bright_q >= (1 << DIR_F):
        tmp = 255
    elif DIR_F >= 8:
        tmp = bright_q >> (DIR_F - 8)
    else:
        tmp = bright_q << (8 - DIR_F)
    return clamp_u8(tmp)


def shader_model(status, h_hit, step_count, Nx, Ny, Nz, sun_dx, sun_dy, sun_dz):
    """Returns (r, g, b)."""
    # Dot product
    dot_x = Nx * sun_dx
    dot_y = Ny * sun_dy
    dot_z = Nz * sun_dz
    dot_sum = dot_x + dot_y + dot_z

    if dot_sum <= 0:
        bright_q = 0
    else:
        bright_q = dot_sum >> DIR_F

    altitude_u8 = height_to_u8(h_hit)
    fog_u8      = step_to_fog(step_count)
    bright_u8   = bright_to_u8(bright_q)

    # Ambient blend.  SV: AMBIENT + ((255 - AMBIENT) * bright_u8 >> 8)
    light_u8 = clamp_u8(AMBIENT + (((255 - AMBIENT) * bright_u8) >> 8))

    base_r = altitude_u8
    base_b = clamp_u8(255 - altitude_u8)
    # base_g is a piecewise function in SV
    if altitude_u8 > 127:
        diff = (altitude_u8 - 127) << 1
    else:
        diff = (127 - altitude_u8) << 1
    inner = clamp_u8(255 - diff)
    base_g = clamp_u8(32 + (inner >> 2))

    fogged_r = mix_u8(base_r, PALE_R, fog_u8)
    fogged_g = mix_u8(base_g, PALE_G, fog_u8)
    fogged_b = mix_u8(base_b, PALE_B, fog_u8)

    lit_r = mul_u8(fogged_r, light_u8)
    lit_g = mul_u8(fogged_g, light_u8)
    lit_b = mul_u8(fogged_b, light_u8)

    if status == ST_HIT:
        return lit_r, lit_g, lit_b
    else:
        return SKY_R, SKY_G, SKY_B


def rand_dir():
    f = random.uniform(-1.0, 1.0)
    return sat_signed(int(round(f * (1 << DIR_F))), DIR_W)

def rand_h():
    f = random.uniform(-1.0, 1.0)
    return sat_signed(int(round(f * (1 << H_F))), H_W)


def main():
    random.seed(SEED)
    records = []

    # Directed tests
    # 1. HIT, normal up, sun overhead -> full bright
    Nz = 1 << DIR_F
    records.append((ST_HIT, 0, 0,
                    0, 0, Nz,
                    0, 0, Nz,
                    320, 240))
    # 2. HIT, normal up, sun sideways -> dark
    records.append((ST_HIT, 0, 0,
                    0, 0, Nz,
                    Nz, 0, 0,
                    320, 240))
    # 3. MISS -> sky
    records.append((ST_MISS, 0, 0, 0, 0, Nz, 0, 0, Nz, 320, 240))
    # 4. OFFGRID -> sky
    records.append((ST_OFFGRID, 0, 0, 0, 0, Nz, 0, 0, Nz, 320, 240))
    # 5. HIT, low altitude, far step -> blue + fogged
    records.append((ST_HIT, -((1 << H_F)*0.9).__int__(), N_STEPS-1,
                    0, 0, Nz, 0, 0, Nz, 100, 400))
    # 6. HIT, high altitude, near step -> red, saturated
    records.append((ST_HIT, ((1 << H_F)*0.9).__int__(), 1,
                    0, 0, Nz, 0, 0, Nz, 500, 200))

    # Sun is hardcoded to (0, 0, 1) in the SV - constrain TB inputs to match.
    SUN_X = 0
    SUN_Y = 0
    SUN_Z = 1 << DIR_F   # = 8192

    # Random tests
    for _ in range(N_TESTS):
        st = random.choice([ST_HIT]*4 + [ST_MISS, ST_OFFGRID])
        h  = rand_h()
        sc = random.randint(0, (1 << STEP_W) - 1)
        Nx = rand_dir(); Ny = rand_dir(); Nz_v = rand_dir()
        sx = SUN_X; sy = SUN_Y; sz = SUN_Z
        px = random.randint(0, 639)
        py = random.randint(0, 479)
        records.append((st, h, sc, Nx, Ny, Nz_v, sx, sy, sz, px, py))

    # Layout per record (14 values, 16-bit each):
    #   Inputs (11):  status h_hit step_count Nx Ny Nz sun_dx sun_dy sun_dz px py
    #   Outputs (3):  r g b
    VPR = 14
    with open("shader_vectors.hex", "w") as f:
        f.write(f"// {len(records)} test records, {VPR} values each\n")
        for (st, h, sc, Nx, Ny, Nz_v, sx, sy, sz, px, py) in records:
            r, g, b = shader_model(st, h, sc, Nx, Ny, Nz_v, sx, sy, sz)
            vals = [
                st, h, sc, Nx, Ny, Nz_v, sx, sy, sz, px, py,
                r, g, b,
            ]
            for v in vals:
                f.write(to_unsigned_hex(v, 16) + "\n")

    print(f"Wrote shader_vectors.hex with {len(records)} records.")


if __name__ == "__main__":
    main()
