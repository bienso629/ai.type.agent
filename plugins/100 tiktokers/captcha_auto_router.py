# -*- coding: utf-8 -*-
"""
Captcha Auto Watcher Router
- SSE endpoint to watch profiles and auto-click a saved coordinate when TikTok captcha container appears
- Designed to plug into opera_api.py via app.include_router(...)

Usage:
  from captcha_auto_router import router as captcha_auto_router
  app.include_router(captcha_auto_router)

Endpoint:
  GET /v1/opera/captcha-auto/stream
    query params:
      profiles_root: str = default from opera_api (pass explicitly here)
      profiles: CSV list of profiles (e.g., Profile001,Profile002) or omit to scan all Profile*
      host: DevTools host (default 127.0.0.1)
      site: target domain (default "tiktok.com")
      selector: css selector for captcha container (default "#captcha-verify-container-main-page")
      coords_file: path to JSON with saved coordinates (default "mouse_coords.json")
      coord_title: title key to lookup within coords (default "Captcha-Audio")
      poll_ms: polling interval (default 400)
      cooldown_ms: cooldown after a detected click (default 5000)
      topmost_ms: bring-to-top duration on Windows (default 1200)

Notes:
- Works best on Windows (auto-click & ontop use Win32 APIs). On non-Windows, events still stream but ontop/click are skipped.
- Self-contained: duplicates minimal helpers to avoid circular imports with opera_api.py.
"""
import asyncio
import json
import os
import platform
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests
import websockets
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

# ---------------- Platform helpers (Windows) ----------------
_IS_WIN = platform.system() == "Windows"
if _IS_WIN:
    import ctypes
    import ctypes.wintypes as wt
    user32 = ctypes.windll.user32
    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_SHOWWINDOW = 0x0040
    HWND_TOPMOST = -1
    HWND_NOTOPMOST = -2
    SW_SHOW = 5
    MOUSEEVENTF_LEFTDOWN = 0x0002
    MOUSEEVENTF_LEFTUP = 0x0004

    def _enum_windows_for_pid(pid: int) -> Optional[int]:
        """Return the first top-level window handle for a given PID."""
        hwnd_found: Optional[int] = None
        @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
        def cb(hwnd, lparam):
            nonlocal hwnd_found
            _pid = wt.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(_pid))
            if int(_pid.value) == int(pid):
                hwnd_found = int(hwnd)
                return False  # stop
            return True
        user32.EnumWindows(cb, 0)
        return hwnd_found

    def _bring_ontop(hwnd: int, duration_ms: int = 1200) -> None:
        try:
            user32.ShowWindow(hwnd, SW_SHOW)
            user32.SetForegroundWindow(hwnd)
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
            time.sleep(max(0, min(duration_ms, 10000)) / 1000.0)
            user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
        except Exception:
            pass

    def _set_cursor(x: int, y: int) -> None:
        user32.SetCursorPos(int(x), int(y))

    def _left_click() -> None:
        user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        time.sleep(0.02)
        user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
else:
    def _enum_windows_for_pid(pid: int) -> Optional[int]:
        return None
    def _bring_ontop(hwnd: int, duration_ms: int = 1200) -> None:
        return None
    def _set_cursor(x: int, y: int) -> None:
        return None
    def _left_click() -> None:
        return None

# ---------------- DevTools helpers (self-contained) ----------------
DEVTOOLS_SUBPATHS = ["", "Opera Stable", "Default"]

def _active_port_file_candidates(profile_dir: Path) -> List[Path]:
    return [profile_dir / sub / "DevToolsActivePort" for sub in DEVTOOLS_SUBPATHS]

def _build_ws_from_active_port_file(profile_dir: Path, host: str) -> Optional[str]:
    for p in _active_port_file_candidates(profile_dir):
        try:
            if not p.exists():
                continue
            raw = p.read_text(encoding="utf-8", errors="ignore").strip().splitlines()
            if len(raw) >= 2:
                port = int(raw[0]) if raw[0].isdigit() else None
                guid = raw[1].strip()
                if port:
                    return f"ws://{host}:{port}/devtools/browser/{guid}"
        except Exception:
            continue
    return None

