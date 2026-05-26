# Laptop Client Implementation Document

## Goal

Implement a laptop-based UI for controlling the FPGA renderer running on the PYNQ board. The UI sends renderer parameters to the PYNQ PS server and optionally displays a live preview stream.

The laptop should provide a clean demo interface. It does not perform FPGA rendering.

## Architecture

```text
Laptop Client
  -> WebSocket control messages
PYNQ PS Server
  -> AXI-Lite
PL Renderer

PYNQ PS Server
  -> MJPEG preview
Laptop Client
```

## Recommended Tech Stack

Use a browser-based UI.

Recommended simple stack:

```text
HTML
CSS
JavaScript
```

Optional advanced stack:

```text
React
Vite
TypeScript
```

For fastest implementation, plain HTML/JS is enough.

## Files

```text
laptop_client/
  index.html
  style.css
  app.js
  README.md
```

## UI Controls

Include controls for:

```text
yaw
pitch
camera_x
camera_y
camera_z
height_scale
colour_mode
render_mode
max_depth
step_size
connect/disconnect
preview enable/disable
```

Use sliders for continuous parameters and dropdowns for modes.

## Connection Settings

The user should be able to enter:

```text
PYNQ IP address
server port
```

Default:

```text
http://192.168.2.99:8000
```

Do not hard-code the IP permanently.

## Control Protocol

Use WebSocket:

```text
ws://<PYNQ_IP>:8000/ws/control
```

Send parameter messages as JSON.

Example:

```json
{
  "type": "params",
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

## Update Rate

Do not send every slider event immediately.

Throttle updates to:

```text
20-30 Hz maximum
```

Recommended:

```javascript
setInterval(sendCurrentParams, 33);
```

Only send when connected.

## Preview

Display MJPEG preview using an image element:

```html
<img id="preview" src="http://<PYNQ_IP>:8000/preview.mjpg">
```

Preview should be optional.

If preview fails, controls should still work.

## UI Layout

Suggested layout:

```text
Left panel:
  connection status
  IP / port
  connect button

Middle panel:
  renderer controls

Right panel:
  live preview
```

Show connection state clearly:

```text
Disconnected
Connecting
Connected
Error
```

## Error Handling

The client should handle:

* PYNQ server offline
* WebSocket disconnect
* preview unavailable
* invalid IP
* slow network

Do not freeze the UI.

## Acceptance Tests

* User can connect to PYNQ server.
* Sliders send WebSocket messages.
* Messages are throttled.
* UI shows connection status.
* Preview displays if `/preview.mjpg` is available.
* Controls still work if preview is disabled.
* Reconnection works after server restart.
