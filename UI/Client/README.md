# Laptop Renderer Client

Static browser UI for controlling the PYNQ FPGA renderer server.

## Run

Open `index.html` directly in a browser, or serve this folder with any static file server.

```bash
cd UI/Client
python -m http.server 8080
```

Then open:

```text
http://127.0.0.1:8080
```

## Use

1. Enter the PYNQ server URL, for example `http://192.168.2.99:8000`.
2. Click `Connect`.
3. Move sliders or change modes.
4. Enable preview to display `http://<pynq-ip>:8000/preview.mjpg`.

The client sends WebSocket messages to:

```text
ws://<pynq-ip>:8000/ws/control
```

Messages are throttled to roughly 30 Hz and use the JSON format from `Client.md`.

