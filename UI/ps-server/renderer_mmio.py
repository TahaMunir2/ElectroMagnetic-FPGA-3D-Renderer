"""MMIO helpers for PYNQ and local development."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from threading import Lock
from typing import Dict


LOG = logging.getLogger(__name__)


def u32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


class MockMMIO:
    """Small in-memory stand-in for pynq.MMIO.

    This keeps the HTTP/WebSocket server testable on a laptop while the same
    code runs against real PYNQ MMIO on the board.
    """

    def __init__(self) -> None:
        self._regs: Dict[int, int] = {}
        self._lock = Lock()

    def write(self, offset: int, value: int) -> None:
        with self._lock:
            self._regs[int(offset)] = u32(value)

    def read(self, offset: int) -> int:
        with self._lock:
            return self._regs.get(int(offset), 0)


@dataclass
class RendererMMIO:
    base_addr: int
    length: int
    mock: bool = False

    def __post_init__(self) -> None:
        self._lock = Lock()
        self.overlay_loaded = False

        if self.mock:
            self._mmio = MockMMIO()
            LOG.warning("Using mock MMIO")
            return

        try:
            from pynq import MMIO  # type: ignore

            self._mmio = MMIO(self.base_addr, self.length)
            self.overlay_loaded = True
            LOG.info("Using PYNQ MMIO at 0x%08X", self.base_addr)
        except Exception as exc:
            self._mmio = MockMMIO()
            self.mock = True
            LOG.warning("PYNQ MMIO unavailable, using mock MMIO: %s", exc)

    def write(self, offset: int, value: int) -> None:
        with self._lock:
            self._mmio.write(offset, u32(value))

    def read(self, offset: int) -> int:
        with self._lock:
            return u32(self._mmio.read(offset))

    def snapshot(self, registers: Dict[str, int]) -> Dict[str, int]:
        return {name: self.read(offset) for name, offset in registers.items()}
