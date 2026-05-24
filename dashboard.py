#!/usr/bin/env python3
"""
NODE v1 — Interactive ALPACA control panel.

Run:  python dashboard.py
Then open http://localhost:5173 in a browser.
"""

import base64
import io
import json
import logging
import queue
import sys
import threading
import time
from typing import Any, Optional

import yaml
from flask import Flask, Response, jsonify, render_template_string, request, stream_with_context

from alpaca.discovery import discover_servers
from alpaca.safety_manager import SafetyManager
from alpaca.telescope import Telescope
from alpaca.camera import Camera


app = Flask(__name__)
logging.getLogger("werkzeug").setLevel(logging.WARNING)


# ── Shared state ───────────────────────────────────────────────────────────────

_state: dict[str, Any] = {
    "server":    None,
    "connected": False,
    "telescope": {
        "enabled":   False,
        "connected": False,
        "slewing":   None,
        "parked":    None,
        "tracking":  None,
        "ra":        None,
        "dec":       None,
        "busy":      False,
    },
    "camera": {
        "enabled":     False,
        "connected":   False,
        "state":       None,
        "state_name":  None,
        "image_ready": None,
        "exposing":    False,
    },
    "safety": {
        "safe":              True,
        "parked":            False,
        "reason":            "",
        "heartbeat_ok":      True,
        "disconnected_secs": None,
        "sun_elevation":     None,
        "dawn_threshold":    -18.0,
    },
    "image_captured": False,
    "image_id":       0,
    "error":          None,
}
_state_lock = threading.Lock()

_CAMERA_STATES = {
    0: "Idle", 1: "Waiting", 2: "Exposing",
    3: "Reading", 4: "Downloading", 5: "Error",
}


# ── Log broadcasting ───────────────────────────────────────────────────────────

_subscribers: list[queue.Queue] = []
_subscribers_lock = threading.Lock()
_log_history: list[dict] = []


def _broadcast(entry: dict) -> None:
    global _log_history
    _log_history.append(entry)
    if len(_log_history) > 300:
        _log_history = _log_history[-300:]
    with _subscribers_lock:
        dead = []
        for q in _subscribers:
            try:
                q.put_nowait(entry)
            except queue.Full:
                dead.append(q)
        for q in dead:
            _subscribers.remove(q)


class _BroadcastHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.setFormatter(logging.Formatter(
            "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            datefmt="%H:%M:%S",
        ))

    def emit(self, record: logging.LogRecord) -> None:
        _broadcast({
            "time":  time.strftime("%H:%M:%S", time.localtime(record.created)),
            "level": record.levelname,
            "name":  record.name,
            "msg":   self.format(record),
        })


logging.getLogger().addHandler(_BroadcastHandler())
logger = logging.getLogger("dashboard")


class _StdoutCapture:
    def write(self, text: str) -> None:
        text = text.strip()
        if text:
            logging.getLogger("stdout").info(text)

    def flush(self) -> None:
        pass


sys.stdout = _StdoutCapture()  # type: ignore[assignment]


# ── Device handles ─────────────────────────────────────────────────────────────

_tel: Optional[Telescope] = None
_cam: Optional[Camera] = None
_last_image_b64: Optional[str] = None
_last_image_lock = threading.Lock()


def _capture_image() -> None:
    global _last_image_b64
    if _cam is None:
        return
    try:
        import numpy as np
        from PIL import Image

        logger.info("Downloading image array from camera…")
        raw = _cam.image_array()
        arr = np.array(raw, dtype=np.float32)

        if arr.ndim == 3 and arr.shape[0] in (1, 3):
            arr = np.transpose(arr, (1, 2, 0))
            if arr.shape[2] == 1:
                arr = arr[:, :, 0]

        mn, mx = float(arr.min()), float(arr.max())
        if mx > mn:
            arr = (arr - mn) / (mx - mn) * 255.0
        arr = arr.clip(0, 255).astype(np.uint8)

        mode = "RGB" if arr.ndim == 3 else "L"
        img = Image.fromarray(arr, mode=mode)

        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()

        with _last_image_lock:
            _last_image_b64 = b64
        with _state_lock:
            _state["image_captured"] = True
            _state["image_id"] += 1
        logger.info("Image stored — %.1f KB PNG", len(b64) * 3 / 4 / 1024)
    except Exception as exc:
        logger.error("Image capture failed: %s", exc)


# ── Safety manager ─────────────────────────────────────────────────────────────

_safety_mgr: Optional[SafetyManager] = None


def _on_safety_unsafe() -> None:
    reason = _safety_mgr.status()["reason"] if _safety_mgr else "unknown"
    with _state_lock:
        _state["error"] = f"Safety stop: {reason}"
    logger.critical("Safety manager triggered: %s", reason)


# ── Background poller ──────────────────────────────────────────────────────────

_poller_stop = threading.Event()


def _poll_loop() -> None:
    while not _poller_stop.is_set():
        with _state_lock:
            tel_enabled = _state["telescope"]["enabled"]
            cam_enabled = _state["camera"]["enabled"]

        if tel_enabled and _tel is not None:
            try:
                ra       = _tel.ra()
                dec      = _tel.dec()
                slewing  = _tel.is_slewing()
                parked   = _tel.is_parked()
                tracking = _tel.is_tracking()
                with _state_lock:
                    _state["telescope"].update(
                        connected=True, ra=ra, dec=dec,
                        slewing=slewing, parked=parked, tracking=tracking,
                    )
            except Exception:
                with _state_lock:
                    _state["telescope"]["connected"] = False

        if cam_enabled and _cam is not None:
            try:
                state     = _cam.camera_state()
                img_ready = _cam.image_ready()
                with _state_lock:
                    _state["camera"].update(
                        connected=True, state=state,
                        state_name=_CAMERA_STATES.get(state, "Unknown"),
                        image_ready=img_ready,
                    )
            except Exception:
                with _state_lock:
                    _state["camera"]["connected"] = False

        if _safety_mgr is not None:
            try:
                safety_snap = _safety_mgr.status()
                with _state_lock:
                    _state["safety"].update(safety_snap)
            except Exception:
                pass

        time.sleep(1.0)


