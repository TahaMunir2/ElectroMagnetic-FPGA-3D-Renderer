# PS Server Implementation Document

## Goal

Implement a lightweight server running on the PYNQ PS. The server receives renderer control parameters from a laptop UI, writes them to AXI-Lite registers, and optionally streams a preview frame back to the laptop.

The PS should not perform rendering. Rendering remains in PL.

## Architecture

```text
Laptop UI
  -> WebSocket / HTTP
PYNQ PS Server
  -> AXI-Lite MMIO
PL Renderer

PL Renderer
  -> DMA / VDMA / shared frame buffer
PYNQ PS Server
  -> MJPEG / JPEG preview stream
Laptop UI
```

## Recommended Tech Stack

* Python
* FastAPI
* Uvicorn
* PYNQ MMIO
* OpenCV or PIL for JPEG encoding
* Optional: PYNQ DMA / VDMA buffer access

## Files

```text
ps_server/
  server.py
  register_map.py
  frame_source.py
  requirements.txt
  README.md
```

## Register Interface

Create a `register_map.py` file containing named offsets:

```python
REG_CONTROL      = 0x00
REG_YAW          = 0x04
REG_PITCH        = 0x08
REG_CAMERA_X     = 0x0C
REG_CAMERA_Y     = 0x10
REG_CAMERA_Z     = 0x14
REG_HEIGHT_SCALE = 0x18
REG_COLOUR_MODE  = 0x1C
REG_RENDER_MODE  = 0x20
REG_MAX_DEPTH    = 0x24
REG_STEP_SIZE    = 0x28
REG_STATUS       = 0x2C
```

Use integer fixed-point values. Do not send floats to PL unless the hardware explicitly supports them.

## Server Endpoints

### `GET /health`

Returns server status.

Example response:

```json
{
  "status": "ok",
  "overlay_loaded": true
}
```

### `POST /params`

Receives renderer parameters as JSON and writes them to MMIO registers.

Example request:

```json
{
  "yaw": 1024,
  "pitch": 256,
  "camera_x": 512,
  "camera_y": 512,
  "camera_z": 128,
  "height_scale": 180,
  "colour_mode": 1,
  "render_mode": 0,
  "max_depth": 64,
  "step_size": 1
}
```

Missing fields should be ignored.

### `WebSocket /ws/control`

Receives frequent parameter updates from the laptop UI.

Use this for sliders and live controls.

Message format:

```json
{
  "type": "params",
  "yaw": 1024,
  "pitch": 256,
  "height_scale": 180,
  "render_mode": 0
}
```

Server should write only fields that are present.

### `GET /preview.mjpg`

Returns an MJPEG stream.

This is optional. If no frame source is available, stream a test image or return an error.

## Preview Strategy

Start with low frame rate:

```text
320x240 JPEG @ 5-15 fps
```

Then test higher resolutions.

Do not block PL rendering if preview streaming is slow.

## Frame Source

Implement `frame_source.py` with a simple interface:

```python
def get_latest_frame() -> np.ndarray:
    """
    Return latest RGB frame as HxWx3 uint8 numpy array.
    """
```

Initial implementation may return a test pattern.

Later implementations can read from:

* DMA buffer
* VDMA frame buffer
* shared DDR memory

## Safety Rules

* Validate all input ranges before writing registers.
* Clamp invalid values.
* Do not crash if the laptop disconnects.
* Do not make the PL renderer wait for the PS.
* Preview should be optional and droppable.

## Acceptance Tests

* `GET /health` works.
* Laptop can send parameters and MMIO registers update.
* WebSocket remains stable under repeated slider updates.
* Preview stream works with a test frame.
* Server can run without preview enabled.
* Renderer continues running if laptop disconnects.
