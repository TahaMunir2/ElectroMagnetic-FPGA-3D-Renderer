"""2D FDTD contour renderer control module.

Mirrors the helpers from test_fdtd_contour_128_cb.ipynb so the server can drive
the 2D wave simulation over AXI/GPIO. The notebook is the ground-truth contract.

MMIO bases (from the notebook):
  CTRL    0x41200000  - phase_step, amplitude, source, mag_mode, height, etc.
  MOTION  0x41210000  - moving source velocity + speed throttle
  PALETTE 0x41220000  - 16-entry contour palette (commit-toggle protocol)
  STATUS  0x41230000  - checksum, frame-ready flags
"""

from __future__ import annotations
import time
from pynq import MMIO

GRID = 128
GPIO_CH1, GPIO_CH2 = 0x0, 0x8

# Defaults confirmed on hardware.
DEFAULT_HEIGHT = 6
DEFAULT_SPEED = 300000

# Four validated palettes (RGB tuples). Match the UI exactly.
PALETTES = {
    "none": [(0,0,255),(0,80,255),(0,160,255),(0,255,255),(0,255,160),(0,255,80),
        (0,255,0),(128,255,0),(200,255,0),(255,255,0),(255,200,0),(255,160,0),
        (255,100,0),(255,40,0),(255,0,0),(180,0,0)],
    "protanopia": [(127,59,8),(162,78,7),(194,102,11),(224,130,20),(243,166,73),
        (253,197,127),(254,224,182),(249,239,225),(237,237,243),(216,218,235),
        (191,187,218),(161,152,197),(128,115,172),(99,64,148),(71,26,116),(45,0,75)],
    "deuteranopia": [(59,76,192),(79,105,217),(100,133,236),(123,159,249),(147,181,254),
        (170,199,253),(192,212,245),(212,219,230),(229,216,209),(242,203,183),
        (247,184,156),(245,160,129),(238,132,104),(224,101,79),(204,64,58),(180,4,38)],
    "tritanopia": [(103,0,31),(153,16,39),(190,48,54),(214,96,77),(234,142,112),
        (247,183,153),(253,219,199),(249,238,231),(234,241,245),(209,229,240),
        (167,208,228),(120,180,213),(67,147,195),(44,117,180),(24,84,147),(5,48,97)],
}


def cell(x, y):
    return y * GRID + x


def q313(v):
    return int(round(v * 8192)) & 0xFFFF


