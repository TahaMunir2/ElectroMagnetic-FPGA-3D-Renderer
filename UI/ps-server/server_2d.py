"""Mode handler + overlay loading for 2D (contour) and 3D (terrain)."""

from pynq import Overlay
from renderer_2d import Renderer2D
from renderer_3d import Renderer3D

OVERLAYS = {
    "2d": "/home/xilinx/jupyter_notebooks/Server/fdtd_hdmi.bit",
    "3d": "/home/xilinx/jupyter_notebooks/Server/fdtd_3d.bit",
}

_state = {"mode": None, "overlay": None, "ctrl": None}


def load_overlay(mode):
    if mode not in OVERLAYS:
        raise ValueError(f"unknown mode {mode}")
    ol = Overlay(OVERLAYS[mode])
    _state["overlay"] = ol
    _state["mode"] = mode
    if mode == "2d":
        r = Renderer2D(); r.start_default()
    else:
        r = Renderer3D(); r.start_default()
    _state["ctrl"] = r
    return {"mode": mode, "loaded": True}


def current_mode():
    return _state["mode"]


def handle_2d_message(payload):
    """Dispatch a control message to the active renderer (2D or 3D)."""
    if not ui_writes_allowed():
        return {"ok": True, "ignored": "hardware-mode"}
    r = _state["ctrl"]
    if r is None:
        return {"ok": False, "error": "no overlay loaded"}

    done = []
    for key, value in payload.items():
        if key == "type":
            continue
        try:
            if key == "cvd_mode" and hasattr(r, "set_palette_by_name"):
                names = ["none", "protanopia", "deuteranopia", "tritanopia"]
                r.set_palette_by_name(names[int(value)] if isinstance(value, (int, float)) else value)
            elif key == "amplitude":
                r.set_amplitude(float(value))
            elif key == "phase_step":
                r.set_phase_step(float(value))
            elif key == "height":
                r.set_height(int(value))
            elif key == "mag_mode" and hasattr(r, "set_mag_mode"):
                r.set_mag_mode(int(value))
            elif key == "speed":
                r.set_speed(int(value))
            elif key == "clear":
                r.clear_fields()
            elif key == "source_field" and hasattr(r, "set_source_field"):
                r.set_source_field(bool(value))
            elif key == "dcfree" and hasattr(r, "set_source_mode"):
                r.set_source_mode(bool(value))
            elif key in ("yaw", "pitch", "dist"):
                pass  # handled together below
            elif key in ("vx", "vy"):
                pass
            else:
                continue
            done.append(key)
        except Exception as exc:
            return {"ok": False, "error": f"{key}: {exc}"}

    # camera (3D): apply if any camera key present
    if hasattr(r, "set_camera") and any(k in payload for k in ("yaw", "pitch", "dist")):
        r.set_camera(
            yaw_deg=float(payload.get("yaw", 45.0)),
            pitch_deg=float(payload.get("pitch", 45.0)),
            dist=float(payload.get("dist", 0.64)),
        )
        done.append("camera")

    # velocity (Doppler): apply if present. Full sequence (DC-free + Bz + velocity),
    # matching the proven notebook path -- velocity alone leaves a frozen DC trail.
    if hasattr(r, "set_velocity") and ("vx" in payload or "vy" in payload):
        vx = float(payload.get("vx", 0))
        vy = float(payload.get("vy", 0))
        if vx != 0 or vy != 0:
            if hasattr(r, "set_source_mode"):
                r.set_source_mode(True)   # DC-free injection: no trail
            if hasattr(r, "set_source_field"):
                r.set_source_field(True)  # Bz monopole: circular wavefronts
            r.set_velocity(vx, vy)
        else:
            if hasattr(r, "stop_motion"):
                r.stop_motion()
        done.append("velocity")

    return {"ok": True, "applied": done}


# ---- input authority: "ui" or "hardware" ----
_input = {"source": "ui"}

def set_input_source(source):
    if source not in ("ui", "hardware"):
        raise ValueError(f"bad input source {source!r}")
    _input["source"] = source
    return {"input_source": source}

def get_input_source():
    return _input["source"]

def ui_writes_allowed():
    return _input["source"] == "ui"