def _start_poller() -> None:
    _poller_stop.clear()
    t = threading.Thread(target=_poll_loop, daemon=True, name="alpaca-poller")
    t.start()


# ── Config helper ──────────────────────────────────────────────────────────────

def _load_config() -> dict:
    try:
        with open("config.yaml") as fh:
            return yaml.safe_load(fh)
    except FileNotFoundError:
        return {}


# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template_string(_HTML)


@app.route("/api/status")
def api_status():
    with _state_lock:
        return jsonify(dict(_state))


@app.route("/api/logs")
def api_logs():
    q: queue.Queue = queue.Queue(maxsize=400)
    for entry in _log_history:
        try:
            q.put_nowait(entry)
        except queue.Full:
            break
    with _subscribers_lock:
        _subscribers.append(q)

    def generate():
        try:
            while True:
                try:
                    entry = q.get(timeout=15)
                    yield f"data: {json.dumps(entry)}\n\n"
                except queue.Empty:
                    yield ": keepalive\n\n"
        finally:
            with _subscribers_lock:
                try:
                    _subscribers.remove(q)
                except ValueError:
                    pass

    return Response(
        stream_with_context(generate()),
        content_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.route("/api/discover", methods=["POST"])
def api_discover():
    cfg = _load_config()
    alpaca_cfg = cfg.get("alpaca", {})
    logger.info("Starting LAN discovery…")
    servers = discover_servers(
        port=alpaca_cfg.get("discovery_port", 32227),
        timeout=alpaca_cfg.get("discovery_timeout", 5),
    )
    return jsonify({"servers": servers})


@app.route("/api/connect", methods=["POST"])
def api_connect():
    global _tel, _cam
    data    = request.get_json(force=True) or {}
    host    = data.get("host", "")
    port    = int(data.get("port", 11111))
    cfg     = _load_config()
    api_ver = cfg.get("alpaca", {}).get("api_version", 1)
    devices = cfg.get("devices", {})

    logger.info("Connecting to ALPACA server %s:%d", host, port)
    with _state_lock:
        _state["server"]    = {"address": host, "port": port}
        _state["connected"] = False

    if devices.get("telescope", {}).get("enabled", False):
        num = devices["telescope"].get("device_number", 0)
        try:
            _tel = Telescope(host, port, num, api_ver)
            _tel.connect()
            with _state_lock:
                _state["telescope"].update(enabled=True, connected=True)
            if _safety_mgr is not None:
                _safety_mgr.attach_telescope(_tel)
        except Exception as exc:
            logger.error("Telescope connect failed: %s", exc)

    if devices.get("camera", {}).get("enabled", False):
        num = devices["camera"].get("device_number", 0)
        try:
            _cam = Camera(host, port, num, api_ver)
            _cam.connect()
            with _state_lock:
                _state["camera"].update(enabled=True, connected=True)
        except Exception as exc:
            logger.error("Camera connect failed: %s", exc)

    with _state_lock:
        _state["connected"] = True

    _start_poller()
    return jsonify({"ok": True})


@app.route("/api/telescope/unpark", methods=["POST"])
def api_unpark():
    if _tel is None:
        return jsonify({"error": "Telescope not connected"}), 400

    def _do():
        with _state_lock:
            _state["telescope"]["busy"] = True
        try:
            _tel.unpark()
        except Exception as exc:
            logger.error("Unpark failed: %s", exc)
        finally:
            with _state_lock:
                _state["telescope"]["busy"] = False

    threading.Thread(target=_do, daemon=True, name="tel-unpark").start()
    logger.info("Unpark commanded")
    return jsonify({"ok": True})


@app.route("/api/telescope/park", methods=["POST"])
def api_park():
    if _tel is None:
        return jsonify({"error": "Telescope not connected"}), 400

    def _do():
        with _state_lock:
            _state["telescope"]["busy"] = True
        try:
            _tel.park()
        except Exception as exc:
            logger.error("Park failed: %s", exc)
        finally:
            with _state_lock:
                _state["telescope"]["busy"] = False

    threading.Thread(target=_do, daemon=True, name="tel-park").start()
    logger.info("Park commanded")
    return jsonify({"ok": True})


@app.route("/api/telescope/tracking", methods=["POST"])
def api_tracking():
    if _tel is None:
        return jsonify({"error": "Telescope not connected"}), 400
    data    = request.get_json(force=True) or {}
    enabled = bool(data.get("enabled", True))
    try:
        _tel.set_tracking(enabled)
    except Exception as exc:
        logger.error("Set tracking failed: %s", exc)
        return jsonify({"error": str(exc)}), 500
    return jsonify({"ok": True})


@app.route("/api/slew", methods=["POST"])
def api_slew():
    if _tel is None:
        return jsonify({"error": "Telescope not connected"}), 400
    data = request.get_json(force=True) or {}
    try:
        ra  = float(data["ra"])
        dec = float(data["dec"])
    except (KeyError, ValueError):
        return jsonify({"error": "Invalid ra/dec"}), 400
    if not (0.0 <= ra < 24.0):
        return jsonify({"error": "RA must be in range [0, 24)"}), 400
    if not (-90.0 <= dec <= 90.0):
        return jsonify({"error": "Dec must be in range [-90, 90]"}), 400

    def _do():
        try:
            _tel.slew_to_coordinates(ra=ra, dec=dec)
        except Exception as exc:
            logger.error("Slew failed: %s", exc)

    threading.Thread(target=_do, daemon=True, name="tel-slew").start()
    logger.info("Slew commanded: RA=%.4f h  Dec=%.4f °", ra, dec)
    return jsonify({"ok": True})


@app.route("/api/camera/expose", methods=["POST"])
def api_expose():
    if _cam is None:
        return jsonify({"error": "Camera not connected"}), 400
    with _state_lock:
        if _state["camera"]["exposing"]:
            return jsonify({"error": "Exposure already in progress"}), 409

    data     = request.get_json(force=True) or {}
    duration = float(data.get("duration", 1.0))
    binning  = int(data.get("binning", 1))

    if duration <= 0:
        return jsonify({"error": "Duration must be > 0"}), 400
    if binning < 1:
        return jsonify({"error": "Binning must be >= 1"}), 400

    def _do():
        with _state_lock:
            _state["camera"]["exposing"]  = True
            _state["image_captured"]      = False
        try:
            _cam.set_binning(binning)
            _cam.expose(duration=duration, light=True)
            _capture_image()
        except Exception as exc:
            logger.error("Exposure failed: %s", exc)
        finally:
            with _state_lock:
                _state["camera"]["exposing"] = False

    threading.Thread(target=_do, daemon=True, name="cam-expose").start()
    logger.info("Exposure started: %.2f s  binning %dx%d", duration, binning, binning)
    return jsonify({"ok": True})


@app.route("/api/camera/abort", methods=["POST"])
def api_abort_exposure():
    if _cam is None:
        return jsonify({"error": "Camera not connected"}), 400
    try:
        _cam.abort_exposure()
        with _state_lock:
            _state["camera"]["exposing"] = False
    except Exception as exc:
        logger.error("Abort exposure failed: %s", exc)
        return jsonify({"error": str(exc)}), 500
    return jsonify({"ok": True})


@app.route("/api/safety")
def api_safety():
    if _safety_mgr is None:
        return jsonify({"enabled": False})
    return jsonify({"enabled": True, **_safety_mgr.status()})


@app.route("/api/image")
def api_image():
    with _last_image_lock:
        b64 = _last_image_b64
    if b64 is None:
        return jsonify({"error": "No image available"}), 404
    img_bytes = base64.b64decode(b64)
    return Response(img_bytes, content_type="image/png",
                    headers={"Cache-Control": "no-store"})


# ── HTML template ──────────────────────────────────────────────────────────────

_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NODE v1 — ALPACA Control</title>
<style>
:root {
  --bg:       #070a0e;
  --surface:  #0d1117;
  --surface2: #161b22;
  --border:   #21262d;
  --green:    #3fb950;
  --green-hi: #56d364;
  --yellow:   #d29922;
  --red:      #f85149;
  --blue:     #58a6ff;
  --gray:     #484f58;
  --text:     #c9d1d9;
  --dim:      #8b949e;
  --mono:     'Courier New', 'Consolas', monospace;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  background: var(--bg);
  color: var(--text);
  font-family: var(--mono);
  font-size: 13px;
  height: 100vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* ── Header ── */
.hdr {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 10px 20px;
  display: flex;
  align-items: center;
  gap: 14px;
  flex-shrink: 0;
}
.hdr-logo { font-size: 17px; font-weight: bold; color: var(--green-hi); letter-spacing: 3px; }
.hdr-sub  { color: var(--dim); font-size: 10px; letter-spacing: 2px; margin-top: 2px; }
.hdr-right { margin-left: auto; display: flex; gap: 8px; align-items: center; }
.hdr-server { color: var(--dim); font-size: 12px; }
.hdr-server span { color: var(--blue); }
.hdr-server.hidden { display: none; }

.conn-pill {
  display: flex; align-items: center; gap: 5px;
  font-size: 11px; letter-spacing: 1px;
}

/* ── Buttons ── */
.btn {
  padding: 4px 13px;
  border: 1px solid;
  background: transparent;
  font-family: var(--mono);
  font-size: 11px;
  cursor: pointer;
  letter-spacing: 1px;
  text-transform: uppercase;
  transition: background 0.12s, color 0.12s;
}
.btn-green  { border-color: var(--green);  color: var(--green); }
.btn-green:hover:not(:disabled)  { background: var(--green);  color: var(--bg); }
.btn-red    { border-color: var(--red);    color: var(--red); }
.btn-red:hover:not(:disabled)    { background: var(--red);    color: var(--bg); }
.btn-blue   { border-color: var(--blue);   color: var(--blue); }
.btn-blue:hover:not(:disabled)   { background: var(--blue);   color: var(--bg); }
.btn-yellow { border-color: var(--yellow); color: var(--yellow); }
.btn-yellow:hover:not(:disabled) { background: var(--yellow); color: var(--bg); }
.btn-dim    { border-color: var(--gray);   color: var(--dim); }
.btn-dim:hover:not(:disabled)    { background: var(--gray);   color: var(--text); }
.btn:disabled { opacity: 0.3; cursor: not-allowed; }
.btn-full { width: 100%; }

/* ── Dot indicators ── */
.dot {
  width: 8px; height: 8px; border-radius: 50%;
  display: inline-block; flex-shrink: 0;
}
.dot-green  { background: var(--green);  box-shadow: 0 0 6px var(--green); }
.dot-yellow { background: var(--yellow); box-shadow: 0 0 6px var(--yellow); }
.dot-red    { background: var(--red);    box-shadow: 0 0 6px var(--red); }
.dot-gray   { background: var(--gray); }

@keyframes pulse { 0%,100% { opacity:1; } 50% { opacity:.35; } }
.pulse { animation: pulse 1.1s ease-in-out infinite; }

/* ── Layout ── */
.main {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1px;
  background: var(--border);
  overflow: hidden;
  min-height: 0;
}

.log-footer {
  flex-shrink: 0;
  height: 180px;
  background: var(--surface);
  border-top: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* ── Panels ── */
.panel {
  background: var(--surface);
  padding: 16px 20px;
  display: flex; flex-direction: column; gap: 12px;
  overflow-y: auto; min-height: 0;
}

.img-col {
  grid-column: 1 / -1;
  background: var(--surface);
  padding: 14px 20px;
  display: flex; flex-direction: column; gap: 10px;
  overflow: hidden; min-height: 0;
}
.img-col.hidden { display: none; }

.panel-hdr {
  display: flex; align-items: center; justify-content: space-between;
  border-bottom: 1px solid var(--border); padding-bottom: 10px;
  flex-shrink: 0;
}
.panel-name {
  display: flex; align-items: center; gap: 8px;
  font-size: 11px; font-weight: bold; letter-spacing: 2px;
  text-transform: uppercase;
}
.panel-label {
  font-size: 10px; letter-spacing: 2px; color: var(--dim);
  text-transform: uppercase;
}

.badges { display: flex; gap: 5px; flex-wrap: wrap; align-items: center; }
.badge {
  padding: 2px 7px; font-size: 10px; letter-spacing: 1px;
  text-transform: uppercase; border: 1px solid var(--gray); color: var(--gray);
}
.badge-on   { border-color: var(--green);  color: var(--green); }
.badge-warn { border-color: var(--yellow); color: var(--yellow); }
.badge-err  { border-color: var(--red);    color: var(--red); }

/* ── Coordinates ── */
.coords { display: grid; grid-template-columns: 40px 1fr; gap: 4px 10px; align-items: center; }
.coord-lbl { color: var(--dim); font-size: 11px; text-align: right; }
.coord-val { font-size: 20px; color: var(--green-hi); letter-spacing: 2px; }
.coord-val.dim { color: var(--gray); }
.coord-raw { color: var(--dim); font-size: 11px; }

/* ── Control groups ── */
.ctrl-group {
  display: flex; flex-direction: column; gap: 6px;
}
.ctrl-row {
  display: flex; gap: 6px;
}
.ctrl-row .btn { flex: 1; }

.section-div {
  border-top: 1px solid var(--border);
  padding-top: 12px;
}

/* ── Input fields ── */
.inp {
  background: var(--bg); border: 1px solid var(--border);
  color: var(--text); font-family: var(--mono); font-size: 13px;
  padding: 6px 10px; width: 100%;
}
.inp:focus { outline: none; border-color: var(--blue); }
.inp-label { font-size: 10px; color: var(--dim); letter-spacing: 1px; margin-bottom: 3px; }
.inp-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.inp-group { display: flex; flex-direction: column; }

/* ── Camera state ── */
.cam-state { font-size: 24px; letter-spacing: 3px; }
.cs-idle   { color: var(--gray); }
.cs-wait   { color: var(--dim); }
.cs-expose { color: var(--yellow); }
.cs-read   { color: var(--blue); }
.cs-dl     { color: var(--blue); }
.cs-error  { color: var(--red); }
.cam-sub   { color: var(--dim); font-size: 11px; }

/* ── Image panel ── */
.img-inner {
  display: flex; align-items: flex-start; gap: 20px;
  overflow: hidden; min-height: 0;
}
.img-frame {
  border: 1px solid var(--border); background: #000;
  flex-shrink: 0; max-width: 420px;
}
.img-frame img {
  display: block; max-width: 420px; max-height: 260px;
  width: 100%; image-rendering: pixelated;
}
.img-meta { color: var(--dim); font-size: 11px; line-height: 1.9; }
.img-meta span { color: var(--text); }

/* ── Log ── */
.log-panel { display: flex; flex-direction: column; overflow: hidden; flex: 1; }
.log-hdr {
  padding: 6px 20px; border-bottom: 1px solid var(--border);
  display: flex; align-items: center; justify-content: space-between;
  flex-shrink: 0;
}
.log-body {
  flex: 1; overflow-y: auto;
  padding: 4px 20px; font-size: 12px; line-height: 1.6;
}
.log-body::-webkit-scrollbar { width: 5px; }
.log-body::-webkit-scrollbar-track { background: var(--bg); }
.log-body::-webkit-scrollbar-thumb { background: var(--border); }
.ll { display: flex; gap: 8px; }
.lt  { color: var(--dim); flex-shrink:0; width:68px; }
.llv { flex-shrink:0; width:50px; }
.llv.INFO    { color: var(--green); }
.llv.WARNING { color: var(--yellow); }
.llv.ERROR   { color: var(--red); }
.llv.DEBUG   { color: var(--gray); }
.ln  { color: var(--blue); flex-shrink:0; min-width:100px; max-width:140px; overflow:hidden; }
.lm  { color: var(--text); word-break: break-all; }
.lm.warn-msg { color: var(--yellow); }
.lm.err-msg  { color: var(--red); }
.count-badge {
  font-size: 10px; color: var(--dim);
  padding: 1px 7px; border: 1px solid var(--border);
}

/* ── Discovery overlay ── */
.overlay {
  position: fixed; inset: 0;
  background: rgba(7,10,14,.88);
  backdrop-filter: blur(3px);
  display: flex; align-items: center; justify-content: center;
  z-index: 50;
}
.overlay.hidden { display: none; }
.card {
  background: var(--surface2); border: 1px solid var(--border);
  padding: 24px 28px; width: 420px;
  display: flex; flex-direction: column; gap: 14px;
}
.card-title { font-size: 13px; letter-spacing: 2px; text-transform: uppercase; color: var(--green-hi); }
.inp-row { display: flex; gap: 8px; }
.srv-list { display: flex; flex-direction: column; gap: 5px; }
.srv-item {
  padding: 7px 12px; border: 1px solid var(--border);
  cursor: pointer; color: var(--blue); transition: border-color .12s, background .12s;
}
.srv-item:hover { border-color: var(--blue); background: rgba(88,166,255,.06); }
.sep { border-top: 1px solid var(--border); }
</style>
</head>
<body>

<!-- Header -->
<div class="hdr">
  <div>
    <div class="hdr-logo">NODE v1</div>
    <div class="hdr-sub">ALPACA CONTROL</div>
  </div>

  <div class="conn-pill">
    <span class="dot dot-gray" id="connDot"></span>
    <span id="connLabel">Disconnected</span>
  </div>

  <div class="hdr-server hidden" id="hdrServer">
    Server: <span id="hdrAddr"></span>
  </div>

  <div class="conn-pill" id="safetyPill" style="display:none">
    <span class="dot dot-green" id="safetyDot"></span>
    <span id="safetyLabel" style="letter-spacing:1px;font-size:11px;">SAFE</span>
    <span id="safetyReason" style="color:var(--dim);font-size:10px;margin-left:4px;"></span>
  </div>

  <div style="color:var(--dim);font-size:11px;" id="sunEl"></div>

  <div class="hdr-right">
    <button class="btn btn-blue" onclick="showDiscover()">Discover</button>
  </div>
</div>

<!-- Main grid -->
<div class="main">

  <!-- Telescope panel -->
  <div class="panel">
    <div class="panel-hdr">
      <div class="panel-name">
        <span class="dot dot-gray" id="telDot"></span>
        Telescope
      </div>
      <div class="badges" id="telBadges"></div>
    </div>

    <!-- Coordinates -->
    <div class="coords">
      <div class="coord-lbl">R.A.</div>
      <div class="coord-val dim" id="telRA">—</div>
      <div class="coord-lbl">Dec</div>
      <div class="coord-val dim" id="telDec">—</div>
    </div>
    <div class="coord-raw" id="telRaw"></div>

    <!-- Mount controls -->
    <div class="ctrl-group section-div">
      <div class="panel-label">Mount</div>
      <div class="ctrl-row">
        <button class="btn btn-green" id="btnUnpark" onclick="apiUnpark()" disabled>Unpark</button>
        <button class="btn btn-dim"   id="btnPark"   onclick="apiPark()"   disabled>Park</button>
      </div>
    </div>

    <!-- Tracking controls -->
    <div class="ctrl-group">
      <div class="panel-label">Tracking</div>
      <div class="ctrl-row">
        <button class="btn btn-green"  id="btnTrackOn"  onclick="apiTracking(true)"  disabled>Track ON</button>
        <button class="btn btn-yellow" id="btnTrackOff" onclick="apiTracking(false)" disabled>Track OFF</button>
      </div>
    </div>

    <!-- Slew -->
    <div class="ctrl-group section-div">
      <div class="panel-label">Slew Target</div>
      <div class="inp-grid">
        <div class="inp-group">
          <div class="inp-label">R.A. (decimal hours)</div>
          <input class="inp" id="slewRA" type="number" min="0" max="23.9999" step="0.0001" placeholder="0.0000">
        </div>
        <div class="inp-group">
          <div class="inp-label">Dec (decimal degrees)</div>
          <input class="inp" id="slewDec" type="number" min="-90" max="90" step="0.0001" placeholder="0.0000">
        </div>
      </div>
      <button class="btn btn-blue btn-full" id="btnSlew" onclick="apiSlew()" disabled>Slew to Target</button>
    </div>
  </div>

  <!-- Camera panel -->
  <div class="panel">
    <div class="panel-hdr">
      <div class="panel-name">
        <span class="dot dot-gray" id="camDot"></span>
        Camera
      </div>
      <div id="camReady" style="font-size:11px;color:var(--gray)"></div>
    </div>

    <!-- State display -->
    <div class="cam-state cs-idle" id="camState">—</div>
    <div class="cam-sub" id="camSub"></div>

    <!-- Exposure controls -->
    <div class="ctrl-group section-div">
      <div class="panel-label">Exposure</div>
      <div class="inp-grid">
        <div class="inp-group">
          <div class="inp-label">Duration (seconds)</div>
          <input class="inp" id="expDuration" type="number" min="0.001" step="0.1" value="1.0" placeholder="1.0">
        </div>
        <div class="inp-group">
          <div class="inp-label">Binning</div>
          <input class="inp" id="expBinning" type="number" min="1" max="8" step="1" value="1" placeholder="1">
        </div>
      </div>
      <div class="ctrl-row">
        <button class="btn btn-green" id="btnExpose" onclick="apiExpose()" disabled>Expose</button>
        <button class="btn btn-red"   id="btnAbortExp" onclick="apiAbortExposure()" disabled>Abort</button>
      </div>
    </div>
  </div>

  <!-- Image panel (hidden until capture) -->
  <div class="img-col hidden" id="imgPanel">
    <div class="panel-label">Last Exposure</div>
    <div class="img-inner">
      <div class="img-frame">
        <img id="lastImg" src="" alt="Last exposure">
      </div>
      <div class="img-meta" id="imgMeta"></div>
    </div>
  </div>

</div><!-- /main -->

<!-- Log footer -->
<div class="log-footer">
  <div class="log-panel">
    <div class="log-hdr">
      <div class="panel-label" style="margin:0">Live Log</div>
      <div style="display:flex;gap:8px;align-items:center;">
        <span class="count-badge" id="logCount">0 lines</span>
        <button class="btn btn-dim" style="padding:2px 8px;font-size:10px;" onclick="clearLog()">Clear</button>
      </div>
    </div>
    <div class="log-body" id="logBody"></div>
  </div>
</div>

<!-- Discovery overlay -->
<div class="overlay hidden" id="overlay">
  <div class="card">
    <div class="card-title">Connect to ALPACA Server</div>
    <button class="btn btn-blue" id="scanBtn" onclick="doScan()" style="width:100%">
      Scan LAN for servers
    </button>
    <div class="srv-list" id="srvList"></div>
    <div class="sep"></div>
    <div style="color:var(--dim);font-size:11px;">Manual entry</div>
    <div class="inp-row">
      <input class="inp" id="mHost" placeholder="192.168.1.x" style="flex:1">
      <input class="inp" id="mPort" placeholder="11111" style="width:80px">
    </div>
    <div style="display:flex;gap:8px;">
      <button class="btn btn-green" onclick="doManualConnect()" style="flex:1">Connect</button>
      <button class="btn btn-dim"   onclick="hideDiscover()">Cancel</button>
    </div>
  </div>
</div>

<script>
// ── Status polling ──────────────────────────────────────────────────────────

async function poll() {
  try {
    const r = await fetch("/api/status");
    render(await r.json());
  } catch {}
}
setInterval(poll, 1000);
poll();

function render(s) {
  renderHeader(s);
  renderTelescope(s.telescope || {});
  renderCamera(s.camera || {});
  renderSafety(s.safety || {});
  renderImage(s);
}

// ── Header ──────────────────────────────────────────────────────────────────

function renderHeader(s) {
  const dot   = document.getElementById("connDot");
  const label = document.getElementById("connLabel");

  if (s.server) {
    const srv = document.getElementById("hdrServer");
    srv.classList.remove("hidden");
    document.getElementById("hdrAddr").textContent =
      `${s.server.address}:${s.server.port}`;
  }

  if (s.connected) {
    dot.className    = "dot dot-green";
    label.textContent = "Connected";
  } else {
    dot.className    = "dot dot-gray";
    label.textContent = "Disconnected";
  }
}

// ── Safety ──────────────────────────────────────────────────────────────────

function renderSafety(sf) {
  const pill   = document.getElementById("safetyPill");
  const dot    = document.getElementById("safetyDot");
  const label  = document.getElementById("safetyLabel");
  const reason = document.getElementById("safetyReason");
  const sunEl  = document.getElementById("sunEl");

  if (!sf || sf.safe === undefined) { pill.style.display = "none"; return; }
  pill.style.display = "flex";

  if (sf.safe) {
    dot.className     = "dot dot-green";
    label.textContent = "SAFE";
    label.style.color = "var(--green)";
    reason.textContent = sf.heartbeat_ok ? "" : "hb?";
  } else {
    dot.className     = "dot dot-red pulse";
    label.textContent = "UNSAFE";
    label.style.color = "var(--red)";
    reason.textContent = sf.reason ? `· ${sf.reason}` : "";
  }

  if (sf.sun_elevation != null) {
    const el  = sf.sun_elevation.toFixed(1);
    const thr = sf.dawn_threshold != null ? sf.dawn_threshold.toFixed(0) : "-18";
    sunEl.style.color = sf.sun_elevation > sf.dawn_threshold ? "var(--yellow)" : "var(--dim)";
    sunEl.textContent = `☀ ${el >= 0 ? "+" : ""}${el}°`;
    sunEl.title       = `Sun elevation (dawn at ${thr}°)`;
  } else {
    sunEl.textContent = "";
  }
}

// ── Telescope ───────────────────────────────────────────────────────────────

function renderTelescope(t) {
  document.getElementById("telDot").className =
    t.connected ? "dot dot-green" : "dot dot-gray";

  const raEl  = document.getElementById("telRA");
  const decEl = document.getElementById("telDec");
  const rawEl = document.getElementById("telRaw");

  if (t.connected && t.ra != null) {
    raEl.textContent  = fmtRA(t.ra);
    decEl.textContent = fmtDec(t.dec);
    raEl.className    = "coord-val";
    decEl.className   = "coord-val";
    rawEl.textContent = `RA ${t.ra.toFixed(4)} h  ·  Dec ${t.dec?.toFixed(4)} °`;
  } else {
    raEl.textContent  = "—"; raEl.className  = "coord-val dim";
    decEl.textContent = "—"; decEl.className = "coord-val dim";
    rawEl.textContent = "";
  }

  // Badges
  const badges = document.getElementById("telBadges");
  badges.innerHTML = "";
  if (t.connected) {
    if (t.busy)                               badges.innerHTML += `<span class="badge badge-warn pulse">Busy</span>`;
    if (t.slewing)                            badges.innerHTML += `<span class="badge badge-warn pulse">Slewing</span>`;
    if (t.tracking)                           badges.innerHTML += `<span class="badge badge-on">Tracking</span>`;
    if (t.parked)                             badges.innerHTML += `<span class="badge badge-warn">Parked</span>`;
    if (!t.busy && !t.slewing && !t.tracking && !t.parked)
                                              badges.innerHTML += `<span class="badge">Idle</span>`;
  } else if (t.enabled) {
    badges.innerHTML += `<span class="badge badge-err">Disconnected</span>`;
  }

  // Button states — disabled while not connected, busy, or slewing
  const blocked = !t.connected || t.busy || t.slewing;
  document.getElementById("btnUnpark").disabled   = blocked;
  document.getElementById("btnPark").disabled     = blocked;
  document.getElementById("btnTrackOn").disabled  = blocked;
  document.getElementById("btnTrackOff").disabled = blocked;
  document.getElementById("btnSlew").disabled     = blocked;
}

// ── Camera ───────────────────────────────────────────────────────────────────

const CAM_CLASSES = ["cs-idle","cs-wait","cs-expose","cs-read","cs-dl","cs-error"];

function renderCamera(c) {
  document.getElementById("camDot").className =
    c.connected ? "dot dot-green" : "dot dot-gray";

  const stEl  = document.getElementById("camState");
  const subEl = document.getElementById("camSub");
  const rdEl  = document.getElementById("camReady");

  if (c.connected) {
    stEl.textContent = (c.exposing ? (c.state_name || "Exposing") : (c.state_name || "—")).toUpperCase();
    stEl.className   = "cam-state " + (CAM_CLASSES[c.state] || "cs-idle");
    if (c.state === 2 || c.exposing) stEl.classList.add("pulse");
    subEl.textContent = c.exposing ? `ALPACA state ${c.state} · exposure in progress` : `ALPACA state ${c.state}`;
    rdEl.textContent  = c.image_ready ? "✓ IMAGE READY" : "";
    rdEl.style.color  = c.image_ready ? "var(--green)" : "var(--gray)";
  } else {
    stEl.textContent = "—"; stEl.className = "cam-state cs-idle";
    subEl.textContent = c.enabled ? "Disconnected" : "Not enabled";
    rdEl.textContent  = "";
  }

  document.getElementById("btnExpose").disabled   = !c.connected || c.exposing;
  document.getElementById("btnAbortExp").disabled = !c.connected || !c.exposing;
}

// ── Image ────────────────────────────────────────────────────────────────────

let _lastImageId = -1;

async function renderImage(s) {
  if (!s.image_captured) return;
  if (s.image_id === _lastImageId) return;
  _lastImageId = s.image_id;

  const panel = document.getElementById("imgPanel");
  const img   = document.getElementById("lastImg");
  const meta  = document.getElementById("imgMeta");

  panel.classList.remove("hidden");
  meta.innerHTML = "Downloading…";

  try {
    const r    = await fetch("/api/image");
    if (!r.ok) throw new Error("HTTP " + r.status);
    const blob = await r.blob();
    const url  = URL.createObjectURL(blob);
    img.src = url;
    const kb = (blob.size / 1024).toFixed(1);
    const ts = new Date().toLocaleTimeString();
    img.onload = () => {
      meta.innerHTML =
        `Captured: <span>${ts}</span><br>` +
        `Size: <span>${img.naturalWidth} × ${img.naturalHeight} px</span><br>` +
        `File: <span>${kb} KB (PNG)</span>`;
    };
  } catch (e) {
    meta.innerHTML = `<span style="color:var(--red)">Image load failed: ${e.message}</span>`;
    _lastImageId = -1;
  }
}

// ── Coordinate formatters ────────────────────────────────────────────────────

function fmtRA(h) {
  if (h == null) return "—";
  const hr  = Math.floor(h);
  const mn  = Math.floor((h - hr) * 60);
  const sec = ((h - hr) * 3600 - mn * 60).toFixed(1);
  return `${pad(hr)}h ${pad(mn)}m ${String(sec).padStart(4,"0")}s`;
}

function fmtDec(d) {
  if (d == null) return "—";
  const sign = d >= 0 ? "+" : "−";
  const abs  = Math.abs(d);
  const deg  = Math.floor(abs);
  const mn   = Math.floor((abs - deg) * 60);
  const sec  = ((abs - deg) * 3600 - mn * 60).toFixed(1);
  return `${sign}${pad(deg)}° ${pad(mn)}' ${String(sec).padStart(4,"0")}"`;
}

function pad(n) { return String(n).padStart(2, "0"); }

// ── Telescope actions ────────────────────────────────────────────────────────

async function apiUnpark() {
  try { await fetch("/api/telescope/unpark", { method: "POST" }); }
  catch (e) { alert("Unpark failed: " + e.message); }
}

async function apiPark() {
  try { await fetch("/api/telescope/park", { method: "POST" }); }
  catch (e) { alert("Park failed: " + e.message); }
}

async function apiTracking(enabled) {
  try {
    await fetch("/api/telescope/tracking", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled }),
    });
  } catch (e) { alert("Set tracking failed: " + e.message); }
}