class Renderer2D:
    """Owns the 2D MMIO handles and exposes notebook-equivalent controls."""

    def __init__(self):
        self.ctrl = MMIO(0x41200000, 0x10000)
        self.status = MMIO(0x41230000, 0x10000)
        self.motion = MMIO(0x41210000, 0x10000)
        self.palette = MMIO(0x41220000, 0x10000)
        self._palette_commit = 0

    # ---- main control ----
    def set_ctrl(self, phase_step, amplitude, source_addr, solver_enable,
                 mag_mode, sample_req, free_run, height_ctl=DEFAULT_HEIGHT):
        ch1 = (q313(amplitude) << 16) | q313(phase_step)
        ch2 = (((mag_mode >> 1) & 1) << 23) | ((height_ctl & 0x1F) << 18) \
            | ((free_run & 1) << 17) | ((sample_req & 1) << 16) \
            | ((mag_mode & 1) << 15) | ((solver_enable & 1) << 14) \
            | (source_addr & 0x3FFF)
        self.ctrl.write(GPIO_CH1, ch1)
        self.ctrl.write(GPIO_CH2, ch2)

    def start_default(self):
        """Start the sim with the confirmed-good defaults."""
        self.set_ctrl(phase_step=0.18, amplitude=0.3, source_addr=cell(64, 48),
                      solver_enable=1, mag_mode=2, sample_req=1, free_run=1,
                      height_ctl=DEFAULT_HEIGHT)
        self.set_speed(DEFAULT_SPEED)

    def set_amplitude(self, amp):
        ch1 = (self.ctrl.read(GPIO_CH1) & 0x0000FFFF) | (q313(amp) << 16)
        self.ctrl.write(GPIO_CH1, ch1)

    def set_phase_step(self, phase_step):
        ch1 = (self.ctrl.read(GPIO_CH1) & 0xFFFF0000) | q313(phase_step)
        self.ctrl.write(GPIO_CH1, ch1)

    def set_height(self, h):
        ch2 = (self.ctrl.read(GPIO_CH2) & ~(0x1F << 18)) | ((h & 0x1F) << 18)
        self.ctrl.write(GPIO_CH2, ch2)


    def set_source_position(self, x, y):
        """Place the point source at grid cell (x,y). Disables moving-source so
        static placement owns source_addr (CTRL CH2 [13:0])."""
        x = max(0, min(GRID - 1, int(round(x))))
        y = max(0, min(GRID - 1, int(round(y))))
        # turn off moving-source engine (MOTION CH2 bit0)
        self.motion.write(0x8, self.motion.read(0x8) & ~0x1)
        v = self.ctrl.read(GPIO_CH2)
        self.ctrl.write(GPIO_CH2, (v & ~0x3FFF) | (cell(x, y) & 0x3FFF))


    def set_mag_mode(self, m):
        """Display quantity: 0=|E|, 1=|S|, 2=Ey, 3=Bz(untested).
        2-bit field split across CTRL CH2 bit15 (lo) and bit23 (hi)."""
        m = int(m) & 0x3
        ch2 = self.ctrl.read(GPIO_CH2)
        ch2 = (ch2 & ~(1 << 15)) | ((m & 1) << 15)
        ch2 = (ch2 & ~(1 << 23)) | (((m >> 1) & 1) << 23)
        self.ctrl.write(GPIO_CH2, ch2)

    def clear_fields(self):
        v = self.ctrl.read(GPIO_CH2)
        self.ctrl.write(GPIO_CH2, v | (1 << 24))
        time.sleep(0.005)
        self.ctrl.write(GPIO_CH2, v & ~(1 << 24))

    # ---- speed throttle (MOTION) ----
    def set_speed(self, idle_cycles):
        ch2 = (self.motion.read(0x8) & 0xFF) | ((idle_cycles & 0xFFFFFF) << 8)
        self.motion.write(0x8, ch2)

    # ---- palette ----
    def set_palette(self, rgb16):
        assert len(rgb16) == 16, "need 16 (R,G,B) tuples"
        for i, (r, g, b) in enumerate(rgb16):
            self.palette.write(0x0, (i << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF))
            self._palette_commit ^= 1
            self.palette.write(0x8, self._palette_commit)
            time.sleep(0.0005)

    def set_palette_by_name(self, name):
        pal = PALETTES.get(name, PALETTES["none"])
        self.set_palette(pal)
        return pal

# ---- motion / Doppler (MOTION block) ----
    def _s16(self, v):
        iv = max(-32768, min(32767, int(round(v * 256))))
        return iv & 0xFFFF

    def set_velocity(self, vx, vy):
        self.motion.write(0x0, (self._s16(vy) << 16) | self._s16(vx))
        base = self.motion.read(0x8) & ~0x1
        self.motion.write(0x8, base)
        self.motion.write(0x8, base | 0x1)

    def stop_motion(self):
        self.motion.write(0x8, self.motion.read(0x8) & ~0x1)

    def set_source_mode(self, dcfree=True):
        ch2 = self.motion.read(0x8)
        ch2 = (ch2 | 0x2) if dcfree else (ch2 & ~0x2)
        self.motion.write(0x8, ch2)

    def set_source_field(self, bz=True):
        ch2 = self.motion.read(0x8)
        ch2 = (ch2 | 0x4) if bz else (ch2 & ~0x4)
        self.motion.write(0x8, ch2)