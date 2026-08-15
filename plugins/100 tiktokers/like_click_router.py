#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
like_click_router.py — v3.3 Stream Optimized (Dynamic Selector)
- Tính năng: Tự động mở Opera (ensure_opera).
- Tính năng: Hỗ trợ like_selector động để kiểm tra trạng thái trang LIVE.
- Chiến thuật: Nếu là Live, sẽ đợi selector xuất hiện rồi mới click tọa độ vật lý.
"""

from __future__ import annotations
import asyncio
import json
import logging
import os
import platform
import subprocess
import time
import socket
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests
import websockets
from fastapi import APIRouter, HTTPException

log = logging.getLogger("like_click_router")
router = APIRouter()

# --- Pydantic & Win32 Helpers ---
try:
    from pydantic import BaseModel, Field
    _PD_V2 = hasattr(BaseModel, "model_validate")
    if _PD_V2: from pydantic import ConfigDict
except Exception:
    from pydantic.v1 import BaseModel, Field
    _PD_V2 = False

_IS_WIN = platform.system() == "Windows"
if _IS_WIN:
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                    ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_void_p)]
    class INPUT(ctypes.Structure):
        _fields_ = [("type", wintypes.DWORD), ("mi", MOUSEINPUT)]

def _native_click(x: int, y: int):
    if not _IS_WIN: return
    vw, vh = user32.GetSystemMetrics(78), user32.GetSystemMetrics(79)
    nx, ny = int(x * 65535 / (vw - 1)), int(y * 65535 / (vh - 1))
    # Move & Click
    m = INPUT(type=0, mi=MOUSEINPUT(nx, ny, 0, 0x0001 | 0x8000 | 0x4000, 0, None))
    user32.SendInput(1, ctypes.byref(m), ctypes.sizeof(m))
    time.sleep(0.1)
    for f in [0x0002, 0x0004]:
        c = INPUT(type=0, mi=MOUSEINPUT(0, 0, 0, f, 0, None))
        user32.SendInput(1, ctypes.byref(c), ctypes.sizeof(c))
        time.sleep(0.05)

# --- Opera Management ---
async def ensure_opera(profile_dir: str, port: int):
    def check():
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1): return True
        except: return False
    if check(): return
    candidates = [Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Opera" / "opera.exe", Path("C:/Program Files/Opera/opera.exe")]
    exe = next((str(c) for c in candidates if c.exists()), "opera.exe")
    subprocess.Popen([exe, f"--user-data-dir={profile_dir}", f"--remote-debugging-port={port}", "--remote-allow-origins=*", "--no-first-run"])
    for _ in range(40):
        if check(): return
        await asyncio.sleep(0.5)

# ==================================================
# CORE LOGIC: LIKE CLICKER
# ==================================================

async def _handle_like(req: LikeClickReq, prof: str, sx: int, sy: int) -> Dict:
    prof_path = Path(req.profiles_root) / prof
    await ensure_opera(str(prof_path), req.port)
    
    try:
        r = requests.get(f"http://{req.host}:{req.port}/json", timeout=2)
        ws_url = next(t["webSocketDebuggerUrl"] for t in r.json() if t["type"] == "page")
    except: return {"profile": prof, "ok": False, "err": "ws_fail"}

    try:
        async with websockets.connect(ws_url) as ws:
            nav_url = req.profile_urls.get(prof)
            if nav_url:
                await ws.send(json.dumps({"id": 1, "method": "Page.navigate", "params": {"url": nav_url}}))
                await asyncio.sleep(6.0) # Đợi trang Live load

            # CHIẾN THUẬT: Đợi Selector xuất hiện rồi mới click tọa độ
            if req.title == "Thả tim trong Live":
                found = False
                for attempt in range(10): # Thử 10 lần quét DOM
                    find_js = f"document.querySelector('{req.like_selector}') !== null"
                    await ws.send(json.dumps({"id": 100+attempt, "method": "Runtime.evaluate", "params": {"expression": find_js, "returnByValue": True}}))
                    
                    msg = await ws.recv()
                    res = json.loads(msg).get("result", {}).get("result", {}).get("value")
                    
                    if res is True:
                        log.info(f"Đã thấy selector {req.like_selector}, tiến hành click.")
                        _native_click(sx, sy)
                        found = True
                        break
                    await asyncio.sleep(1.5)
                
                if not found: return {"profile": prof, "ok": False, "err": "like_selector_not_found"}
                return {"profile": prof, "ok": True, "mode": "live_selector_verified"}

            # LOGIC CŨ: Cho các title khác
            _native_click(sx, sy)
            return {"profile": prof, "ok": True, "mode": "standard_click"}

    except Exception as e: return {"profile": prof, "ok": False, "err": str(e)}

class LikeClickReq(BaseModel):
    site: str
    title: str
    like_selector: str = Field('div[data-e2e="live-chat-input-container"]', description="Selector để check trang đã load xong")
    profiles: List[str]
    profiles_root: str = "C:\\OperaProfiles"
    profile_urls: Dict[str, str] = {}
    host: str = "127.0.0.1"
    port: int = 9222
    coords_file: str = "mouse_coords.json"
    if _PD_V2: model_config = ConfigDict(extra="ignore")
    else:
        class Config: extra = "ignore"

@router.post("/v1/like/click")
async def like_click(req: LikeClickReq):
    try:
        with open(req.coords_file, "r", encoding="utf-8") as f:
            coords = json.load(f)
        entry = next(i for i in coords["sites"][req.site] if i["title"] == req.title)
        sx, sy = int(entry["screenX"]), int(entry["screenY"])
    except: raise HTTPException(400, "Lỗi file tọa độ hoặc tiêu đề.")

    results = []
    for p in req.profiles:
        results.append(await _handle_like(req, p, sx, sy))
    return {"results": results}