async function apiSlew() {
  const ra  = parseFloat(document.getElementById("slewRA").value);
  const dec = parseFloat(document.getElementById("slewDec").value);
  if (isNaN(ra) || isNaN(dec)) { alert("Enter valid RA (h) and Dec (°) values."); return; }
  const btn = document.getElementById("btnSlew");
  btn.disabled = true; btn.textContent = "Slewing…";
  try {
    const r = await fetch("/api/slew", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ra, dec }),
    });
    const d = await r.json();
    if (!d.ok) alert(d.error || "Slew failed");
  } catch (e) { alert("Slew failed: " + e.message); }
  btn.textContent = "Slew to Target";
  // disabled state re-evaluated on next poll
}

// ── Camera actions ───────────────────────────────────────────────────────────

async function apiExpose() {
  const duration = parseFloat(document.getElementById("expDuration").value);
  const binning  = parseInt(document.getElementById("expBinning").value);
  if (isNaN(duration) || duration <= 0) { alert("Enter a valid exposure duration > 0 s."); return; }
  if (isNaN(binning) || binning < 1)    { alert("Binning must be >= 1."); return; }
  try {
    const r = await fetch("/api/camera/expose", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ duration, binning }),
    });
    const d = await r.json();
    if (!d.ok) alert(d.error || "Expose failed");
  } catch (e) { alert("Expose failed: " + e.message); }
}

