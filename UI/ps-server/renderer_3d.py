"""3D FDTD terrain renderer control (fdtd_3d.bit). Same solver/motion as 2D,
plus an orbitable camera (set_camera writes CAMA/B/C, latched via MOTION bit3)."""

from __future__ import annotations
import math, time
from pynq import MMIO

GRID = 128
GPIO_CH1, GPIO_CH2 = 0x0, 0x8
DEFAULT_HEIGHT = 6
DEFAULT_SPEED = 300000


def cell(x, y): return y * GRID + x
def q313(v):    return int(round(v * 8192)) & 0xFFFF


class Renderer3D:
    def __init__(self):
        self.ctrl   = MMIO(0x41200000, 0x10000)
        self.motion = MMIO(0x41210000, 0x10000)
        self.status = MMIO(0x41220000, 0x10000)
        self.cama   = MMIO(0x41230000, 0x10000)
        self.camb   = MMIO(0x41240000, 0x10000)
        self.camc   = MMIO(0x41250000, 0x10000)

    # ---- solver control (same as 2D) ----
    def set_ctrl(self, phase_step, amplitude, source_addr, solver_enable,
                 mag_mode, sample_req, free_run, height_ctl=3):
        ch1 = (q313(amplitude) << 16) | q313(phase_step)
        ch2 = (((mag_mode >> 1) & 1) << 23) | ((height_ctl & 0x1F) << 18) \
            | ((free_run & 1) << 17) | ((sample_req & 1) << 16) \
            | ((mag_mode & 1) << 15) | ((solver_enable & 1) << 14) \
            | (source_addr & 0x3FFF)
        self.ctrl.write(GPIO_CH1, ch1)
        self.ctrl.write(GPIO_CH2, ch2)

    def start_default(self):
        self.set_ctrl(phase_step=0.15, amplitude=0.15, source_addr=cell(64, 48),
                      solver_enable=1, mag_mode=2, sample_req=1, free_run=1,
                      height_ctl=3)
        self.set_speed(400000)
        self.set_camera()  # default isometric

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
        self.ctrl.write(GPIO_CH2, v | (1 << 24)); time.sleep(0.005)
        self.ctrl.write(GPIO_CH2, v & ~(1 << 24))

    def set_speed(self, idle_cycles):
        ch2 = (self.motion.read(0x8) & 0xFF) | ((idle_cycles & 0xFFFFFF) << 8)
        self.motion.write(0x8, ch2)

    # ---- camera ----
    def _q(self, v):
        iv = max(-32768, min(32767, int(round(v * 8192))))
        return iv & 0xFFFF


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

    def set_camera(self, yaw_deg=233.0, pitch_deg=67.0, dist=1.28):
        pitch_deg = max(2.0, min(89.0, pitch_deg))
        ya, pa = math.radians(yaw_deg), math.radians(pitch_deg)
        cy, sy, cp, sp = math.cos(ya), math.sin(ya), math.cos(pa), math.sin(pa)
        fwd = (cp*cy, cp*sy, -sp)
        O   = (-dist*fwd[0], -dist*fwd[1], -dist*fwd[2])
        rgt = (fwd[1], -fwd[0], 0.0)
        rn  = math.hypot(rgt[0], rgt[1]) or 1.0
        rgt = (rgt[0]/rn, rgt[1]/rn, 0.0)
        up  = (rgt[1]*fwd[2]-rgt[2]*fwd[1],
               rgt[2]*fwd[0]-rgt[0]*fwd[2],
               rgt[0]*fwd[1]-rgt[1]*fwd[0])
        q = self._q
        self.cama.write(0x0, (q(O[1])  << 16) | q(O[0]))
        self.cama.write(0x8, (q(fwd[0])<< 16) | q(O[2]))
        self.camb.write(0x0, (q(fwd[2])<< 16) | q(fwd[1]))
        self.camb.write(0x8, (q(rgt[1])<< 16) | q(rgt[0]))
        self.camc.write(0x0, (q(up[0]) << 16) | q(rgt[2]))
        self.camc.write(0x8, (q(up[2]) << 16) | q(up[1]))
        base = self.motion.read(0x8) & ~(1 << 3)
        self.motion.write(0x8, base)
        self.motion.write(0x8, base | (1 << 3))
