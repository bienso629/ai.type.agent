#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations


# === BEGIN: STT safe helpers ===
def _stt_sanitize(device, compute):
    d = (device or "cpu")
    try:
        d = d.lower()
    except Exception:
        d = "cpu"
    c = (compute or "")
    try:
        c = c.lower()
    except Exception:
        c = ""
    return d, c
# === END: STT safe helpers ===
"""
Unified FastAPI: Opera Profiles API + TikTok Live Caption API
Single file: app.py

- Keeps Opera features: routers include, lifespan (system tray), /, /health, /meta/routes, /v1/opera/session/keepalive
- Adds TikTok endpoints: live-list, live-watch (start/status/list/rooms/stop/stop-all), direct-start/stop/jobs,
  direct-stream (SSE + WebSocket) and helper utilities.
- Removed: Auto-launching ngrok or cloudflared tunnels.

Run:
  python app.py
  uvicorn app:app --host 0.0.0.0 --port 8000

Notes:
- Optional routers (profiles_router, accounts_router, etc.) will be included if files are present in the same folder.
- Set APP_TOKEN=<token> to require X-Api-Key for TikTok endpoints.

Test quick health:
  curl http://127.0.0.1:8000/health
"""

import os
import sys
import io
import logging
import subprocess
import threading
import time
import socket
import shutil
import webbrowser
import contextlib
import json
import base64
import random
import re
import shlex
import uuid
import asyncio
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from subprocess import PIPE
from typing import Any, Dict, List, Optional, Set, Tuple, Union
from urllib.parse import urlparse, parse_qs

from fastapi import FastAPI, Request, HTTPException, Depends, Header, Query, Body, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.responses import StreamingResponse

# =============================================================================
# App metadata
# =============================================================================
APP_NAME = "Opera + TikTok API"
APP_VERSION = "5.0.0-lite"
BASE_DIR = Path(__file__).resolve().parent

# =============================================================================
# Logging (file + console if TTY)
# =============================================================================

def _has_tty() -> bool:
    try:
        return bool(sys.stderr and hasattr(sys.stderr, "isatty") and sys.stderr.isatty())
    except Exception:
        return False

def _setup_logging() -> logging.Logger:
    level_name = os.environ.get("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)

    handlers: List[logging.Handler] = []
    log_path = Path.cwd() / "app.log"
    try:
        fh = logging.FileHandler(log_path, encoding="utf-8")
        handlers.append(fh)
    except Exception:
        handlers.append(logging.StreamHandler(open(os.devnull, "w")))

    if _has_tty():
        handlers.append(logging.StreamHandler())

    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=handlers,
    )
    log = logging.getLogger("unified_app")
    log.info("Logging initialized. Level=%s, TTY=%s, file=%s", level_name, _has_tty(), log_path)
    return log

log = _setup_logging()

# =============================================================================
# Helpers for locating binaries / bundled paths (PyInstaller)
# =============================================================================

def _which_or_bundle(path: str) -> str:
    p = Path(path)
    if p.exists():
        return str(p)
    b = Path(getattr(sys, "_MEIPASS", "")) / p.name
    if b.exists():
        return str(b)
    w = shutil.which(p.name)
    return w or str(path)

def _bundle_path(rel: str) -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path.cwd()))
    p1 = Path(rel)
    if p1.exists():
        return p1
    p2 = base / Path(rel)
    if p2.exists():
        return p2
    p3 = base / Path(rel).name
    return p3 if p3.exists() else p1

# =============================================================================
# FastAPI app (single instance)
# =============================================================================

