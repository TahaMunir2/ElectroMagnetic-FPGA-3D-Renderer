import math
import time

from pynq import MMIO


REG_CONTROL = 0x00
REG_STATUS = 0x04

REG_OX = 0x10
REG_OY = 0x14
REG_OZ = 0x18

REG_FWD_X = 0x20
REG_FWD_Y = 0x24
REG_FWD_Z = 0x28

REG_RIGHT_X = 0x30
REG_RIGHT_Y = 0x34
REG_RIGHT_Z = 0x38

REG_UP_X = 0x40
REG_UP_Y = 0x44
REG_UP_Z = 0x48


def _q2_13(value):
    raw = int(round(value * 8192.0))
    raw = max(-32768, min(32767, raw))
    return raw & 0xFFFF


def _norm(v):
    length = math.sqrt(sum(c * c for c in v))
    if length == 0:
        raise ValueError("zero-length vector")
    return tuple(c / length for c in v)


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


class CameraControl:
    def __init__(self, base_addr, length=0x100):
        self.mmio = MMIO(base_addr, length)

    def write_look_at(self, position, target, wait=True):
        fwd = _norm(tuple(t - p for p, t in zip(position, target)))
        world_up = (0.0, 0.0, 1.0)
        right = _norm(_cross(fwd, world_up))
        up = _cross(right, fwd)
        self.write_basis(position, fwd, right, up, wait=wait)

    def write_yaw_pitch(self, position, yaw_deg, pitch_deg, wait=True):
        yaw = math.radians(yaw_deg)
        pitch = math.radians(pitch_deg)

        cp = math.cos(pitch)
        fwd = _norm((
            cp * math.cos(yaw),
            cp * math.sin(yaw),
            math.sin(pitch),
        ))

        world_up = (0.0, 0.0, 1.0)
        right = _norm(_cross(fwd, world_up))
        up = _cross(right, fwd)
        self.write_basis(position, fwd, right, up, wait=wait)

    def write_basis(self, position, fwd, right, up, wait=True):
        values = (
            (REG_OX, position[0]),
            (REG_OY, position[1]),
            (REG_OZ, position[2]),
            (REG_FWD_X, fwd[0]),
            (REG_FWD_Y, fwd[1]),
            (REG_FWD_Z, fwd[2]),
            (REG_RIGHT_X, right[0]),
            (REG_RIGHT_Y, right[1]),
            (REG_RIGHT_Z, right[2]),
            (REG_UP_X, up[0]),
            (REG_UP_Y, up[1]),
            (REG_UP_Z, up[2]),
        )

        for offset, value in values:
            self.mmio.write(offset, _q2_13(value))

        self.mmio.write(REG_CONTROL, 1)

        if wait:
            self.wait_committed()

    def wait_committed(self, timeout_s=0.1):
        deadline = time.monotonic() + timeout_s
        while self.mmio.read(REG_STATUS) & 1:
            if time.monotonic() > deadline:
                raise TimeoutError("camera commit did not complete")
            time.sleep(0.001)
