"""ESP32 panel reader, integrated into the server's asyncio loop (no bg thread).
Applies hardware inputs only when input_source == 'hardware'. Mirrors the
notebook's safe foreground pr.run() path, never pr.start(apply=True)."""

import asyncio
import serial

import server_2d

PORT = "/dev/ttyUSB0"
BAUD = 115200
PANEL_GRID = 128


def _parse(line):
    if not line.startswith("DATA,"):
        return None
    d = {}
    for item in line[5:].split(","):
        if "=" in item:
            k, v = item.split("=", 1)
            try:
                d[k.strip().lower()] = int(v.strip(), 0)
            except ValueError:
                d[k.strip().lower()] = v.strip()
    return d


def _panel_touched(d):
    return (
        "x" in d and "y" in d
        and int(d["x"]) >= 0 and int(d["y"]) >= 0
        and int(d.get("touch", 0) or 0) != 0
    )


class PanelReader:
    def __init__(self):
        self.ser = None
        self._buf = b""
        self._amp_prev = None
        self._cond_prev = None
        self._cam_prev = None
        self._clear_prev = 0
        self.last = None  # most recent parsed record (for UI mirroring later)

    def open(self):
        self.ser = serial.Serial(PORT, BAUD, timeout=0)
        self.ser.reset_input_buffer()

    def _read_records(self):
        try:
            chunk = self.ser.read(4096)
        except Exception:
            return []
        if chunk:
            self._buf += chunk
        if b"\n" not in self._buf:
            return []
        parts = self._buf.split(b"\n")
        self._buf = parts[-1]
        out = []
        for p in parts[:-1]:
            rec = _parse(p.decode("ascii", "ignore").strip())
            if rec:
                self.last = rec
                out.append(rec)
        return out

    def _apply(self, d):
        r = server_2d._state.get("ctrl")
        if r is None:
            return

        # amplitude (0..1023 -> 0..0.5), deadband 8
        if "amp" in d:
            amp_raw = max(0, min(1023, int(d["amp"])))
            if self._amp_prev is None or abs(amp_raw - self._amp_prev) >= 8:
                self._amp_prev = amp_raw
                r.set_amplitude((amp_raw / 1023.0) * 0.50)

        # conductivity knob -> wave speed (0..1023 -> 0..600000), deadband 8
        if "cond" in d:
            c_raw = max(0, min(1023, int(d["cond"])))
            if self._cond_prev is None or abs(c_raw - self._cond_prev) >= 8:
                self._cond_prev = c_raw
                r.set_speed(int((c_raw / 1023.0) * 600000))

        # camera knobs -> set_camera (3D only). yaw 0..360, pitch 2..89, dist 0.4..2.0
        if hasattr(r, "set_camera") and all(k in d for k in ("yaw", "pitch", "zoom")):
            yaw_raw   = max(0, min(1023, int(d["yaw"])))
            pitch_raw = max(0, min(1023, int(d["pitch"])))
            zoom_raw  = max(0, min(1023, int(d["zoom"])))
            cam = (yaw_raw, pitch_raw, zoom_raw)
            if self._cam_prev is None or any(abs(a-b) >= 8 for a,b in zip(cam, self._cam_prev)):
                self._cam_prev = cam
                r.set_camera(
                    yaw_deg=(yaw_raw / 1023.0) * 360.0,
                    pitch_deg=2.0 + (pitch_raw / 1023.0) * 87.0,
                    dist=0.4 + (zoom_raw / 1023.0) * 1.6,
                )

        # clear button: act on rising edge only
        clr = int(d.get("clear", 0) or 0)
        if clr and not self._clear_prev:
            r.clear_fields()
        self._clear_prev = clr

        # touch -> source placement
        if _panel_touched(d):
            r.set_source_position(int(d["x"]), int(d["y"]))


    def ui_snapshot(self):
        """Latest panel values converted to UI slider units, or None."""
        d = self.last
        if not d:
            return None
        out = {}
        if "amp" in d:
            out["amplitude"] = round((max(0, min(1023, int(d["amp"]))) / 1023.0) * 0.50, 3)
        if "cond" in d:
            out["speed"] = int((max(0, min(1023, int(d["cond"]))) / 1023.0) * 600000)
        if all(k in d for k in ("yaw", "pitch", "zoom")):
            out["yaw"]   = round((max(0, min(1023, int(d["yaw"])))   / 1023.0) * 360.0, 1)
            out["pitch"] = round(2.0 + (max(0, min(1023, int(d["pitch"]))) / 1023.0) * 87.0, 1)
            out["dist"]  = round(0.4 + (max(0, min(1023, int(d["zoom"])))  / 1023.0) * 1.6, 2)
        return out

    async def loop(self):
        import logging
        log = logging.getLogger("panel_reader")
        try:
            if self.ser is None:
                self.open()
                log.info("panel serial opened on %s", PORT)
        except Exception as exc:
            log.error("panel open FAILED: %s", exc)
            return
        while True:
            try:
                recs = self._read_records()
                if recs and server_2d.get_input_source() == "hardware":
                    self._apply(recs[-1])
            except Exception as exc:
                log.error("panel loop error: %s", exc)
            await asyncio.sleep(0.02)