def _extract_port_from_ws(ws: Optional[str]) -> Optional[int]:
    if not ws:
        return None
    m = re.match(r"^ws://[^:]+:(\d+)/", str(ws))
    if m and m.group(1).isdigit():
        return int(m.group(1))
    try:
        parts = str(ws).split(":")
        if len(parts) > 1 and parts[1].isdigit():
            return int(parts[1])
    except Exception:
        pass
    return None

def _page_targets(host: str, port: int) -> List[dict]:
    try:
        r = requests.get(f"http://{host}:{port}/json", timeout=1.2)
        if r.ok:
            return r.json()
    except Exception:
        pass
    return []

def _pid_from_port_windows(port: Optional[int]) -> Optional[int]:
    if not (_IS_WIN and port):
        return None
    try:
        import subprocess
        out = subprocess.check_output(["netstat", "-ano"], encoding="utf-8", errors="ignore")
        for line in out.splitlines():
            line = line.strip()
            if not line:
                continue
            if f":{port}" in line and "LISTENING" in line.upper():
                parts = re.split(r"\s+", line)
                if parts and parts[-1].isdigit():
                    return int(parts[-1])
    except Exception:
        pass
    return None

# ---------------- SSE broker ----------------
class _SseBroker:
    def __init__(self):
        self._queue: asyncio.Queue = asyncio.Queue()
    async def publish(self, data: dict):
        await self._queue.put(data)
    async def subscribe(self):
        while True:
            data = await self._queue.get()
            yield f"data: {json.dumps(data, ensure_ascii=False)}\n\n"

BROKER = _SseBroker()
WATCHERS: Dict[str, Dict[str, Any]] = {}

# ---------------- Coords loader ----------------

def _load_site_coord(coords_path: str, site: str, title: str) -> Optional[Tuple[int, int]]:
    """
    Try multiple layouts:
      1) {"sites": {"tiktok.com": [{"title":"Captcha-Audio","screenX":..,"screenY":..}, ...]}}
      2) [{"site":"tiktok.com","title":"Captcha-Audio","screenX":..,"screenY":..}, ...]
      3) {"title":"Captcha-Audio","screenX":..,"screenY":..}
    """
    try:
        raw = Path(coords_path).read_text(encoding="utf-8")
        data = json.loads(raw)
        # 1) sites mapping
        if isinstance(data, dict) and isinstance(data.get("sites"), dict):
            items = data["sites"].get(site) or []
            for it in items:
                if str(it.get("title", "")).strip().lower() == title.strip().lower():
                    x, y = it.get("screenX"), it.get("screenY")
                    if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                        return int(x), int(y)
        # 2) list of points
        if isinstance(data, list):
            for it in data:
                s = str(it.get("site", site)).strip().lower()
                if s.endswith(site) or site in s:
                    if str(it.get("title", "")).strip().lower() == title.strip().lower():
                        x, y = it.get("screenX"), it.get("screenY")
                        if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                            return int(x), int(y)
        # 3) single object
        if isinstance(data, dict) and "screenX" in data and "screenY" in data:
            return int(data.get("screenX")), int(data.get("screenY"))
    except Exception:
        pass
    return None

