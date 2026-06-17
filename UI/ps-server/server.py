"""PYNQ PS server for the FPGA renderer."""

from __future__ import annotations

import asyncio
import logging
import math
import os
from typing import Any, Dict, Iterable, Tuple

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

import register_map as regs
from frame_source import FrameSource, encode_jpeg
from renderer_mmio import RendererMMIO
import server_2d
import panel_reader


logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
LOG = logging.getLogger(__name__)

MMIO_BASE_ADDR = int(os.getenv("RENDERER_MMIO_BASE", "0x43C00000"), 0)
MMIO_LENGTH = int(os.getenv("RENDERER_MMIO_LENGTH", "0x10000"), 0)
FORCE_MOCK_MMIO = os.getenv("RENDERER_MOCK_MMIO", "0").lower() in {"1", "true", "yes"}

ANGLE_UNITS_PER_TURN = int(os.getenv("RENDERER_ANGLE_UNITS_PER_TURN", "4096"))
Q_DIR_FRAC_BITS = int(os.getenv("RENDERER_Q_DIR_FRAC_BITS", "13"))

PREVIEW_WIDTH = int(os.getenv("RENDERER_PREVIEW_WIDTH", "320"))
PREVIEW_HEIGHT = int(os.getenv("RENDERER_PREVIEW_HEIGHT", "240"))
PREVIEW_FPS = float(os.getenv("RENDERER_PREVIEW_FPS", "10"))

MODE_RANGES = {
    "colour_mode": (0, 3),
    "color_mode": (0, 3),
    "render_mode": (0, 3),
    "max_depth": (1, 256),
    "step_size": (1, 1 << 20),
    "height_scale": (0, 1 << 20),
}

app = FastAPI(title="PYNQ FPGA Renderer Server")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

mmio = None  # lazy: legacy path only; opening at startup conflicts with overlay reload
frame_source = FrameSource(width=PREVIEW_WIDTH, height=PREVIEW_HEIGHT)
last_yaw = 0
last_pitch = 0


def clamp_int(value: Any, low: int, high: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail=f"Expected integer, got {value!r}")
    return max(low, min(high, parsed))


def to_fixed(value: float, frac_bits: int) -> int:
    scaled = int(round(float(value) * (1 << frac_bits)))
    return max(-(1 << 15), min((1 << 15) - 1, scaled))


def angle_to_radians(raw: Any) -> float:
    return (int(raw) / ANGLE_UNITS_PER_TURN) * (2.0 * math.pi)


def camera_basis_from_yaw_pitch(yaw_raw: Any, pitch_raw: Any) -> Dict[str, int]:
    yaw = angle_to_radians(yaw_raw)
    pitch = angle_to_radians(pitch_raw)

    cy = math.cos(yaw)
    sy = math.sin(yaw)
    cp = math.cos(pitch)
    sp = math.sin(pitch)

    fwd = (cp * cy, cp * sy, sp)
    right = (-sy, cy, 0.0)
    up = (-sp * cy, -sp * sy, cp)

    return {
        "fwd_x": to_fixed(fwd[0], Q_DIR_FRAC_BITS),
        "fwd_y": to_fixed(fwd[1], Q_DIR_FRAC_BITS),
        "fwd_z": to_fixed(fwd[2], Q_DIR_FRAC_BITS),
        "right_x": to_fixed(right[0], Q_DIR_FRAC_BITS),
        "right_y": to_fixed(right[1], Q_DIR_FRAC_BITS),
        "right_z": to_fixed(right[2], Q_DIR_FRAC_BITS),
        "up_x": to_fixed(up[0], Q_DIR_FRAC_BITS),
        "up_y": to_fixed(up[1], Q_DIR_FRAC_BITS),
        "up_z": to_fixed(up[2], Q_DIR_FRAC_BITS),
    }


def iter_param_writes(payload: Dict[str, Any]) -> Iterable[Tuple[str, int, int]]:
    global last_yaw, last_pitch

    updates: Dict[str, Any] = {}

    if "yaw" in payload or "pitch" in payload:
        if "yaw" in payload:
            last_yaw = int(payload["yaw"])
        if "pitch" in payload:
            last_pitch = int(payload["pitch"])
        updates.update(camera_basis_from_yaw_pitch(last_yaw, last_pitch))

    for key, value in payload.items():
        if key in {"type", "yaw", "pitch"}:
            continue
        updates[key] = value

    for key, value in updates.items():
        if key not in regs.PARAM_REGISTERS:
            continue

        if key in {"camera_x", "camera_y", "camera_z", "ox", "oy", "oz"}:
            fixed_value = clamp_int(value, -(1 << 15), (1 << 15) - 1)
        elif key in MODE_RANGES:
            low, high = MODE_RANGES[key]
            fixed_value = clamp_int(value, low, high)
        else:
            fixed_value = clamp_int(value, -(1 << 31), (1 << 31) - 1)

        yield key, regs.PARAM_REGISTERS[key], fixed_value