async function apiAbortExposure() {
  try { await fetch("/api/camera/abort", { method: "POST" }); }
  catch (e) { alert("Abort failed: " + e.message); }
}

// ── Log stream (SSE) ─────────────────────────────────────────────────────────

let logCount   = 0;
let autoScroll = true;
const logBody  = document.getElementById("logBody");

logBody.addEventListener("scroll", () => {
  autoScroll = logBody.scrollTop + logBody.clientHeight >= logBody.scrollHeight - 24;
});

function appendLog(entry) {
  logCount++;
  document.getElementById("logCount").textContent = logCount + " lines";

  const raw   = entry.msg || "";
  const match = raw.match(/^\S+\s+\[\w+\]\s+([^:]+):\s(.*)/s);
  const name  = match ? match[1] : (entry.name || "");
  const msg   = match ? match[2] : raw;

  const line = document.createElement("div");
  line.className = "ll";

  const t  = document.createElement("span"); t.className = "lt"; t.textContent = entry.time || "";
  const lv = document.createElement("span"); lv.className = "llv " + entry.level;
  lv.textContent = "[" + (entry.level || "").substring(0, 4) + "]";
  const nm = document.createElement("span"); nm.className = "ln"; nm.textContent = name;
  const ms = document.createElement("span"); ms.className = "lm";
  if (entry.level === "WARNING") ms.classList.add("warn-msg");
  if (entry.level === "ERROR")   ms.classList.add("err-msg");
  ms.textContent = msg;

  line.appendChild(t); line.appendChild(lv); line.appendChild(nm); line.appendChild(ms);
  logBody.appendChild(line);
  if (autoScroll) logBody.scrollTop = logBody.scrollHeight;
}