app = FastAPI(
    title=APP_NAME,
    version=APP_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS (one place)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("CORS_ALLOW_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ensure current folder in sys.path to import optional routers
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

# =============================================================================
# Include routers (optional ones if present)
# =============================================================================

def include_routers(app_: FastAPI) -> None:
    # Required routers (if available): profiles_router, accounts_router
    for modname in ("profiles_router", "accounts_router"):
        try:
            mod = __import__(modname, fromlist=["router"])
            router = getattr(mod, "router", None)
            if router is None:
                log.warning("[router] '%s' has no 'router' attribute.", modname)
                continue
            app_.include_router(router)
            log.info("[router] Included %s", modname)
        except ModuleNotFoundError:
            log.warning("[router] Missing required-like router '%s' (continuing).", modname)
        except Exception as e:
            log.exception("[router] Failed to include '%s': %s", modname, e)
            raise

    # Optional routers
    for modname in ("search_click_router", "like_click_router", "captcha_auto_router", "comment_click_router", "opera_ai_router"):
        try:
            mod = __import__(modname, fromlist=["router"])
            router = getattr(mod, "router", None)
            if router is None:
                log.warning("[router] '%s' has no 'router' attribute.", modname)
                continue
            app_.include_router(router)
            log.info("[router] Included optional %s", modname)
        except ModuleNotFoundError:
            log.warning("[router] Optional router '%s' not found. Skipped.", modname)
        except Exception as e:
            log.warning("[router] Error including optional '%s': %s", modname, e)


# =============================================================================
# pychrome recv loop patch (swallow JSONDecodeError in background threads)
# =============================================================================
def _patch_pychrome_recv_loop() -> None:
    try:
        import pychrome, json  # type: ignore
        Tab = pychrome.tab.Tab  # type: ignore[attr-defined]
        if getattr(Tab, "_mxh_patched", False):
            return
        _orig = Tab._recv_loop

        def _safe_recv_loop(self, *a, **kw):
            try:
                _orig(self, *a, **kw)
            except json.JSONDecodeError:
                # socket may return empty/invalid frame when DevTools closes -> ignore
                log.debug("[pychrome] swallow JSONDecodeError in _recv_loop")
            except Exception as e:
                log.debug("[pychrome] _recv_loop ended: %s", e)

        Tab._recv_loop = _safe_recv_loop
        Tab._mxh_patched = True
        log.info("[pychrome] patched _recv_loop")
    except Exception as e:
        log.warning("[pychrome] patch failed: %s", e)

# =============================================================================
# System tray helpers (pystray/pillow, best-effort)
# =============================================================================
try:
    import pystray
    from PIL import Image, ImageDraw
except Exception:
    pystray = None

def _load_tray_image() -> "Image.Image":
    for cand in ("assets/100tiktok.ico", "assets/operaapi.ico", "assets/tray.png", "tray.png"):
        p = _bundle_path(cand)
        try:
            if p.exists():
                from PIL import Image  # ensure import
                return Image.open(p)  # pystray will scale
        except Exception as e:
            log.debug("[tray] load %s error: %s", p, e)
    from PIL import Image  # type: ignore
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((8, 8, 120, 120), fill=(0, 122, 255, 255))
    d.ellipse((28, 28, 100, 100), fill=(255, 255, 255, 255))
    return img

def _open_local(app_: FastAPI, path: str = "") -> None:
    # Use the port from server if possible, or fallback
    # In this logic we try to grab port from app.state if we saved it in main
    port = 8000
    if hasattr(app_.state, "port"):
        port = app_.state.port
    webbrowser.open(f"http://127.0.0.1:{port}{path}")

def _tray_quit(app_: FastAPI, icon: Optional["pystray.Icon"] = None) -> None:
    srv = getattr(app_.state, "server", None)
    if srv:
        try:
            srv.should_exit = True
        except Exception:
            pass
    if icon:
        try:
            icon.stop()
        except Exception:
            pass

def _start_tray(app_: FastAPI) -> None:
    if pystray is None:
        log.info("[tray] pystray/pillow not installed -> skip system tray")
        return
    try:
        img = _load_tray_image()
        menu = pystray.Menu(
            pystray.MenuItem("Open API root", lambda i: _open_local(app_, "/")),
            pystray.MenuItem("Open Swagger /docs", lambda i: _open_local(app_, "/docs")),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit", lambda i: _tray_quit(app_, app_.state.tray_icon)),
        )
        icon = pystray.Icon("UnifiedAPI", img, "Opera+TikTok API", menu)
        app_.state.tray_icon = icon
        if hasattr(icon, "run_detached"):
            icon.run_detached()
        else:
            threading.Thread(target=icon.run, daemon=True).start()
        log.info("[tray] started")
    except Exception as e:
        log.warning("[tray] fail: %s", e)

def _stop_tray(app_: FastAPI) -> None:
    icon = getattr(app_.state, "tray_icon", None)
    if not icon:
        return
    try:
        icon.stop()
    except Exception:
        pass
    finally:
        app_.state.tray_icon = None

# =============================================================================
# Lifespan
# =============================================================================
from contextlib import asynccontextmanager

@asynccontextmanager
async def app_lifespan(app_: FastAPI):
    # STARTUP
    try:
        start_cfg = getattr(app_.state, "start_cfg", {}) or {}
        if start_cfg.get("tray", False):
            _start_tray(app_)
    except Exception as e:
        log.warning("[lifespan] tray start error: %s", e)

    yield

    # SHUTDOWN
    try:
        _stop_tray(app_)
    except Exception as e:
        log.debug("[lifespan] tray stop error: %s", e)

# attach lifespan
app.router.lifespan_context = app_lifespan

# =============================================================================
# Opera utility endpoints
# =============================================================================

def _list_router_prefixes() -> List[str]:
    prefixes = set()
    for r in app.routes:
        p = getattr(r, "path", None) or getattr(r, "path_format", None)
        if not p:
            continue
        parts = str(p).strip("/").split("/")
        if len(parts) >= 3:
            prefixes.add("/" + "/".join(parts[:3]))
        elif len(parts) >= 2:
            prefixes.add("/" + "/".join(parts[:2]))
        else:
            prefixes.add("/" + "/".join(parts))
    return sorted(prefixes)

@app.get("/")
def root() -> Dict[str, Any]:
    return {
        "name": APP_NAME,
        "version": APP_VERSION,
        "message": "OK",
        "routers": [p for p in _list_router_prefixes()],
    }

@app.get("/health")
def health() -> Dict[str, Any]:
    return {"status": "healthy", "version": APP_VERSION}

@app.get("/meta/routes")
def meta_routes() -> Dict[str, Any]:
    items = []
    for r in app.routes:
        try:
            methods = sorted(list(getattr(r, "methods", [])))
            path = getattr(r, "path", None) or getattr(r, "path_format", None)
            name = getattr(r, "name", None)
            items.append({"methods": methods, "path": str(path), "name": name})
        except Exception:
            pass
    items = sorted(items, key=lambda x: (",".join(x.get("methods", [])), x.get("path", "")))
    return {"count": len(items), "items": items}

@app.get("/v1/opera/session/keepalive")
def session_keepalive() -> Dict[str, Any]:
    return {"ok": True, "ts": time.time(), "version": APP_VERSION}

# include optional routers (if files exist)
include_routers(app)

# =============================================================================
# TikTok Live Caption API (merged)
# =============================================================================

APP_TOKEN = os.environ.get("APP_TOKEN")  # require X-Api-Key when set
IS_WIN = os.name == "nt"

DEFAULT_FEEDS_ROOT = (Path(os.path.expanduser("~")) / "Downloads" / "AI.TYPING" / "livestream").resolve()
JOBS_DIR = (DEFAULT_FEEDS_ROOT / "jobs").resolve()
LOGS_DIR = (DEFAULT_FEEDS_ROOT / "logs").resolve()
DOWNLOADS_DIR = (DEFAULT_FEEDS_ROOT / "downloads").resolve()
for d in (DEFAULT_FEEDS_ROOT, JOBS_DIR, LOGS_DIR, DOWNLOADS_DIR):
    d.mkdir(parents=True, exist_ok=True)

LAUNCH_LOCK = threading.Lock()

# Prefer local ffmpeg executable if present (same folder as this file)
LOCAL_FFMPEG = BASE_DIR / ("ffmpeg.exe" if IS_WIN else "ffmpeg")
FFMPEG_DEFAULT = str(LOCAL_FFMPEG) if LOCAL_FFMPEG.exists() else "ffmpeg"

# FFmpeg headers (TikTok requires proper UA/Referer)
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
      "AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/122.0.0.0 Safari/537.36")
FF_HEADERS = [
    "-user_agent", UA,
    "-referer", "https://www.tiktok.com/",
    "-headers", "Accept-Language: vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7\r\nOrigin: https://www.tiktok.com",
]

# Track direct-start/stream jobs → list of ffmpeg processes per job
DIRECT_JOBS: Dict[str, Dict[str, Any]] = {}

# ---- Auth helpers ----
def require_key(x_api_key: Optional[str] = Header(default=None)) -> bool:
    if APP_TOKEN and x_api_key != APP_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing X-Api-Key")
    return True

def require_key_ws(token: Optional[str]) -> None:
    if APP_TOKEN and token != APP_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing api_key (query)")

def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")

def ensure_dir(p: Path) -> Path:
    p.mkdir(parents=True, exist_ok=True)
    return p

def _rand_hex(n: int = 16) -> str:
    import string as _s
    return ''.join(random.choice(_s.hexdigits.lower()) for _ in range(n))

def _write_srt(srt_path: Path, segments: List[Tuple[float, float, str]]):
    def _fmt(sec: float) -> str:
        ms = int((sec - int(sec)) * 1000)
        s = int(sec) % 60
        m = (int(sec) // 60) % 60
        h = int(sec) // 3600
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
    ensure_dir(srt_path.parent)
    with srt_path.open("w", encoding="utf-8") as f:
        for i, (st, ed, tx) in enumerate(segments, 1):
            f.write(f"{i}\n{_fmt(st)} --> {_fmt(ed)}\n{tx}\n\n")

def _run(cmd: List[str]) -> subprocess.Popen:
    print("[RUN]", " ".join(shlex.quote(x) for x in cmd), flush=True)
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

# ---- WAV helpers ----
def _is_valid_wav(path: Path) -> bool:
    try:
        import wave
        with wave.open(str(path), "rb") as w:
            return (
                w.getnchannels() == 1 and
                w.getframerate() == 16000 and
                w.getsampwidth() in (2,) and
                w.getnframes() > 0
            )
    except Exception:
        return False

def _wav_ready(path: Path, max_wait_s: float = 10.0) -> bool:
    import time as _t, wave
    deadline = _t.time() + max_wait_s
    last = -1
    while _t.time() < deadline:
        if not path.exists():
            _t.sleep(0.15); continue
        sz = path.stat().st_size
        if sz > 46 and sz == last:
            try:
                with wave.open(str(path), "rb") as w:
                    if (w.getnchannels() == 1 and w.getframerate() == 16000 and w.getsampwidth() in (2,)):
                        return True
            except Exception:
                pass
        last = sz
        _t.sleep(0.25)
    return False

def _wav_rms_db(path: Path) -> float:
    try:
        import wave, audioop, math
        with wave.open(str(path), "rb") as w:
            frames = w.getnframes()
            if frames <= 0:
                return -120.0
            data = w.readframes(frames)
            if not data:
                return -120.0
            rms = audioop.rms(data, w.getsampwidth())
            if rms <= 0:
                return -120.0
            db = 20.0 * math.log10(min(rms / 32768.0, 1.0))
            return float(db)
    except Exception:
        return -120.0

# ---- FFmpeg segmenter ----
def _ffmpeg_segment_wav(
    input_url: str,
    out_dir: Path,
    segment_sec: int,
    ffmpeg: str = FFMPEG_DEFAULT,
    headers: Optional[List[str]] = None,
) -> Tuple[List[Path], Optional[subprocess.Popen]]:
    ensure_dir(out_dir)
    out_tpl = str(out_dir / "chunk-%09d.wav")
    hdrs = headers if headers is not None else FF_HEADERS
    cmd = [
        ffmpeg, *hdrs,
        "-hide_banner", "-loglevel", "error",
        "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5",
        "-rw_timeout", "15000000",
        "-i", input_url,
        "-vn", "-sn", "-dn",
        "-ac", "1", "-ar", "16000",
        "-c:a", "pcm_s16le",
        "-f", "segment", "-segment_time", str(segment_sec),
        "-segment_format", "wav",
        "-reset_timestamps", "1",
        out_tpl,
    ]
    p = _run(cmd)
    first = out_dir / "chunk-000000000.wav"
    _ = _wav_ready(first, max_wait_s=max(8.0, segment_sec + 2))
    chunks = sorted(out_dir.glob("*.wav"))
    return chunks, p

# ---- Faster-Whisper ----

def _load_whisper(model: str, device: str, compute: str):
    """Ưu tiên faster-whisper (CTranslate2). Nếu lỗi -> fallback openai-whisper (PyTorch)."""
    d, c = _stt_sanitize(device, compute)
    try:
        from faster_whisper import WhisperModel
        dev = d if d in ("cpu", "cuda") else ("cuda" if os.environ.get("CUDA_VISIBLE_DEVICES") else "cpu")
        valid = {"float16","float32","int8","int8_float16","int8_float32","int16"}
        ctype = c if c in valid else ("float16" if dev == "cuda" else "int8")
        print(f"[STT] faster-whisper -> model={model} device={dev} compute_type={ctype}", flush=True)
        return WhisperModel(model, device=dev, compute_type=ctype)
    except Exception as e:
        print(f"[STT] faster-whisper unavailable, fallback to openai-whisper: {e}", flush=True)
        import whisper as whisper_pt
        print(f"[STT] openai-whisper -> model={model} device=cpu", flush=True)
        return whisper_pt.load_model(model, device="cpu")

def _transcribe_chunk(model_obj, wav_path: Path, lang: str, task: str) -> List[Tuple[float, float, str]]:
    if not _is_valid_wav(wav_path):
        return []
    language = None if (lang is None or str(lang).lower() in ("", "auto")) else lang

    def run(vad: bool) -> List[Tuple[float, float, str]]:
        segs, _info = model_obj.transcribe(
            str(wav_path), language=language, task=task,
            vad_filter=vad, vad_parameters=dict(min_silence_duration_ms=200),
            temperature=0.0, beam_size=5, best_of=5,
        )
        out: List[Tuple[float, float, str]] = []
        for s in segs:
            txt = (s.text or "").strip()
            if txt:
                out.append((s.start, s.end, txt))
        return out

    out = run(True)
    if out:
        return out
    try:
        return run(False)
    except Exception:
        return []

def _transcribe_faster_whisper(
    chunks: List[Path], lang: str, task: str, model: str, device: str, compute: str
) -> List[Tuple[float, float, str]]:
    try:
        model_obj = _load_whisper(model, device, compute)
    except Exception as e:
        print("[ERR] faster-whisper load failed:", e, flush=True)
        return []
    results: List[Tuple[float, float, str]] = []
    for wav in sorted(chunks):
        p = Path(wav)
        if not _is_valid_wav(p):
            print(f"[SKIP] invalid/unfinished wav: {p.name}", flush=True)
            continue
        print(f"[TRANSCRIBE] {p.name}", flush=True)
        try:
            results.extend(_transcribe_chunk(model_obj, p, lang, task))
        except Exception as e:
            print(f"[ERR] transcribe failed for {p.name}: {e}", flush=True)
    return results

# ---- DevTools / Opera control ----
def devtools_up(port: int, timeout: float = 0.25) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except Exception:
        return False

def find_opera_path(cli_path: Optional[str]) -> str:
    if cli_path and Path(cli_path).exists():
        return cli_path
    env = os.environ.get("OPERA_PATH")
    if env and Path(env).exists():
        return env
    if IS_WIN:
        candidates = [
            Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Opera" / "opera.exe",
            Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Opera GX" / "opera.exe",
            Path("C:/Program Files/Opera/opera.exe"),
            Path("C:/Program Files (x86)/Opera/opera.exe"),
        ]
    else:
        candidates = [
            Path("/usr/bin/opera"),
            Path("/usr/bin/opera-stable"),
            Path("/Applications/Opera.app/Contents/MacOS/Opera"),
        ]
    for c in candidates:
        if c and c.exists():
            return str(c)
    return str(candidates[-1])

def ensure_opera(profile: Optional[str], port: int, opera_path: Optional[str], launch_if_needed: bool) -> None:
    if devtools_up(port):
        return
    if not launch_if_needed:
        raise HTTPException(
            status_code=412,
            detail=(
                f"DevTools port {port} is not running. Start Opera with: "
                f'Opera.exe --user-data-dir="{profile or "<profile>"}" --remote-debugging-port={port}'
            ),
        )
    if not profile:
        raise HTTPException(status_code=400, detail="profile is required to launch Opera")

    with LAUNCH_LOCK:
        if devtools_up(port):
            return
        exe = find_opera_path(opera_path)
        if (not exe) or (not Path(exe).exists()):
            raise HTTPException(status_code=400, detail="opera_path not found; provide valid opera.exe")

        args = [
            exe,
            f"--user-data-dir={profile}",
            f"--remote-debugging-port={port}",
            "--remote-allow-origins=*",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--disable-features=Translate,PrivacySandboxSettings4",
            "--autoplay-policy=no-user-gesture-required",
            "--start-maximized",
            "--disable-notifications",
        ]
        creationflags = 0
        preexec_fn = None
        if IS_WIN:
            creationflags = getattr(__import__("subprocess"), "CREATE_NEW_PROCESS_GROUP", 0)
        else:
            import os as _os
            preexec_fn = _os.setsid

        subprocess.Popen(args, stdout=PIPE, stderr=PIPE, creationflags=creationflags, preexec_fn=preexec_fn)

        for _ in range(120):
            if devtools_up(port):
                return
            time.sleep(0.1)
        raise HTTPException(status_code=500, detail=f"DevTools port {port} not available after launch")

# ---- Kill Opera by profile/port ----
def kill_opera(profile: Optional[str], port: Optional[int]) -> Dict[str, Any]:
    profile = (profile or "").strip()
    port = int(port or 0) or None
    result: Dict[str, Any] = {"platform": ("win" if IS_WIN else "nix"), "pids": [], "ok": True, "errors": []}
    try:
        if IS_WIN:
            pat_port = f"--remote-debugging-port={port}" if port else None
            pat_prof = f"--user-data-dir={profile}" if profile else None
            conds = []
            if pat_port:
                conds.append(f"$_.CommandLine -like '*{pat_port.replace('\"', '`\"')}*'")
            if pat_prof:
                conds.append(f"$_.CommandLine -like '*{pat_prof.replace('\"', '`\"')}*'")
            if not conds:
                conds = ["$true"]
            where = " -and (" + " -or ".join(conds) + ")" if conds else ""
            ps = (
                "$p=Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'opera*.exe'" + where +
                " }; $ids=@(); foreach($x in $p){$ids+=$x.ProcessId}; "
                "foreach($i in $ids){ try{ Stop-Process -Id $i -Force -ErrorAction SilentlyContinue }catch{} }; "
                "[string]::Join(',', $ids)"
            )
            completed = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            out = (completed.stdout or "").strip()
            pids = [int(x) for x in out.split(",") if x.strip().isdigit()] if out else []
            result["pids"] = pids
            if completed.returncode != 0:
                result["ok"] = False
                result["errors"].append(completed.stderr)
        else:
            patterns = []
            if port:
                patterns.append(f"--remote-debugging-port={port}")
            if profile:
                patterns.append(profile)
            collected: Set[int] = set()
            for pat in (patterns or ["opera"]):
                try:
                    r = subprocess.run(["pgrep", "-f", pat], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                    for line in (r.stdout or "").splitlines():
                        if line.strip().isdigit():
                            collected.add(int(line.strip()))
                except Exception:
                    pass
                try:
                    subprocess.run(["pkill", "-9", "-f", pat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    pass
            try:
                subprocess.run(["pkill", "-9", "opera"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
            result["pids"] = sorted(collected)
    except Exception as e:
        result["ok"] = False
        result["errors"].append(str(e))
    return result

# ---- Scanner / Watcher ----
class ScanParams(BaseModel):
    profile: str = Field(..., description="Opera --user-data-dir path")
    opera_path: Optional[str] = None
    port: int = 9222
    live_url: str = "https://www.tiktok.com/live"
    timeout: int = 12
    max_items: int = 50
    feeds_dir: Optional[str] = None
    targets: Optional[Union[List[str], str]] = None
    idle_sec: int = Field(default=8, ge=1)
    max_duration: Optional[int] = Field(default=None, ge=1)
    launch_if_needed: bool = Field(default=False, description="Launch Opera if DevTools port is not up")

def feeds_root(custom: Optional[str]) -> Path:
    if custom:
        return ensure_dir(Path(custom))
    env = os.environ.get("LIVE_FEEDS_DIR")
    return ensure_dir(Path(env).resolve()) if env else ensure_dir(DEFAULT_FEEDS_ROOT)

def feeds_scanner_dir(custom: Optional[str]) -> Path:
    return ensure_dir(feeds_root(custom) / "scanner")

def _safe_get_response_body_text(tab: Any, requestId: str, tries: int = 4, delay: float = 0.07) -> str:
    import pychrome
    _patch_pychrome_recv_loop()
    for _ in range(max(1, tries)):
        try:
            body = tab.call_method("Network.getResponseBody", requestId=requestId)
            text: Any = body.get("body", "")
            if body.get("base64Encoded"):
                try:
                    text = base64.b64decode(text).decode("utf-8", "ignore")
                except Exception:
                    text = ""
            return text if isinstance(text, str) else ""
        except Exception:
            time.sleep(delay)
    return ""

def normalize_targets(raw: Optional[Union[List[str], str]]) -> Set[str]:
    s: Set[str] = set()
    if not raw:
        return s
    items: List[str]
    if isinstance(raw, str):
        items = [x.strip() for x in raw.split(",") if x.strip()]
    else:
        items = [str(x).strip() for x in raw if str(x).strip()]
    for t in items:
        s.add(t.lower())
    return s

def flatten_items(js: Union[Dict[str, Any], List[Any]]) -> List[Dict[str, Any]]:
    arr: List[Dict[str, Any]] = []
    def walk(x: Any) -> None:
        if isinstance(x, dict):
            if "data" in x or "owner" in x or "author" in x:
                arr.append(x)
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(js)
    return arr

def collect_full_info(item: Dict[str, Any]) -> Dict[str, Any]:
    data: Dict[str, Any] = item.get("data") if isinstance(item, dict) else {}
    if not isinstance(data, dict) or not data:
        data = item if isinstance(item, dict) else {}
    owner: Dict[str, Any] = data.get("owner") or data.get("author") or data.get("user") or {}
    nickname = owner.get("nickname")
    unique_id = owner.get("display_id") or owner.get("unique_id")
    room_id = data.get("room_id") or data.get("id")
    stats = data.get("stats") or {}
    hashtag = data.get("hashtag") or {}
    cover = data.get("cover") or {}
    stream_url = data.get("stream_url")
    title = data.get("title") or data.get("room_title")
    return {
        "id": str(room_id) if room_id is not None else None,
        "status": data.get("status"),
        "title": title,
        "user_count": data.get("user_count") or data.get("userCount"),
        "stream_size_width": data.get("stream_size_width") or data.get("width"),
        "stream_size_height": data.get("stream_size_height") or data.get("height"),
        "like_count": data.get("like_count") or stats.get("like_count"),
        "anchor_tab_type": data.get("anchor_tab_type"),
        "live_room_mode": data.get("live_room_mode"),
        "stats": stats,
        "hashtag": hashtag,
        "cover": cover,
        "stream_url": stream_url,
        "owner": owner,
        "unique_id": unique_id,
        "nickname": nickname,
    }

def item_matches_targets(item: Dict[str, Any], targets: Set[str]) -> bool:
    if not targets:
        return True
    data = item.get("data") or item
    if not isinstance(data, dict):
        return False
    owner = data.get("owner") or data.get("author") or data.get("user") or {}
    uid = str(owner.get("display_id") or owner.get("unique_id") or "").lower()
    nn = str(owner.get("nickname") or "").lower()
    return bool({uid, nn} & targets)

def _pick_best_tab(browser: Any, preferred_hosts: tuple = ("tiktok.com",)) -> Any:
    try:
        tabs = browser.list_tab()
        if not tabs:
            t = browser.new_tab()
            with contextlib.suppress(Exception):
                t.start()
            return t
        def _score(tab: Any) -> int:
            kw = getattr(tab, "_kwargs", {})
            url = str(kw.get("url") or "").lower()
            typ = kw.get("type") or ""
            sc = 0
            if typ == "page":
                sc += 5
            if url.startswith("http"):
                sc += 10
            if any(h in url for h in preferred_hosts):
                sc += 100
            if (not url) or (url == "about:blank") or url.startswith(("opera://", "chrome://", "devtools://")):
                sc -= 20
            return sc
        tab = max(tabs, key=_score)
        with contextlib.suppress(Exception):
            tab.start()
            tab.call_method("Page.bringToFront")
        return tab
    except Exception:
        t = browser.new_tab()
        with contextlib.suppress(Exception):
            t.start()
        return t

def _navigate_or_open(browser: Any, url: str) -> Any:
    tab = _pick_best_tab(browser)
    def _page_title_ok(t: Any) -> bool:
        try:
            r = t.call_method("Runtime.evaluate", expression="document.title", returnByValue=True)
            title = (r.get("result") or {}).get("value") or ""
            return isinstance(title, str) and len(title) > 0 and title.lower() != "about:blank"
        except Exception:
            return False
    def _url_contains_target(t: Any) -> bool:
        try:
            r = t.call_method("Runtime.evaluate", expression="location.href", returnByValue=True)
            href = (r.get("result") or {}).get("value") or ""
            return isinstance(href, str) and "tiktok.com" in href
        except Exception:
            return False
    for attempt in range(3):
        with contextlib.suppress(Exception):
            if attempt == 0:
                tab.call_method("Page.navigate", url=url)
            elif attempt == 1:
                tab.call_method("Runtime.evaluate", expression=f"location.href='{url}'")
            else:
                tab.call_method("Runtime.evaluate", expression=f"window.open('{url}','_self');")
        t_dead = time.time() + 6
        while time.time() < t_dead:
            if _url_contains_target(tab) or _page_title_ok(tab):
                return tab
            time.sleep(0.25)
    try:
        t2 = browser.new_tab(url=url)
        with contextlib.suppress(Exception):
            t2.start()
            t2.call_method("Page.bringToFront")
        t_dead = time.time() + 8
        while time.time() < t_dead:
            if _url_contains_target(t2) or _page_title_ok(t2):
                return t2
            time.sleep(0.25)
        return t2
    except Exception:
        return tab

def _close_all_tabs_and_open(browser: Any, url: str) -> Any:
    try:
        tabs = browser.list_tab()
        for t in list(tabs):
            with contextlib.suppress(Exception):
                t.start()
                browser.close_tab(t)
        tnew = browser.new_tab(url=url)
        with contextlib.suppress(Exception):
            tnew.start()
            tnew.call_method("Page.bringToFront")
        return tnew
    except Exception:
        return _navigate_or_open(browser, url)

def scan_once(p: "ScanParams") -> Dict[str, Any]:
    feeds_root_dir = feeds_root(p.feeds_dir)
    scanner_dir = feeds_scanner_dir(p.feeds_dir)
    targets = normalize_targets(p.targets)

    ensure_opera(profile=p.profile, port=p.port, opera_path=p.opera_path, launch_if_needed=p.launch_if_needed)

    import pychrome  # runtime import
    _patch_pychrome_recv_loop()
    browser = pychrome.Browser(url=f"http://127.0.0.1:{p.port}")
    tab = _pick_best_tab(browser)

    collected: List[Dict[str, Any]] = []
    files_saved: List[str] = []
    request_ids: Set[str] = set()
    seen_ids: Set[str] = set()
    t0 = time.time()
    last_new = t0

    def on_response_received(requestId: Optional[str] = None, response: Optional[Dict[str, Any]] = None, **kwargs: Any) -> None:
        try:
            if not response:
                return
            url = response.get("url", "") or ""
            if "webcast" in url or url.endswith(".json"):
                if requestId:
                    request_ids.add(requestId)
        except Exception:
            pass

    def on_loading_finished(requestId: Optional[str] = None, **kwargs: Any) -> None:
        nonlocal last_new
        if (requestId is None) or (requestId not in request_ids):
            return
        try:
            text = _safe_get_response_body_text(tab, requestId, tries=5, delay=0.06)
            if (not isinstance(text, str)) or (not text.strip()):
                return

            ts = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            fpath = scanner_dir / f"scanner-{ts}.json"
            with contextlib.suppress(Exception):
                fpath.write_text(text, encoding="utf-8", errors="ignore")
                files_saved.append(str(fpath))

            try:
                js = json.loads(text)
            except Exception:
                return

            new_flag = False
            for it in flatten_items(js):
                if not isinstance(it, dict):
                    continue
                if not item_matches_targets(it, targets):
                    continue
                info = collect_full_info(it)
                rid = str(info.get("id") or "")
                if (not rid) or (rid in seen_ids):
                    continue
                collected.append(info)
                seen_ids.add(rid)
                new_flag = True
            if new_flag:
                last_new = time.time()
        except Exception:
            pass
        finally:
            with contextlib.suppress(KeyError):
                request_ids.discard(requestId)  # type: ignore[arg-type]

    try:
        tab.call_method("Network.enable")
        tab.call_method("Page.enable")
        tab.call_method("Network.clearBrowserCache")

        with contextlib.suppress(Exception):
            tab.call_method(
                "Network.setUserAgentOverride",
                userAgent=UA,
                acceptLanguage="vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
            )

        with contextlib.suppress(Exception):
            tab.call_method("Page.bringToFront")

        tab.set_listener("Network.responseReceived", on_response_received)
        tab.set_listener("Network.loadingFinished", on_loading_finished)

        target = (p.live_url or "").strip() or "https://www.tiktok.com/live"
        tab = _navigate_or_open(browser, target)

        with contextlib.suppress(Exception):
            tab.call_method("Runtime.evaluate", expression="window.scrollTo(0, 800)")

        deadline = None if (p.timeout is None or p.timeout <= 0) else (time.time() + max(1, p.timeout))
        while True:
            if len(collected) >= p.max_items:
                break
            if (deadline is not None) and (time.time() > deadline):
                break
            if deadline is None:
                if (p.max_duration is not None) and ((time.time() - t0) >= max(1, p.max_duration)):
                    break
                if p.idle_sec and ((time.time() - last_new) >= max(1, p.idle_sec)):
                    break
            time.sleep(0.2)
    finally:
        tab.set_listener("Network.responseReceived", None)
        tab.set_listener("Network.loadingFinished", None)

        def _stop_tab_async(t):
            with contextlib.suppress(Exception):
                t.stop()

        with contextlib.suppress(Exception):
            threading.Thread(target=_stop_tab_async, args=(tab,), daemon=True).start()

    return {
        "rooms": collected[: p.max_items],
        "sample_feed_files": files_saved,
        "count": len(collected),
        "feeds_dir": str(feeds_root_dir),
        "scanner_dir": str(feeds_scanner_dir(p.feeds_dir)),
        "targets": sorted(list(targets)),
        "scanned_at": now_iso(),
    }

class WatchParams(ScanParams):
    interval_sec: int = Field(default=10, ge=2, le=600)

@dataclass
class Watcher:
    id: str
    params: WatchParams
    feeds_dir: Path
    status: str = "starting"
    created_at: float = field(default_factory=lambda: time.time())
    rooms: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    last_files: List[str] = field(default_factory=list)
    _thread: Optional[threading.Thread] = None
    _stop: threading.Event = field(default_factory=threading.Event)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "created_at": datetime.fromtimestamp(self.created_at).isoformat(timespec="seconds"),
            "status": self.status,
            "rooms_count": len(self.rooms),
            "feeds_dir": str(self.feeds_dir),
            "scanner_dir": str(self.feeds_dir / "scanner"),
            "interval_sec": self.params.interval_sec,
            "port": self.params.port,
            "live_url": self.params.live_url,
            "targets": sorted(list(normalize_targets(self.params.targets))),
            "timeout": self.params.timeout,
            "idle_sec": self.params.idle_sec,
            "max_duration": self.params.max_duration,
            "launch_if_needed": self.params.launch_if_needed,
        }

WATCHERS: Dict[str, Watcher] = {}

def watcher_loop(w: Watcher) -> None:
    try:
        ensure_opera(
            profile=w.params.profile,
            port=w.params.port,
            opera_path=w.params.opera_path,
            launch_if_needed=w.params.launch_if_needed,
        )
        import pychrome
        _patch_pychrome_recv_loop()
        browser = pychrome.Browser(url=f"http://127.0.0.1:{w.params.port}")
        _close_all_tabs_and_open(browser, (w.params.live_url or "https://www.tiktok.com/live").strip())

        w.status = "running"
        while not w._stop.is_set():
            try:
                res = scan_once(w.params)
                for info in res.get("rooms", []):
                    rid = str(info.get("id") or "")
                    if rid:
                        w.rooms[rid] = info
                w.last_files = (w.last_files + res.get("sample_feed_files", []))[-50:]
            except Exception:
                pass
            for _ in range(int(max(1, w.params.interval_sec) / 0.2)):
                if w._stop.is_set():
                    break
                time.sleep(0.2)
        w.status = "stopped"
    except HTTPException:
        w.status = "error"
    except Exception:
        w.status = "error"

# ---- Routes: live-list/watch ----
PREFIX = "/v1/tiktok/captions"

@app.post(f"{PREFIX}/live-list", dependencies=[Depends(require_key)])
def api_live_list(params: ScanParams):
    try:
        return scan_once(params)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"scan error: {e}")

@app.post(f"{PREFIX}/live-watch/start", dependencies=[Depends(require_key)])
def api_watch_start(params: WatchParams):
    w_id = _rand_hex(10).upper()
    root = feeds_root(params.feeds_dir)
    ensure_dir(root)
    ensure_dir(root / "scanner")
    w = Watcher(id=w_id, params=params, feeds_dir=root)
    t = threading.Thread(target=watcher_loop, args=(w,), daemon=True)
    w._thread = t
    WATCHERS[w_id] = w
    t.start()
    time.sleep(0.25)
    return {"ok": True, "watch_id": w_id, "info": w.to_dict()}

@app.get(f"{PREFIX}/live-watch/status/{{watch_id}}", dependencies=[Depends(require_key)])
def api_watch_status(watch_id: str):
    w = WATCHERS.get(watch_id)
    if not w:
        raise HTTPException(status_code=404, detail="Watcher not found")
    running = bool(w._thread and w._thread.is_alive())
    return {"ok": True, "info": w.to_dict(), "rooms_count": len(w.rooms), "running": running}

@app.get(f"{PREFIX}/live-watch/list", dependencies=[Depends(require_key)])
def api_watch_list():
    listing = [w.to_dict() for w in WATCHERS.values()]
    return {"count": len(listing), "results": listing}

@app.get(f"{PREFIX}/live-watch/rooms/{{watch_id}}", dependencies=[Depends(require_key)])
def api_watch_rooms(
    watch_id: str,
    targets: Optional[str] = Query(default=None, description="CSV targets to filter temporarily"),
    limit: int = Query(default=200, ge=1, le=2000),
):
    w = WATCHERS.get(watch_id)
    if not w:
        raise HTTPException(status_code=404, detail="Watcher not found")
    tset = normalize_targets(targets.split(",") if targets else None)
    rooms: List[Dict[str, Any]] = list(w.rooms.values())
    if tset:
        def ok(info: Dict[str, Any]) -> bool:
            uid = str(info.get("unique_id") or "").lower()
            nn = str(info.get("nickname") or "").lower()
            return bool({uid, nn} & tset)
        rooms = [x for x in rooms if ok(x)]
    running = bool(w._thread and w._thread.is_alive())
    return {
        "ok": True,
        "watch_id": watch_id,
        "running": running,
        "count": len(rooms[:limit]),
        "rooms": rooms[:limit],
        "last_files": w.last_files,
        "scanned_at": now_iso(),
    }

def _close_all_tabs_by_port(port: int) -> Dict[str, Any]:
    try:
        import pychrome
        _patch_pychrome_recv_loop()
        browser = pychrome.Browser(url=f"http://127.0.0.1:{int(port)}")
        tabs = browser.list_tab()
        closed = 0
        for t in list(tabs):
            with contextlib.suppress(Exception):
                t.start()
                browser.close_tab(t)
                closed += 1
        return {"ok": True, "closed": closed}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def _stop_watcher_and_close_opera(w: Watcher, hard_kill: bool = True, close_tabs_first: bool = True) -> Dict[str, Any]:
    w._stop.set()
    if w._thread and w._thread.is_alive():
        for _ in range(40):
            if not w._thread.is_alive():
                break
            time.sleep(0.2)
    killed = {"skipped": False, "result": None, "closed_tabs": None}
    try:
        if close_tabs_first:
            closed = _close_all_tabs_by_port(w.params.port)
            killed["closed_tabs"] = closed
    except Exception as e:
        killed["closed_tabs"] = {"ok": False, "error": str(e)}
    if hard_kill:
        killed["result"] = kill_opera(profile=w.params.profile, port=w.params.port)
    else:
        killed["skipped"] = True
    w.status = "stopped"
    return killed

@app.get(f"{PREFIX}/live-watch/stop/{{watch_id}}", dependencies=[Depends(require_key)])
@app.post(f"{PREFIX}/live-watch/stop/{{watch_id}}", dependencies=[Depends(require_key)])
def api_watch_stop(watch_id: str, close_opera: bool = Query(default=True)):
    w = WATCHERS.pop(watch_id, None)
    if not w:
        raise HTTPException(status_code=404, detail="Watcher not found")
    killed = _stop_watcher_and_close_opera(w, hard_kill=close_opera)
    running = bool(w._thread and w._thread.is_alive())
    return {"ok": True, "watch_id": watch_id, "running": running, "closed_opera": close_opera, "kill_info": killed}

# ---- Stop-all helpers ----
_sessions: Dict[str, Dict[str, Any]] = {}  # for direct-stream start/sse/stop

async def _stop_all_stream_sessions(timeout: float = 3.0) -> dict:
    results = {"count": 0, "details": {}}
    for sid, state in list(_sessions.items()):
        stop_evt: asyncio.Event = state["stop"]
        task = state.get("task")
        stop_evt.set()
        status = {"stopped": False, "cancelled": False, "error": None}
        try:
            if task:
                try:
                    await asyncio.wait_for(task, timeout=timeout)
                    status["stopped"] = True
                except asyncio.TimeoutError:
                    task.cancel()
                    status["cancelled"] = True
        except Exception as e:
            status["error"] = str(e)
        finally:
            _sessions.pop(sid, None)
        results["details"][sid] = status
        results["count"] += 1
    return results

def _kill_all_direct_jobs() -> dict:
    out = {"count": 0, "details": {}}
    for jid, meta in list(DIRECT_JOBS.items()):
        procs = meta.get("procs", []) or []
        res = [_kill_proc(p) for p in procs if p]
        DIRECT_JOBS.pop(jid, None)
        out["details"][jid] = {
            "stopped": sum(1 for r in res if r.get("killed")),
            "pids": [r.get("pid") for r in res],
            "results": res,
            "log": meta.get("log"),
            "dir": meta.get("dir"),
        }
        out["count"] += 1
    return out

@app.post(f"{PREFIX}/live-watch/stop-all", dependencies=[Depends(require_key)])
async def api_watch_stop_all(
    close_opera: bool = Query(default=True, description="Kill Opera after stopping watcher"),
    stop_stream_sessions: bool = Query(default=True, description="Stop all SSE/WebSocket direct-stream sessions"),
    kill_direct_jobs: bool = Query(default=True, description="Kill all ffmpeg processes of direct jobs"),
):
    watcher_results: Dict[str, Any] = {}
    ids = list(WATCHERS.keys())
    for wid in ids:
        w = WATCHERS.pop(wid, None)
        if not w:
            continue
        killed = _stop_watcher_and_close_opera(w, hard_kill=close_opera)
        watcher_results[wid] = {"closed_opera": close_opera, "kill_info": killed}

    sessions_info = {"count": 0, "details": {}}
    if stop_stream_sessions:
        sessions_info = await _stop_all_stream_sessions(timeout=3.0)

    jobs_info = {"count": 0, "details": {}}
    if kill_direct_jobs:
        jobs_info = _kill_all_direct_jobs()

    global_opera_kill = {"skipped": True}
    if close_opera:
        try:
            global_opera_kill = kill_opera(profile=None, port=None)
        except Exception as e:
            global_opera_kill = {"ok": False, "error": str(e)}

    return {
        "ok": True,
        "watchers_stopped": len(watcher_results),
        "watchers": watcher_results,
        "stream_sessions_stopped": sessions_info.get("count", 0),
        "stream_sessions": sessions_info.get("details", {}),
        "direct_jobs_stopped": jobs_info.get("count", 0),
        "direct_jobs": jobs_info.get("details", {}),
        "global_opera_kill": global_opera_kill,
        "ts": now_iso(),
    }

# ---- Direct caption (no browser) ----
class DirectPayload(BaseModel):
    stream_url: dict = Field(..., description="TikTok stream_url object; may include flv_pull_url/rtmp_pull_url/live_core_sdk_data.pull_data.stream_data")
    lang: str = "vi"
    task: str = "transcribe"  # or "translate"
    model: str = "small"
    fw_device: str = "auto"  # auto|cpu|cuda
    fw_compute: str = "auto"  # auto|float32|float16
    segment_sec: int = 10
    job_id: Optional[str] = None
    out: Optional[str] = None
    txt_out: Optional[str] = None
    download: bool = True
    download_out: Optional[str] = None
    ffmpeg: str = FFMPEG_DEFAULT

STREAM_DATA_PAT = re.compile(r'"stream_data"\s*:\s*"(.+?)"', re.S)

def _parse_stream_data_string(s: str) -> Dict[str, str]:
    try:
        stream_json = json.loads(bytes(s, "utf-8").decode("unicode_escape"))
    except Exception:
        try:
            stream_json = json.loads(s)
        except Exception:
            return {}
    urls: Dict[str, str] = {}
    data = (stream_json or {}).get("data") or {}
    for k, v in data.items():
        try:
            flv = (v or {}).get("main", {}).get("flv", "").strip()
            if flv:
                urls[k.lower()] = flv
        except Exception:
            pass
    if "origin" in urls and "only_audio=1" in urls["origin"]:
        urls["ao"] = urls["origin"]
    return urls

def _collect_urls_from_stream_url(stream_url: dict) -> Dict[str, str]:
    urls: Dict[str, str] = {}
    flv_map = (stream_url or {}).get("flv_pull_url") or {}
    for key, val in flv_map.items():
        u = (val or "").strip()
        if u:
            urls[key.lower()] = u
    origin = (stream_url or {}).get("rtmp_pull_url") or ""
    if origin:
        urls["origin"] = origin.strip()
    try:
        sdata = (((stream_url or {}).get("live_core_sdk_data") or {}).get("pull_data") or {}).get("stream_data") or ""
        if sdata:
            urls.update(_parse_stream_data_string(sdata))
    except Exception:
        pass
    return urls

def _is_valid_tiktok_url(u: str) -> bool:
    try:
        p = urlparse(u)
        if p.scheme != "https":
            return False
        host = (p.netloc or "").lower()
        return host.endswith("tiktokcdn.com")
    except Exception:
        return False

def _not_expired(u: str) -> bool:
    try:
        q = parse_qs(urlparse(u).query)
        if "expire" in q:
            exp = int((q.get("expire") or ["0"])[0])
            now = int(time.time())
            return exp > now
        return True
    except Exception:
        return True

def _pick_best_url(urls: Dict[str, str]) -> Optional[str]:
    order = ["origin", "hd1", "hd", "hd_60", "uhd_60", "sd2", "sd", "sd1", "ld", "ao"]
    filtered = {k: v for k, v in urls.items() if v and _is_valid_tiktok_url(v) and _not_expired(v)}
    for k in order:
        if k in filtered:
            return filtered[k]
    return next(iter(filtered.values()), None)

@app.post(f"{PREFIX}/direct-start", dependencies=[Depends(require_key)])
def direct_start(payload: DirectPayload = Body(...)):
    job_id = (payload.job_id or _rand_hex(16)).lower()
    dir_jobs = ensure_dir(JOBS_DIR / job_id)
    dir_logs = ensure_dir(LOGS_DIR)
    dir_dl = ensure_dir(DOWNLOADS_DIR)
    dir_chunks = ensure_dir(dir_jobs / "chunks")

    log_path = dir_logs / f"{job_id}.log"
    sys.stdout = io.TextIOWrapper(open(log_path, "ab", buffering=0), encoding="utf-8", errors="ignore")
    sys.stderr = sys.stdout
    print(f"[BOOT] direct-start job={job_id}")

    DIRECT_JOBS[job_id] = {"created": time.time(), "status": "running", "procs": [], "log": str(log_path), "dir": str(dir_jobs)}

    url_map = _collect_urls_from_stream_url(payload.stream_url)
    if not url_map:
        raise HTTPException(status_code=400, detail="No URLs found in stream_url (flv_pull_url/rtmp_pull_url/stream_data).")

    invalid = {k: v for k, v in url_map.items() if not (_is_valid_tiktok_url(v) and _not_expired(v))}
    if len(invalid) == len(url_map):
        raise HTTPException(status_code=400, detail="All candidate URLs are invalid or expired.")

    primary = _pick_best_url(url_map)
    if not primary:
        raise HTTPException(status_code=400, detail="Could not select a playable primary URL.")

    debug = {
        "job_id": job_id,
        "url_map": url_map,
        "invalid_or_expired": invalid,
        "primary_url": primary,
        "lang": payload.lang,
        "task": payload.task,
        "model": payload.model,
        "fw_device": payload.fw_device,
        "fw_compute": payload.fw_compute,
        "segment_sec": payload.segment_sec,
        "timestamp": now_iso(),
    }
    with (dir_jobs / "debug.json").open("w", encoding="utf-8") as f:
        json.dump(debug, f, ensure_ascii=False, indent=2)

    print(f"[INFO] Primary URL: {primary}")

    dl_file: Optional[Path] = None
    if payload.download:
        dl_file = Path(payload.download_out) if payload.download_out else (dir_dl / f"live_{job_id}.flv")
        ensure_dir(dl_file.parent)
        print(f"[DL] → {dl_file}")
        p_dl = _run([payload.ffmpeg, *FF_HEADERS, "-y", "-i", primary, "-c", "copy", str(dl_file)])
        DIRECT_JOBS[job_id]["procs"].append(p_dl)

    chunks, p_seg = _ffmpeg_segment_wav(primary, dir_chunks, payload.segment_sec, payload.ffmpeg, FF_HEADERS)
    if p_seg:
        DIRECT_JOBS[job_id]["procs"].append(p_seg)

    if not chunks:
        ao = url_map.get("ao")
        if ao and ao != primary:
            print("[WARN] Primary produced no audio; retry with AO …")
            chunks, p_seg2 = _ffmpeg_segment_wav(ao, dir_chunks, payload.segment_sec, payload.ffmpeg, FF_HEADERS)
            if p_seg2:
                DIRECT_JOBS[job_id]["procs"].append(p_seg2)
            primary = ao

    if not chunks:
        DIRECT_JOBS[job_id]["status"] = "error"
        raise HTTPException(status_code=500, detail="Failed to produce WAV chunks (stream may have no audio).")

    segs = _transcribe_faster_whisper(chunks, payload.lang, payload.task, payload.model, payload.fw_device, payload.fw_compute)
    if not segs:
        DIRECT_JOBS[job_id]["status"] = "error"
        raise HTTPException(status_code=500, detail="Speech-to-text produced no segments.")

    srt_path = Path(payload.out) if payload.out else (dir_jobs / f"captions_{job_id}.srt")
    txt_path = Path(payload.txt_out) if payload.txt_out else (dir_jobs / f"captions_{job_id}.txt")
    _write_srt(srt_path, segs)
    with txt_path.open("w", encoding="utf-8") as f:
        f.write("\n".join(t for _, _, t in segs))

    print(f"[OK] SRT: {srt_path}")
    print(f"[OK] TXT: {txt_path}")
    if dl_file:
        print(f"[OK] FLV (background): {dl_file}")

    return {
        "ok": True,
        "job_id": job_id,
        "primary_url": primary,
        "outputs": {
            "srt": str(srt_path),
            "txt": str(txt_path),
            "flv": (str(dl_file) if dl_file else None),
            "chunks_dir": str(dir_chunks),
            "log": str(log_path),
        },
    }

def _kill_proc(p: subprocess.Popen) -> Dict[str, Any]:
    info: Dict[str, Any] = {"pid": getattr(p, "pid", None), "killed": False}
    try:
        if p.poll() is None:
            if IS_WIN:
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                p.terminate()
                time.sleep(1)
                if p.poll() is None:
                    p.kill()
            info["killed"] = True
    except Exception as e:
        info["error"] = str(e)
    return info

@app.post(f"{PREFIX}/direct-stop/{{job_id}}", dependencies=[Depends(require_key)])
def direct_stop(job_id: str):
    job = DIRECT_JOBS.pop(job_id, None)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found or already finished")
    procs: List[subprocess.Popen] = job.get("procs", [])
    results = [_kill_proc(p) for p in procs if p]
    return {"ok": True, "job_id": job_id, "stopped": sum(1 for r in results if r.get("killed")), "results": results, "log": job.get("log"), "dir": job.get("dir")}

@app.get(f"{PREFIX}/direct-jobs", dependencies=[Depends(require_key)])
def direct_jobs():
    listing = []
    for jid, meta in DIRECT_JOBS.items():
        procs = meta.get("procs", [])
        pids = [getattr(p, "pid", None) for p in procs if p]
        alive = [(pid, (p.poll() is None)) for pid, p in zip(pids, procs)]
        listing.append({
            "job_id": jid,
            "created_at": datetime.fromtimestamp(meta.get("created", time.time())).isoformat(timespec="seconds"),
            "status": meta.get("status", "running"),
            "pids": pids,
            "alive": alive,
            "log": meta.get("log"),
            "dir": meta.get("dir"),
        })
    return {"count": len(listing), "results": listing}

# ---- Direct streaming: SSE ----
class DirectStreamPayload(DirectPayload):
    keepalive_sec: int = Field(default=7, ge=2, le=60)
    idle_stop_sec: int = Field(default=25, ge=5, le=300, description="Stop if no new chunks and ffmpeg ended")
    persist_srt: bool = False
    persist_txt: bool = False

def _sse_format(event: str, data: Dict[str, Any]) -> bytes:
    return (f"event: {event}\n" + "data: " + json.dumps(data, ensure_ascii=False) + "\n\n").encode("utf-8")

def _streaming_setup(payload: DirectStreamPayload) -> Tuple[str, Dict[str, str], str, Path, Path, Path, List[Path], subprocess.Popen]:
    job_id = (payload.job_id or _rand_hex(16)).lower()
    dir_jobs = ensure_dir(JOBS_DIR / job_id)
    dir_logs = ensure_dir(LOGS_DIR)
    dir_dl = ensure_dir(DOWNLOADS_DIR)
    dir_chunks = ensure_dir(dir_jobs / "chunks")

    log_path = dir_logs / f"{job_id}.log"
    sys.stdout = io.TextIOWrapper(open(log_path, "ab", buffering=0), encoding="utf-8", errors="ignore")
    sys.stderr = sys.stdout
    print(f"[BOOT] direct-stream job={job_id}")

    DIRECT_JOBS[job_id] = {"created": time.time(), "status": "streaming", "procs": [], "log": str(log_path), "dir": str(dir_jobs)}

    url_map = _collect_urls_from_stream_url(payload.stream_url)
    if not url_map:
        raise HTTPException(status_code=400, detail="No URLs found in stream_url (flv_pull_url/rtmp_pull_url/stream_data).")

    primary = _pick_best_url(url_map)
    if not primary:
        raise HTTPException(status_code=400, detail="Could not select a playable primary URL.")

    if payload.download:
        dl_file = Path(payload.download_out) if payload.download_out else (dir_dl / f"live_{job_id}.flv")
        ensure_dir(dl_file.parent)
        p_dl = _run([payload.ffmpeg, *FF_HEADERS, "-y", "-i", primary, "-c", "copy", str(dl_file)])
        DIRECT_JOBS[job_id]["procs"].append(p_dl)

    chunks, p_seg = _ffmpeg_segment_wav(primary, dir_chunks, payload.segment_sec, payload.ffmpeg, FF_HEADERS)
    if p_seg:
        DIRECT_JOBS[job_id]["procs"].append(p_seg)

    if not chunks:
        ao = url_map.get("ao")
        if ao and ao != primary:
            chunks, p_seg2 = _ffmpeg_segment_wav(ao, dir_chunks, payload.segment_sec, payload.ffmpeg, FF_HEADERS)
            if p_seg2:
                DIRECT_JOBS[job_id]["procs"].append(p_seg2)
            primary = ao

    if not chunks:
        DIRECT_JOBS[job_id]["status"] = "error"
        raise HTTPException(status_code=500, detail="Failed to produce WAV chunks (stream may have no audio).")

    return job_id, url_map, primary, dir_jobs, dir_chunks, log_path, chunks, p_seg

@app.post(f"{PREFIX}/direct-stream/sse", dependencies=[Depends(require_key)])
def direct_stream_sse(payload: DirectStreamPayload = Body(...)):
    job_id, url_map, primary, dir_jobs, dir_chunks, log_path, chunks, p_seg = _streaming_setup(payload)
    try:
        model_obj = _load_whisper(payload.model, payload.fw_device, payload.fw_compute)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to load model: {e}")

    srt_path = dir_jobs / f"captions_{job_id}.srt" if payload.persist_srt else None
    txt_path = dir_jobs / f"captions_{job_id}.txt" if payload.persist_txt else None
    srt_segments: List[Tuple[float, float, str]] = []

    def gen():
        nonlocal chunks
        next_idx = 0
        last_sent = time.time()
        start_ts = now_iso()
        yield _sse_format("ready", {"job_id": job_id, "primary_url": primary, "chunks_dir": str(dir_chunks), "started_at": start_ts})
        chunks = sorted(dir_chunks.glob("chunk-*.wav"))
        while True:
            fname = f"chunk-{next_idx:09d}.wav"
            fpath = dir_chunks / fname
            if fpath.exists():
                if _wav_ready(fpath, max_wait_s=payload.segment_sec + 2) and _is_valid_wav(fpath):
                    try:
                        segs = _transcribe_chunk(model_obj, fpath, payload.lang, payload.task)
                        if segs and srt_path:
                            srt_segments.extend(segs)
                            _write_srt(srt_path, srt_segments)
                        if segs and txt_path:
                            with txt_path.open("a", encoding="utf-8") as tf:
                                for _, _, tx in segs:
                                    tf.write(tx + "\n")
                        if segs:
                            data = {
                                "job_id": job_id,
                                "chunk": fname,
                                "index": next_idx,
                                "segments": [{"start": a, "end": b, "text": t} for a,b,t in segs],
                                "ts": now_iso(),
                            }
                            yield _sse_format("segment", data)
                            last_sent = time.time()
                        else:
                            try:
                                db = _wav_rms_db(fpath)
                            except Exception:
                                db = -120.0
                            yield _sse_format("silence", {"job_id": job_id, "chunk": fname, "index": next_idx, "rms_dbfs": db, "ts": now_iso()})
                            last_sent = time.time()
                    except Exception as e:
                        yield _sse_format("error", {"job_id": job_id, "chunk": fname, "error": str(e)})
                next_idx += 1
            else:
                if (time.time() - last_sent) >= payload.keepalive_sec:
                    yield _sse_format("heartbeat", {"job_id": job_id, "index": next_idx, "ts": now_iso()})
                    last_sent = time.time()
                ended = (p_seg and (p_seg.poll() is not None))
                if ended:
                    waited = 0
                    while waited < payload.idle_stop_sec and not fpath.exists():
                        time.sleep(0.5)
                        waited += 0.5
                    if not fpath.exists():
                        yield _sse_format("done", {"job_id": job_id, "reason": "segmenter_ended", "index": next_idx})
                        break
                time.sleep(0.2)
        DIRECT_JOBS.get(job_id, {}).update({"status": "done"})
    headers = {
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
        "Content-Type": "text/event-stream; charset=utf-8",
    }
    return StreamingResponse(gen(), headers=headers, media_type="text/event-stream")

# ---- WebSocket streaming ----
@app.get(f"{PREFIX}/direct-stream/ws")
async def direct_stream_ws(websocket: WebSocket, api_key: Optional[str] = Query(default=None)):
    if APP_TOKEN and api_key != APP_TOKEN:
        await websocket.close(code=4401)
        return
    await websocket.accept()
    try:
        init = await websocket.receive_json()
    except Exception:
        await websocket.send_json({"event": "error", "error": "expect JSON payload as first message"})
        await websocket.close(code=1003)
        return
    try:
        payload = DirectStreamPayload(**init)
    except Exception as e:
        await websocket.send_json({"event": "error", "error": f"invalid payload: {e}"})
        await websocket.close(code=1003)
        return

    loop = asyncio.get_running_loop()
    try:
        job_id, url_map, primary, dir_jobs, dir_chunks, log_path, chunks, p_seg = await loop.run_in_executor(
            None, _streaming_setup, payload
        )
    except Exception as e:
        await websocket.send_json({"event": "error", "error": str(e)})
        await websocket.close(code=1011)
        return

    try:
        model_obj = await loop.run_in_executor(None, _load_whisper, payload.model, payload.fw_device, payload.fw_compute)
    except Exception as e:
        await websocket.send_json({"event": "error", "error": f"failed to load model: {e}"})
        await websocket.close(code=1011)
        return

    await websocket.send_json({"event": "ready", "job_id": job_id, "primary_url": primary, "chunks_dir": str(dir_chunks), "started_at": now_iso()})

    srt_path = dir_jobs / f"captions_{job_id}.srt" if payload.persist_srt else None
    txt_path = dir_jobs / f"captions_{job_id}.txt" if payload.persist_txt else None
    srt_segments: List[Tuple[float, float, str]] = []

    next_idx = 0
    last_sent = time.time()

    try:
        while True:
            fname = f"chunk-{next_idx:09d}.wav"
            fpath = dir_chunks / fname
            exists = fpath.exists()
            if exists:
                ready = await loop.run_in_executor(None, _wav_ready, fpath, payload.segment_sec + 2)
                valid = await loop.run_in_executor(None, _is_valid_wav, fpath)
                if ready and valid:
                    try:
                        segs = await loop.run_in_executor(None, _transcribe_chunk, model_obj, fpath, payload.lang, payload.task)
                        if segs and srt_path:
                            srt_segments.extend(segs)
                            await loop.run_in_executor(None, _write_srt, srt_path, srt_segments)
                        if segs and txt_path:
                            def _append_txt():
                                with txt_path.open("a", encoding="utf-8") as tf:
                                    for _, _, tx in segs:
                                        tf.write(tx + "\n")
                            await loop.run_in_executor(None, _append_txt)
                        if segs:
                            await websocket.send_json({
                                "event": "segment",
                                "job_id": job_id,
                                "chunk": fname,
                                "index": next_idx,
                                "segments": [{"start": a, "end": b, "text": t} for a,b,t in segs],
                                "ts": now_iso(),
                            })
                            last_sent = time.time()
                        else:
                            try:
                                db = await loop.run_in_executor(None, _wav_rms_db, fpath)
                            except Exception:
                                db = -120.0
                            await websocket.send_json({
                                "event": "silence",
                                "job_id": job_id,
                                "chunk": fname,
                                "index": next_idx,
                                "rms_dbfs": db,
                                "ts": now_iso(),
                            })
                            last_sent = time.time()
                    except Exception as e:
                        await websocket.send_json({"event": "error", "job_id": job_id, "chunk": fname, "error": str(e)})
                next_idx += 1
            else:
                if (time.time() - last_sent) >= payload.keepalive_sec:
                    await websocket.send_json({"event": "heartbeat", "job_id": job_id, "index": next_idx, "ts": now_iso()})
                    last_sent = time.time()
                ended = (p_seg and (p_seg.poll() is not None))
                if ended:
                    waited = 0
                    while waited < payload.idle_stop_sec and not fpath.exists():
                        await asyncio.sleep(0.5)
                        waited += 0.5
                    if not fpath.exists():
                        await websocket.send_json({"event": "done", "job_id": job_id, "reason": "segmenter_ended", "index": next_idx})
                        break
                await asyncio.sleep(0.2)
    except WebSocketDisconnect:
        pass
    finally:
        meta = DIRECT_JOBS.get(job_id)
        if meta:
            meta["status"] = "done"
        with contextlib.suppress(Exception):
            await websocket.close()

# ---- Alternate direct-stream (session-based SSE) ----
async def _sse_gen(session_id: str, keepalive_sec: int = 15):
    state = _sessions.get(session_id)
    if not state:
        raise HTTPException(status_code=404, detail="Invalid session_id")
    q: asyncio.Queue = state["queue"]
    stop: asyncio.Event = state["stop"]

    async def _yield(evt: str, data: Any):
        payload = f"event: {evt}\n" + f"data: {json.dumps(data, ensure_ascii=False)}\n\n"
        return payload

    last_ping = time.time()
    try:
        while not stop.is_set():
            try:
                item = await asyncio.wait_for(q.get(), timeout=1.0)
                yield await _yield(item["event"], item["data"])
                last_ping = time.time()
            except asyncio.TimeoutError:
                if time.time() - last_ping >= keepalive_sec:
                    yield "event: heartbeat\n" + "data: " + json.dumps({"ts": datetime.utcnow().isoformat()}) + "\n\n"
                    last_ping = time.time()
    finally:
        stop.set()

@app.post("/v1/tiktok/captions/direct-stream/start", dependencies=[Depends(require_key)])
async def direct_stream_start(cfg: Dict[str, Any] = Body(...)):
    session_id = uuid.uuid4().hex
    q: asyncio.Queue = asyncio.Queue(maxsize=1000)
    stop = asyncio.Event()

    async def push(event: str, data: Any):
        try:
            await q.put({"event": event or "message", "data": data})
        except asyncio.QueueFull:
            pass

    async def _run_direct_stream_worker(session_id: str, cfg: Dict[str, Any], push):
        try:
            payload = DirectStreamPayload(**cfg)
        except Exception as e:
            await push("error", {"session_id": session_id, "error": f"invalid payload: {e}"})
            return
        loop = asyncio.get_running_loop()
        try:
            job_id, url_map, primary, dir_jobs, dir_chunks, log_path, chunks, p_seg = await loop.run_in_executor(
                None, _streaming_setup, payload
            )
        except Exception as e:
            await push("error", {"session_id": session_id, "error": str(e)})
            return
        await push("ready", {
            "session_id": session_id,
            "job_id": job_id,
            "primary_url": primary,
            "chunks_dir": str(dir_chunks),
            "ts": now_iso(),
        })
        try:
            model_obj = await loop.run_in_executor(None, _load_whisper, payload.model, payload.fw_device, payload.fw_compute)
        except Exception as e:
            await push("error", {"session_id": session_id, "error": f"failed to load model: {e}"})
            return

        srt_path = (dir_jobs / f"captions_{job_id}.srt") if payload.persist_srt else None
        txt_path = (dir_jobs / f"captions_{job_id}.txt") if payload.persist_txt else None
        srt_segments: List[Tuple[float, float, str]] = []

        next_idx = 0
        last_sent = time.time()

        try:
            while not _sessions[session_id]["stop"].is_set():
                fname = f"chunk-{next_idx:09d}.wav"
                fpath = dir_chunks / fname
                if fpath.exists():
                    ready = await loop.run_in_executor(None, _wav_ready, fpath, payload.segment_sec + 2)
                    valid = await loop.run_in_executor(None, _is_valid_wav, fpath)
                    if ready and valid:
                        try:
                            segs = await loop.run_in_executor(None, _transcribe_chunk, model_obj, fpath, payload.lang, payload.task)
                            if segs and srt_path:
                                srt_segments.extend(segs)
                                await loop.run_in_executor(None, _write_srt, srt_path, srt_segments)
                            if segs and txt_path:
                                def _append_txt():
                                    with txt_path.open("a", encoding="utf-8") as tf:
                                        for _, _, tx in segs:
                                            tf.write(tx + "\n")
                                await loop.run_in_executor(None, _append_txt)
                            if segs:
                                await push("segment", {
                                    "session_id": session_id,
                                    "job_id": job_id,
                                    "chunk": fname,
                                    "index": next_idx,
                                    "segments": [{"start": a, "end": b, "text": t} for a, b, t in segs],
                                    "ts": now_iso(),
                                })
                            else:
                                try:
                                    db = await loop.run_in_executor(None, _wav_rms_db, fpath)
                                except Exception:
                                    db = -120.0
                                await push("silence", {
                                    "session_id": session_id,
                                    "job_id": job_id,
                                    "chunk": fname,
                                    "index": next_idx,
                                    "rms_dbfs": db,
                                    "ts": now_iso(),
                                })
                            last_sent = time.time()
                        except Exception as e:
                            await push("error", {"session_id": session_id, "job_id": job_id, "chunk": fname, "error": str(e)})
                    next_idx += 1
                else:
                    if (time.time() - last_sent) >= payload.keepalive_sec:
                        await push("heartbeat", {"session_id": session_id, "job_id": job_id, "index": next_idx, "ts": now_iso()})
                        last_sent = time.time()
                    ended = (p_seg and (p_seg.poll() is not None))
                    if ended:
                        waited = 0.0
                        while waited < payload.idle_stop_sec and not fpath.exists():
                            await asyncio.sleep(0.5)
                            waited += 0.5
                        if not fpath.exists():
                            await push("done", {"session_id": session_id, "job_id": job_id, "reason": "segmenter_ended", "index": next_idx})
                            break
                    await asyncio.sleep(0.2)
        finally:
            meta = DIRECT_JOBS.get(job_id)
            if meta:
                meta["status"] = "done"

    task = asyncio.create_task(_run_direct_stream_worker(session_id, cfg, push))
    _sessions[session_id] = {"queue": q, "stop": stop, "task": task, "created": time.time(), "cfg": cfg}
    return {"session_id": session_id}

@app.get("/v1/tiktok/captions/direct-stream/sse", dependencies=[Depends(require_key)])
async def direct_stream_sse_session(
    request: Request,
    session_id: str = Query(..., description="session id from /start"),
):
    if session_id not in _sessions:
        raise HTTPException(404, "Invalid session_id")
    headers = {
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    }
    gen = _sse_gen(session_id)
    return StreamingResponse(gen, media_type="text/event-stream", headers=headers)

@app.post("/v1/tiktok/captions/direct-stream/stop", dependencies=[Depends(require_key)])
async def direct_stream_stop(session_id: str = Body(..., embed=True)):
    state = _sessions.get(session_id)
    if not state:
        raise HTTPException(404, "Invalid session_id")
    state["stop"].set()
    try:
        await asyncio.wait_for(state["task"], timeout=3)
    except asyncio.TimeoutError:
        state["task"].cancel()
    finally:
        _sessions.pop(session_id, None)
    return {"ok": True}

# Optional ping for TikTok block (no collision with global "/")
@app.get("/v1/tiktok/ping", dependencies=[Depends(require_key)])
def tiktok_ping():
    return {"ok": True, "name": "TikTok Live Caption API (merged)", "version": APP_VERSION, "time": now_iso()}

# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    import argparse
    import uvicorn

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.getenv("HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.getenv("PORT", "8000")))
    parser.add_argument("--tray", dest="tray", action="store_true", help="Show system tray icon")
    parser.add_argument("--no-tray", dest="tray", action="store_false")
    parser.set_defaults(tray=True)

    args = parser.parse_args()

    app.state.port = args.port
    app.state.start_cfg = {"tray": args.tray}

    # Use uvicorn.Server so tray can request shutdown via should_exit
    uvicorn_kwargs = {
        "host": args.host,
        "port": args.port,
        "log_config": None,   # avoid stderr isatty formatter issues in --windowed mode
        "access_log": False,
        "log_level": os.getenv("LOG_LEVEL", "info"),
    }

    config = uvicorn.Config(app, **uvicorn_kwargs)
    server = uvicorn.Server(config)
    app.state.server = server
    server.run()