def apply_params(payload: Dict[str, Any], apply_at_frame_boundary: bool = True) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        raise HTTPException(status_code=422, detail="JSON body must be an object")

    written: Dict[str, int] = {}
    for key, offset, value in iter_param_writes(payload):
        mmio.write(offset, value)
        written[key] = value

    if apply_at_frame_boundary and written:
        control = mmio.read(regs.REG_CONTROL)
        mmio.write(regs.REG_CONTROL, control | regs.CONTROL_ENABLE | regs.CONTROL_APPLY)

    return {"written": written, "count": len(written)}


@app.get("/health")
async def health() -> Dict[str, Any]:
    return {
        "status": "ok",
        "overlay_loaded": (mmio.overlay_loaded if mmio else False),
        "mock_mmio": (mmio.mock if mmio else False),
        "mmio_base": f"0x{MMIO_BASE_ADDR:08X}",
        "mode": server_2d.current_mode(),
        "input_source": server_2d.get_input_source(),
    }


@app.get("/registers")
async def registers() -> Dict[str, int]:
    return mmio.snapshot(regs.READBACK_REGISTERS)


@app.post("/params")
async def post_params(payload: Dict[str, Any]) -> Dict[str, Any]:
    if server_2d.current_mode() in ("2d", "3d"):
        return server_2d.handle_2d_message(payload)
    return apply_params(payload)


@app.post("/overlay/load")
async def overlay_load(payload: Dict[str, Any]) -> Dict[str, Any]:
    mode = payload.get("mode")
    try:
        return server_2d.load_overlay(mode)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/input/source")
async def input_source(payload: Dict[str, Any]) -> Dict[str, Any]:
    try:
        return server_2d.set_input_source(payload.get("source"))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.get("/input/source")
async def get_input_source_ep() -> Dict[str, Any]:
    return {"input_source": server_2d.get_input_source()}




_panel_reader = panel_reader.PanelReader()


@app.on_event("startup")
async def _start_panel_reader():
    import asyncio
    try:
        asyncio.get_event_loop().create_task(_panel_reader.loop())
        LOG.info("panel reader task started")
    except Exception as exc:
        LOG.warning("panel reader not started: %s", exc)



@app.get("/panel/snapshot")
async def panel_snapshot() -> Dict[str, Any]:
    return {"snapshot": _panel_reader.ui_snapshot(), "raw": _panel_reader.last}


@app.websocket("/ws/control")
async def ws_control(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            # Wait for an incoming message, but time out ~10x/sec so we can also
            # push live hardware values back to the UI (slider mirroring).
            try:
                payload = await asyncio.wait_for(websocket.receive_json(), timeout=0.1)
            except asyncio.TimeoutError:
                if server_2d.get_input_source() == "hardware":
                    snap = _panel_reader.ui_snapshot()
                    if snap:
                        await websocket.send_json({"type": "hardware", "values": snap})
                continue

            if payload.get("type", "params") != "params":
                await websocket.send_json({"ok": False, "error": "unsupported message type"})
                continue
            try:
                if server_2d.current_mode() in ("2d", "3d"):
                    result = server_2d.handle_2d_message(payload)
                else:
                    result = apply_params(payload)
                await websocket.send_json({"ok": True, **result})
            except HTTPException as exc:
                await websocket.send_json({"ok": False, "error": exc.detail})
    except WebSocketDisconnect:
        LOG.info("WebSocket disconnected")


async def mjpeg_frames() -> Any:
    delay = 1.0 / max(PREVIEW_FPS, 1.0)
    while True:
        frame = frame_source.get_latest_frame()
        jpg = encode_jpeg(frame)
        yield (
            b"--frame\r\n"
            b"Content-Type: image/jpeg\r\n"
            + f"Content-Length: {len(jpg)}\r\n\r\n".encode("ascii")
            + jpg
            + b"\r\n"
        )
        await asyncio.sleep(delay)


@app.get("/preview.mjpg")
async def preview_mjpg() -> StreamingResponse:
    return StreamingResponse(
        mjpeg_frames(),
        media_type="multipart/x-mixed-replace; boundary=frame",
    )


@app.post("/control/enable")
async def enable_renderer() -> Dict[str, int]:
    control = mmio.read(regs.REG_CONTROL) | regs.CONTROL_ENABLE
    mmio.write(regs.REG_CONTROL, control)
    return {"control": control}


@app.post("/control/disable")
async def disable_renderer() -> Dict[str, int]:
    control = mmio.read(regs.REG_CONTROL) & ~regs.CONTROL_ENABLE
    mmio.write(regs.REG_CONTROL, control)
    return {"control": control}


@app.post("/control/reset")
async def reset_renderer() -> Dict[str, int]:
    control = mmio.read(regs.REG_CONTROL) | regs.CONTROL_SOFT_RESET
    mmio.write(regs.REG_CONTROL, control)
    mmio.write(regs.REG_CONTROL, control & ~regs.CONTROL_SOFT_RESET)
    return {"control": mmio.read(regs.REG_CONTROL)}


@app.get("/")
async def root() -> Dict[str, str]:
    return {"service": "pynq-renderer-server", "health": "/health"}


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("server:app", host=host, port=port, reload=False)