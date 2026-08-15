#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
comment_click_router.py — v4.5 The Unstoppable
- Chiến thuật: Quét sâu (Deep Scan) cả Iframe và Shadow DOM.
- Logic: Tự động lặp lại Click vật lý cho tới khi phát hiện ô chat.
- Hành động: Mở Opera -> Navigate -> Click-to-Find -> Fill Text -> Click Send.
"""

from __future__ import annotations
import asyncio, json, logging, os, platform, subprocess, time, socket
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Literal
import requests, websockets
from fastapi import APIRouter, HTTPException

log = logging.getLogger("comment_click_router")
router = APIRouter()

# --- Pydantic Fix ---
try:
    from pydantic import BaseModel, Field
    _PD_V2 = hasattr(BaseModel, 'model_validate')
    if _PD_V2: from pydantic import ConfigDict
except Exception:
    from pydantic.v1 import BaseModel, Field
    _PD_V2 = False

class CommentClickReq(BaseModel):
    site: str
    title_comment_button: str = Field("Viết comment")
    # Selector dự phòng cho cả Live và Video thường
    comment_selector: str = Field('div[contenteditable="plaintext-only"], div[data-e2e="comment-text"], .css-113kwq0')
    profiles: List[str]
    profiles_root: str = Field("C:\\OperaProfiles")
    profile_urls: Optional[Dict[str, str]] = None
    typing_text: str = "Tooi xem nhaamf phim ah?"
    press_enter_after: bool = True
    key_interval_ms: int = 60
    coords_file: str = "mouse_coords.json"
    host: str = "127.0.0.1"
    port: int = 9222
    send_btn_x: int = 1877
    send_btn_y: int = 995
    if _PD_V2:
        model_config = ConfigDict(extra="ignore")
    else:
        class Config:
            extra = "ignore"

# --- Win32 Native Fix ---
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

def _native_action(x: int = None, y: int = None, click: bool = True):
    if not _IS_WIN: return
    if x is not None and y is not None:
        vw, vh = user32.GetSystemMetrics(78), user32.GetSystemMetrics(79)
        nx, ny = int(x * 65535 / (vw - 1)), int(y * 65535 / (vh - 1))
        inp_m = INPUT(type=0, mi=MOUSEINPUT(nx, ny, 0, 0x0001 | 0x8000 | 0x4000, 0, None))
        user32.SendInput(1, ctypes.byref(inp_m), ctypes.sizeof(inp_m))
        time.sleep(0.1)
    if click:
        for f in [0x0002, 0x0004]:
            inp_c = INPUT(type=0, mi=MOUSEINPUT(0, 0, 0, f, 0, None))
            user32.SendInput(1, ctypes.byref(inp_c), ctypes.sizeof(inp_c))
            time.sleep(0.05)

async def ensure_opera(profile_dir: str, port: int):
    def up():
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1): return True
        except: return False
    if up(): return
    candidates = [Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Opera" / "opera.exe", Path("C:/Program Files/Opera/opera.exe")]
    exe = next((str(c) for c in candidates if c.exists()), "opera.exe")
    subprocess.Popen([exe, f"--user-data-dir={profile_dir}", f"--remote-debugging-port={port}", "--remote-allow-origins=*", "--no-first-run"])
    for _ in range(40):
        if up(): return
        await asyncio.sleep(0.5)

# ===========================
#  HÀM LOGIC CHÍNH
# ===========================

async def _handle_profile(req: CommentClickReq, prof: str, bx: int, by: int) -> Dict:
    prof_path = Path(req.profiles_root) / prof
    await ensure_opera(str(prof_path), req.port)
    
    # Lấy WebSocket
    try:
        r = requests.get(f"http://{req.host}:{req.port}/json", timeout=3)
        ws_url = next(t["webSocketDebuggerUrl"] for t in r.json() if t["type"] == "page")
    except: return {"profile": prof, "ok": False, "err": "ws_fail"}

    try:
        async with websockets.connect(ws_url) as ws:
            url = (req.profile_urls or {}).get(prof)
            if url:
                await ws.send(json.dumps({"id": 1, "method": "Page.navigate", "params": {"url": url}}))
                await asyncio.sleep(8.0) # TikTok LIVE cần thời gian load rất dài

            target_pos = None
            # CHIẾN THUẬT: Click liên tục + Quét sâu (Deep Scan)
            for attempt in range(12):
                _native_action(bx, by, click=True)
                await asyncio.sleep(2.5)

                # Script quét sâu cả trong Iframe
                find_js = f"""(() => {{
                    const find = (doc) => {{
                        const el = doc.querySelector('{req.comment_selector}');
                        if (el) {{
                            el.focus();
                            el.click(); // Force click bằng JS
                            const r = el.getBoundingClientRect();
                            return {{x: r.left + r.width/2, y: r.top + r.height/2}};
                        }}
                        const iframes = doc.querySelectorAll('iframe');
                        for (let f of iframes) {{
                            try {{
                                const res = find(f.contentDocument);
                                if (res) return res;
                            }} catch(e) {{}}
                        }}
                        return null;
                    }};
                    return find(document);
                }})()"""
                
                await ws.send(json.dumps({"id": 400 + attempt, "method": "Runtime.evaluate", "params": {"expression": find_js, "returnByValue": True}}))
                resp = json.loads(await ws.recv())
                target_pos = resp.get("result", {}).get("result", {}).get("value")
                if target_pos: break

            if target_pos:
                # Gõ chữ
                for ch in req.typing_text:
                    await ws.send(json.dumps({"id": 5, "method": "Input.insertText", "params": {"text": ch}}))
                    await asyncio.sleep(req.key_interval_ms / 1000.0)
                
                await asyncio.sleep(1.0)
                # Click gửi tại (1877, 995)
                _native_action(req.send_btn_x, req.send_btn_y, click=True)
                return {"profile": prof, "ok": True}
            
            return {"profile": prof, "ok": False, "err": "selector_not_found_even_after_deep_scan"}
            
    except Exception as e: return {"profile": prof, "ok": False, "err": str(e)}

@router.post("/v1/comment/click")
async def comment_click_api(req: CommentClickReq):
    try:
        with open(req.coords_file, "r", encoding="utf-8") as f:
            coords = json.load(f)
        entry = next(i for i in coords["sites"][req.site] if i["title"] == req.title_comment_button)
        bx, by = int(entry["screenX"]), int(entry["screenY"])
    except: raise HTTPException(400, "Lỗi file tọa độ.")

    results = []
    for p in req.profiles:
        results.append(await _handle_profile(req, p, bx, by))
    return {"results": results}