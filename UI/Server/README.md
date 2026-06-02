# PYNQ Renderer Server

FastAPI server for controlling the PL renderer from the laptop UI.

## Run On PYNQ

```bash
cd UI/Server
pip install -r requirements.txt
export RENDERER_MMIO_BASE=0x43C00000
python server.py
```

Server URL:

```text
http://<pynq-ip>:8000
```

## Run Without Hardware

The server automatically falls back to mock MMIO if `pynq.MMIO` is unavailable.

```bash
cd UI/Server
pip install -r requirements.txt
python server.py
```

Useful endpoints:

```text
GET  /health
GET  /registers
POST /params
WS   /ws/control
GET  /preview.mjpg
```

## Parameter Example

```bash
curl -X POST http://127.0.0.1:8000/params \
  -H "Content-Type: application/json" \
  -d '{"yaw":1024,"pitch":128,"camera_x":0,"camera_y":0,"camera_z":8192,"height_scale":180,"colour_mode":0,"render_mode":0,"max_depth":64,"step_size":1}'
```

The server converts `yaw` and `pitch` into fixed-point camera basis vectors before writing MMIO registers.

## Environment

```text
RENDERER_MMIO_BASE=0x43C00000
RENDERER_MMIO_LENGTH=0x10000
RENDERER_MOCK_MMIO=1
RENDERER_ANGLE_UNITS_PER_TURN=4096
RENDERER_Q_DIR_FRAC_BITS=13
RENDERER_Q_POS_FRAC_BITS=13
RENDERER_PREVIEW_WIDTH=320
RENDERER_PREVIEW_HEIGHT=240
RENDERER_PREVIEW_FPS=10
HOST=0.0.0.0
PORT=8000
```