function clearLog() {
  logBody.innerHTML = ""; logCount = 0;
  document.getElementById("logCount").textContent = "0 lines";
}

const es = new EventSource("/api/logs");
es.onmessage = e => { try { appendLog(JSON.parse(e.data)); } catch {} };

// ── Discovery overlay ────────────────────────────────────────────────────────

function showDiscover()  { document.getElementById("overlay").classList.remove("hidden"); }
function hideDiscover()  { document.getElementById("overlay").classList.add("hidden"); }

async function doScan() {
  const btn = document.getElementById("scanBtn");
  btn.textContent = "Scanning…"; btn.disabled = true;
  document.getElementById("srvList").innerHTML = "";
  try {
    const r    = await fetch("/api/discover", { method: "POST" });
    const data = await r.json();
    const list = document.getElementById("srvList");
    if (data.servers?.length) {
      data.servers.forEach(srv => {
        const item = document.createElement("div");
        item.className   = "srv-item";
        item.textContent = `${srv.address}:${srv.port}`;
        item.onclick     = () => connectTo(srv.address, srv.port);
        list.appendChild(item);
      });
    } else {
      list.innerHTML = '<div style="color:var(--dim);font-size:12px;">No servers found on LAN.</div>';
    }
  } catch {
    document.getElementById("srvList").innerHTML =
      '<div style="color:var(--red);font-size:12px;">Discovery request failed.</div>';
  }
  btn.textContent = "Scan LAN for servers"; btn.disabled = false;
}

