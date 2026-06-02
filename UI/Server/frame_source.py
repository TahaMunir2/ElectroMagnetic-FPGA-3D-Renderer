"""Preview frame source.

The initial implementation returns a generated RGB test frame. On PYNQ this
can later be replaced with a VDMA/DMA/shared-DDR reader without changing the
FastAPI endpoint.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass

import numpy as np


@dataclass
class FrameSource:
    width: int = 320
    height: int = 240

    def get_latest_frame(self) -> np.ndarray:
        """Return latest RGB frame as HxWx3 uint8 numpy array."""
        t = time.time()
        x = np.linspace(0, 255, self.width, dtype=np.uint8)
        y = np.linspace(0, 255, self.height, dtype=np.uint8)
        xx = np.tile(x, (self.height, 1))
        yy = np.tile(y[:, None], (1, self.width))

        phase = int((math.sin(t * 2.0) * 0.5 + 0.5) * 255)
        frame = np.empty((self.height, self.width, 3), dtype=np.uint8)
        frame[:, :, 0] = xx
        frame[:, :, 1] = yy
        frame[:, :, 2] = np.uint8(phase)

        # Add a moving white bar so preview liveness is obvious.
        bar_x = int((t * 40.0) % self.width)
        frame[:, max(0, bar_x - 2) : min(self.width, bar_x + 2), :] = 255
        return frame


def encode_jpeg(frame: np.ndarray, quality: int = 80) -> bytes:
    """Encode an RGB frame to JPEG bytes."""
    from io import BytesIO

    from PIL import Image

    image = Image.fromarray(frame, mode="RGB")
    output = BytesIO()
    image.save(output, format="JPEG", quality=quality, optimize=False)
    return output.getvalue()

