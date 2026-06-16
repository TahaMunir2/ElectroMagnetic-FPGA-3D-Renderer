
#include <stdint.h>
#include <string.h>
#include <math.h>

#define GRID 128
#define PML 6
#define CB (-717)

static int16_t ey[GRID][GRID], ex[GRID][GRID], bz[GRID][GRID];
static int32_t ca_ey[GRID][GRID], ca_ex[GRID][GRID], ca_bz[GRID][GRID];
static int iter_count = 0;

static inline int16_t q313(int32_t p) { return (int16_t)((p + 4096) >> 13); }

static int depth(int i) {
    int lo = PML - 1 - i;
    int hi = i - (GRID - PML);
    int d = (lo > 0 ? lo : 0) + (hi > 0 ? hi : 0);
    return d > PML - 1 ? PML - 1 : d;
}

void init(const int32_t *ramp) {
    for (int r = 0; r < GRID; r++)
        for (int c = 0; c < GRID; c++) {
            int dr = depth(r), dc = depth(c);
            ca_ey[r][c] = ramp[dr];
            ca_ex[r][c] = ramp[dc];
            ca_bz[r][c] = ramp[dr > dc ? dr : dc];
        }
}

void reset(void) {
    memset(ey, 0, sizeof ey);
    memset(ex, 0, sizeof ex);
    memset(bz, 0, sizeof bz);
    iter_count = 0;
}

void run(int iters, int nthreads) {
    for (int n = 0; n < iters; n++) {
        #pragma omp parallel for num_threads(nthreads) schedule(static)
        for (int r = 0; r < GRID; r++) {
            for (int c = 0; c < GRID; c++) {
                int32_t b  = bz[r][c];
                int32_t bu = r ? bz[r-1][c] : 0;
                int32_t bl = c ? bz[r][c-1] : 0;
                int16_t eyn = q313(ca_ey[r][c] * ey[r][c] + CB * (b - bu));
                int16_t exn = q313(ca_ex[r][c] * ex[r][c] - CB * (b - bl));
                ey[r][c] = (r == 0 || r == GRID-1) ? 0 : eyn;
                ex[r][c] = (c == 0 || c == GRID-1) ? 0 : exn;
            }
        }

        int32_t s = (int32_t)ey[GRID/2][GRID/2]
                  + (int32_t)(2048.0 * sin(iter_count * 450.0 / 8192.0));
        ey[GRID/2][GRID/2] = (int16_t)s;
        iter_count++;

        #pragma omp parallel for num_threads(nthreads) schedule(static)
        for (int r = 0; r < GRID; r++) {
            for (int c = 0; c < GRID; c++) {
                int32_t eyd = (r < GRID-1) ? ey[r+1][c] : ey[r][c];
                int32_t exr = (c < GRID-1) ? ex[r][c+1] : 0;
                bz[r][c] = q313(ca_bz[r][c] * bz[r][c]
                          + CB * ((eyd - ey[r][c]) - (exr - ex[r][c])));
            }
        }
    }
}