async function doManualConnect() {
  const host = document.getElementById("mHost").value.trim();
  const port = parseInt(document.getElementById("mPort").value.trim() || "11111");
  if (!host) return;
  await connectTo(host, port);
}

async function connectTo(host, port) {
  hideDiscover();
  try {
    const r = await fetch("/api/connect", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ host, port }),
    });
    const d = await r.json();
    if (!d.ok) throw new Error(d.error || "failed");
  } catch (e) {
    alert("Connection failed: " + e.message);
  }
}
</script>
</body>
</html>"""


# ── Entry point ────────────────────────────────────────────────────────────────

def launch(port: int = 5173) -> None:
    global _safety_mgr

    import urllib.request
    import webbrowser

    cfg = _load_config()
    log_cfg = cfg.get("logging", {})
    logging.basicConfig(
        level=log_cfg.get("level", "INFO"),
        format=log_cfg.get("format", "%(asctime)s [%(levelname)s] %(name)s: %(message)s"),
    )

    _safety_mgr = SafetyManager(config=cfg, on_unsafe=_on_safety_unsafe)
    _safety_mgr.start()

    flask_thread = threading.Thread(
        target=lambda: app.run(
            host="0.0.0.0", port=port, debug=False,
            threaded=True, use_reloader=False,
        ),
        daemon=True,
        name="flask",
    )
    flask_thread.start()

    url = f"http://localhost:{port}"
    for _ in range(20):
        try:
            urllib.request.urlopen(url, timeout=0.5)
            break
        except Exception:
            time.sleep(0.25)

    print(f"\n  NODE v1  →  {url}\n", file=sys.__stdout__)
    webbrowser.open(url)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n  Shutting down.", file=sys.__stdout__)
    finally:
        if _safety_mgr is not None:
            _safety_mgr.stop()


if __name__ == "__main__":
    launch()