# ---------------- Watcher task ----------------
async def _auto_watch_profile(profile: str, profiles_root: str, host: str,
                              selector: str, site: str, coords_file: str,
                              coord_title: str, poll_ms: int, cooldown_ms: int,
                              topmost_ms: int):
    """Continuous watcher for a single profile: if TikTok captcha container appears -> click coord."""
    cooldown_until = 0.0
    pdir = Path(profiles_root) / profile
    while True:
        try:
            ws_browser = _build_ws_from_active_port_file(pdir, host)
            port = _extract_port_from_ws(ws_browser) if ws_browser else None
            if not port:
                await asyncio.sleep(1.0)
                continue
            targets = _page_targets(host, int(port))
            page_ws = next((t.get("webSocketDebuggerUrl") for t in targets if t.get("type") == "page" and t.get("webSocketDebuggerUrl")), None)
            if not page_ws:
                await asyncio.sleep(0.8)
                continue

            async with websockets.connect(page_ws, ping_interval=None) as ws_page:
                await ws_page.send(json.dumps({"id": 1, "method": "Runtime.enable"}))
                while True:
                    try:
                        expr = (
                            "(function(){\n"
                            f"const s={json.dumps(selector)};\n"
                            "const has=!!document.querySelector(s);\n"
                            "const h=(location&&location.hostname)||'';\n"
                            "return {has:has, host:h};\n"
                            "})()"
                        )
                        await ws_page.send(json.dumps({"id": 2, "method": "Runtime.evaluate", "params": {"expression": expr, "returnByValue": True}}))
                        msg = await asyncio.wait_for(ws_page.recv(), timeout=1.2)
                        ok = False; hostname = ""
                        try:
                            data = json.loads(msg)
                            if data.get("id") == 2:
                                v = data.get("result", {}).get("result", {}).get("value")
                                if isinstance(v, dict):
                                    ok = bool(v.get("has")); hostname = str(v.get("host") or "")
                        except Exception:
                            pass

                        now = time.monotonic()
                        if ok and (hostname.endswith(site) or ("."+site) in hostname):
                            if now >= cooldown_until:
                                # bring to top (Windows)
                                if _IS_WIN:
                                    try:
                                        pid = _pid_from_port_windows(int(port))
                                        if pid:
                                            hwnd = _enum_windows_for_pid(pid)
                                            if hwnd:
                                                _bring_ontop(hwnd, duration_ms=topmost_ms)
                                                time.sleep(0.12)
                                    except Exception:
                                        pass
                                # click saved coord
                                xy = _load_site_coord(coords_file, site, coord_title)
                                clicked = False
                                if xy and _IS_WIN:
                                    try:
                                        _set_cursor(int(xy[0]), int(xy[1]))
                                        _left_click()
                                        clicked = True
                                    except Exception:
                                        clicked = False
                                await BROKER.publish({
                                    "profile": profile,
                                    "event": "captcha_detected",
                                    "host": hostname,
                                    "selector": selector,
                                    "coords": {"x": (xy[0] if xy else None), "y": (xy[1] if xy else None)},
                                    "clicked": bool(clicked),
                                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                                })
                                cooldown_until = now + max(0.5, cooldown_ms/1000.0)
                        await asyncio.sleep(max(0.05, poll_ms/1000.0))
                    except asyncio.TimeoutError:
                        await asyncio.sleep(max(0.05, poll_ms/1000.0))
                    except websockets.ConnectionClosed:
                        break  # reconnect outer loop
        except Exception as e:
            try:
                await BROKER.publish({
                    "profile": profile,
                    "event": "watcher_error",
                    "error": str(e),
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                })
            except Exception:
                pass
            await asyncio.sleep(1.0)  # backoff

# ---------------- Router & Endpoint ----------------
router = APIRouter()

@router.get("/v1/opera/captcha-auto/stream")
async def captcha_auto_stream(profiles_root: str,
                              profiles: Optional[str] = None,  # CSV: Profile001,Profile002
                              host: str = "127.0.0.1",
                              site: str = "tiktok.com",
                              selector: str = "#captcha-verify-container-main-page",
                              coords_file: str = "mouse_coords.json",
                              coord_title: str = "Captcha-Audio",
                              poll_ms: int = 400,
                              cooldown_ms: int = 5000,
                              topmost_ms: int = 1200):
    """SSE stream that also starts watchers. Auto-clicks Captcha-Audio when TikTok captcha container appears."""
    root = Path(profiles_root)
    if not root.exists():
        raise HTTPException(status_code=404, detail=f"profiles_root not found: {root}")

    if profiles:
        prof_list = [x.strip() for x in profiles.split(',') if x.strip()]
    else:
        prof_list = [d.name for d in sorted(root.glob("Profile*")) if d.is_dir()]

    # start watchers if not started
    for prof in prof_list:
        key = f"{prof}"
        if key not in WATCHERS or WATCHERS[key].get("task") is None or WATCHERS[key]["task"].done():
            t = asyncio.create_task(_auto_watch_profile(prof, profiles_root, host, selector, site, coords_file, coord_title, poll_ms, cooldown_ms, topmost_ms))
            WATCHERS[key] = {"task": t, "started": time.time(), "site": site, "selector": selector}
            try:
                await BROKER.publish({
                    "profile": prof,
                    "event": "watcher_started",
                    "site": site,
                    "selector": selector,
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                })
            except Exception:
                pass

    async def event_generator():
        async for event in BROKER.subscribe():
            yield event
    return StreamingResponse(event_generator(), media_type="text/event-stream")
