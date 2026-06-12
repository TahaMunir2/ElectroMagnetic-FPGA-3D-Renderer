"""
CPU baseline for the FDTD solver. Runs the same architecture as the PL:
2D TE mode, Q3.13 16 bit fixed point, round-to-nearest renormalisation,
two-pass update (Ey+Ex then Bz), 6 cell cubic PML, cb = -717.

Run this on the PYNQ-Z1 (python3 scripts/cpu_benchmark.py) to get the
Cortex-A9 number for the report. NumPy vectorised is the strongest
realistic CPU implementation available in python; a scalar C loop on
the A9 lands lower.
"""

import time
import numpy as np

GRID = 128
PML = 6
CB = -717
ITERS = 200

CA_RAMP = np.array([8192, 8174, 8045, 7695, 7014, 5892], dtype=np.int32)


def depth_map(n):
    idx = np.arange(n)
    d_lo = np.maximum(PML - 1 - idx, 0)
    d_hi = np.maximum(idx - (n - PML), 0)
    return np.minimum(d_lo + d_hi, PML - 1)


def build_coeffs():
    d_row = depth_map(GRID)
    d_col = depth_map(GRID)
    d_ey = np.broadcast_to(d_row[:, None], (GRID, GRID))
    d_ex = np.broadcast_to(d_col[None, :], (GRID, GRID))
    d_bz = np.maximum(d_ey, d_ex)
    return CA_RAMP[d_ey], CA_RAMP[d_ex], CA_RAMP[d_bz]


def q313(product):
    return ((product + 4096) >> 13).astype(np.int16)


def run(iters):
    ey = np.zeros((GRID, GRID), dtype=np.int16)
    ex = np.zeros((GRID, GRID), dtype=np.int16)
    bz = np.zeros((GRID, GRID), dtype=np.int16)
    ca_ey, ca_ex, ca_bz = build_coeffs()

    src_r, src_c = GRID // 2, GRID // 2
    phase_step = 450 / 8192.0

    bz_up = np.zeros((GRID, GRID), dtype=np.int32)
    bz_left = np.zeros((GRID, GRID), dtype=np.int32)

    t0 = time.perf_counter()
    for it in range(iters):
        bz32 = bz.astype(np.int32)
        bz_up[1:, :] = bz32[:-1, :]
        bz_up[0, :] = 0
        bz_left[:, 1:] = bz32[:, :-1]
        bz_left[:, 0] = 0

        ey = q313(ca_ey * ey + CB * (bz32 - bz_up))
        ex = q313(ca_ex * ex - CB * (bz32 - bz_left))

        ey[0, :] = 0
        ey[-1, :] = 0
        ex[:, 0] = 0
        ex[:, -1] = 0

        s = int(ey[src_r, src_c]) + int(2048 * np.sin(it * phase_step))
        ey[src_r, src_c] = np.int16(((s + 32768) & 0xFFFF) - 32768)

        ey32 = ey.astype(np.int32)
        ex32 = ex.astype(np.int32)
        ey_down = np.zeros_like(ey32)
        ey_down[:-1, :] = ey32[1:, :]
        ex_right = np.zeros_like(ex32)
        ex_right[:, :-1] = ex32[:, 1:]

        bz = q313(ca_bz * bz + CB * ((ey_down - ey32) - (ex_right - ex32)))

    t1 = time.perf_counter()
    return t1 - t0


def main():
    run(10)
    elapsed = run(ITERS)

    cells = GRID * GRID * ITERS
    updates = 3 * cells
    print(f"grid {GRID}x{GRID}, {ITERS} iterations in {elapsed:.3f} s")
    print(f"cell updates  : {cells / elapsed / 1e6:8.1f} MCells/s")
    print(f"field updates : {updates / elapsed / 1e6:8.1f} M/s")
    print(f"fpga 16 lane  :   2400.0 M/s")
    print(f"speedup       : {2.4e9 / (updates / elapsed):8.1f}x")


if __name__ == "__main__":
    main()
