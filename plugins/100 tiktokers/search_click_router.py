#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
search_click_router.py

Router FastAPI cho chức năng "Tìm kiếm" + Follow theo tọa độ lưu trong mouse_coords.json.

- Click (Search) theo (site, title)
- Nếu activeElement là <input name="q">: gõ text (per-key) + Enter
- BẮT BUỘC chờ DOM complete sau Enter (+ nghỉ thêm)
- Follow:
   - Lấy toạ độ (site, follow_title), re-ontop (tuỳ chọn)
   - Map SCREEN→CLIENT chuẩn Windows (ScreenToClient + DPR)
   - Poll đúng nút "Follow" (match text/aria + e2e); click (native/dom/both)
   - Timeout vẫn forced-click (tuỳ chọn)
- Lưu **history** vào SQLite cho từng profile

Endpoints:
  POST /v1/search/click
  GET  /v1/search/history  (tuỳ chọn xem lại lịch sử)
"""
from __future__ import annotations

import os
import re
import json
import time
import asyncio
import logging
import platform
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Literal

import requests
import websockets
from fastapi import APIRouter, HTTPException, Query

# === SQLite history helpers ===
from history_db import init_db, insert_history, query_history

# Pydantic v1/v2 guard (tránh lỗi 'regex removed' ở v2)
try:
    from pydantic import BaseModel, Field
    _PD_V2 = hasattr(BaseModel, 'model_validate')
    if _PD_V2:
        from pydantic import ConfigDict
except Exception:  # pragma: no cover
    from pydantic.v1 import BaseModel, Field  # type: ignore
    _PD_V2 = False
    ConfigDict = None  # type: ignore

log = logging.getLogger("search_click_router")

# ===========================
#  NỀN TẢNG
# ===========================
_IS_WIN = platform.system() == "Windows"
def _is_windows() -> bool:
    return _IS_WIN

# ===========================
#  WINDOWS HELPERS (ontop + move/click + DPI/mapping)
# ===========================
if _IS_WIN:
    import ctypes
    import ctypes.wintypes as wt

    user32 = ctypes.windll.user32

    # DPI aware
    try:
        DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = ctypes.c_void_p(-4)
        user32.SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
    except Exception:
        try:
            shcore = ctypes.windll.shcore
            PROCESS_PER_MONITOR_DPI_AWARE = 2
            shcore.SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)
        except Exception:
            try:
                user32.SetProcessDPIAware()
            except Exception:
                pass

    # Show/Topmost
    SW_SHOW = 5
    HWND_TOPMOST = -1
    HWND_NOTOPMOST = -2
    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_SHOWWINDOW = 0x0040

    # Mouse flags
    MOUSEEVENTF_MOVE        = 0x0001
    MOUSEEVENTF_LEFTDOWN    = 0x0002
    MOUSEEVENTF_LEFTUP      = 0x0004
    MOUSEEVENTF_ABSOLUTE    = 0x8000
    MOUSEEVENTF_VIRTUALDESK = 0x4000

    # Virtual desktop metrics
    SM_XVIRTUALSCREEN  = 76
    SM_YVIRTUALSCREEN  = 77
    SM_CXVIRTUALSCREEN = 78
    SM_CYVIRTUALSCREEN = 79

    if hasattr(wt, "ULONG_PTR"):
        ULONG_PTR = wt.ULONG_PTR
    else:
        ULONG_PTR = ctypes.c_ulonglong if ctypes.sizeof(ctypes.c_void_p) == 8 else ctypes.c_ulong

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", wt.LONG),
            ("dy", wt.LONG),
            ("mouseData", wt.DWORD),
            ("dwFlags", wt.DWORD),
            ("time", wt.DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class INPUT(ctypes.Structure):
        _fields_ = [
            ("type", wt.DWORD),
            ("mi", MOUSEINPUT),
        ]

    class POINT(ctypes.Structure):
        _fields_ = [("x", wt.LONG), ("y", wt.LONG)]

    INPUT_MOUSE = 0

    def _win_enum_windows_for_pid(pid: int):
        hwnds = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
        def enum_proc(hwnd, lparam):
            lpdwProcessId = wt.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(lpdwProcessId))
            if lpdwProcessId.value == pid and user32.IsWindowVisible(hwnd):
                hwnds.append(hwnd)
            return True

        user32.EnumWindows(enum_proc, 0)
        return hwnds[0] if hwnds else None

    def _win_bring_window_ontop(hwnd, duration_ms: int = 1000):
        try:
            user32.ShowWindow(hwnd, SW_SHOW)
            user32.SetForegroundWindow(hwnd)
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                                SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
            time.sleep(min(max(duration_ms, 0), 10000) / 1000.0)
            user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                                SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
        except Exception as e:
            log.warning("ONTOP failed: %s", e)

    def _get_virtual_screen_metrics():
        vx = user32.GetSystemMetrics(SM_XVIRTUALSCREEN)
        vy = user32.GetSystemMetrics(SM_YVIRTUALSCREEN)
        vw = user32.GetSystemMetrics(SM_CXVIRTUALSCREEN)
        vh = user32.GetSystemMetrics(SM_CYVIRTUALSCREEN)
        return vx, vy, max(1, vw), max(1, vh)

    def _sendinput_move_absolute(x: int, y: int):
        vx, vy, vw, vh = _get_virtual_screen_metrics()
        nx = int(round((x - vx) * 65535 / max(1, vw - 1)))
        ny = int(round((y - vy) * 65535 / max(1, vh - 1)))
        inp = INPUT(type=INPUT_MOUSE,
                    mi=MOUSEINPUT(dx=nx, dy=ny, mouseData=0,
                                  dwFlags=MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                                  time=0, dwExtraInfo=ULONG_PTR(0)))
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(inp))

    def _set_cursor_pos(x: int, y: int):
        user32.SetCursorPos(int(x), int(y))

    def _get_cursor_pos() -> Tuple[int, int]:
        pt = POINT()
        if user32.GetCursorPos(ctypes.byref(pt)):
            return int(pt.x), int(pt.y)
        return -1, -1

    def _sendinput_left_click():
        down = INPUT(type=INPUT_MOUSE,
                     mi=MOUSEINPUT(dx=0, dy=0, mouseData=0,
                                   dwFlags=MOUSEEVENTF_LEFTDOWN, time=0, dwExtraInfo=ULONG_PTR(0)))
        up = INPUT(type=INPUT_MOUSE,
                   mi=MOUSEINPUT(dx=0, dy=0, mouseData=0,
                                 dwFlags=MOUSEEVENTF_LEFTUP, time=0, dwExtraInfo=ULONG_PTR(0)))
        user32.SendInput(1, ctypes.byref(down), ctypes.sizeof(down))
        time.sleep(0.015)
        user32.SendInput(1, ctypes.byref(up), ctypes.sizeof(up))

    def _win_screen_to_client(hwnd, x: int, y: int) -> Tuple[int, int]:
        """Map Screen (device px) -> Client area (device px)."""
        pt = POINT(int(x), int(y))
        user32.ScreenToClient(hwnd, ctypes.byref(pt))
        return int(pt.x), int(pt.y)
else:
    def _win_enum_windows_for_pid(pid: int): return None
    def _win_bring_window_ontop(hwnd, duration_ms: int = 1000): return None
    def _set_cursor_pos(x: int, y: int): return None
    def _sendinput_move_absolute(x: int, y: int): return None
    def _get_cursor_pos() -> Tuple[int,int]: return (-1,-1)
    def _sendinput_left_click(): return None
    def _win_screen_to_client(hwnd, x: int, y: int) -> Tuple[int,int]: return (x, y)

# ===========================
#  DEVTOOLS HELPERS
# ===========================
def _ports_map_path(root: Path) -> Path:
    return root / ".devtools_ports.json"

def _ports_map_load(root: Path) -> Dict[str, int]:
    try:
        p = _ports_map_path(root)
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {}

def _normalize_path(p: str) -> str:
    return os.path.normcase(os.path.normpath(p or ""))

def _locate_active_port_file(profile_dir: Path) -> Optional[Path]:
    candidates = [
        profile_dir / "DevToolsActivePort",
        profile_dir / "Opera Stable" / "DevToolsActivePort",
        profile_dir / "Default" / "DevToolsActivePort",
    ]
    for p in candidates:
        try:
            if p.exists():
                return p
        except Exception:
            pass
    return None

def _extract_port_from_active_port_file(p: Path) -> Optional[int]:
    try:
        txt = p.read_text(encoding="utf-8", errors="ignore").strip().splitlines()
        if not txt:
            return None
        first = txt[0].strip()
        return int(first) if first.isdigit() else None
    except Exception:
        return None

def _page_targets(host: str, port: int) -> Tuple[List[dict], Optional[str]]:
    url = f"http://{host}:{port}/json"
    try:
        r = requests.get(url, timeout=1.2)
        if r.ok:
            return r.json(), None
        return [], f"http {r.status_code}"
    except Exception as e:
        return [], f"http_err:{e.__class__.__name__}"

def _extract_dir_port_from_cmdline(cmdline: str) -> tuple[Optional[str], Optional[int]]:
    if not cmdline:
        return None, None
    mdir = re.search(r'--user-data-dir(?:=| )"?(?P<dir>[^"\r\n]+)"?', cmdline, flags=re.IGNORECASE)
    mport = re.search(r'--remote-debugging-port(?:=| )(?P<port>\d+)', cmdline, flags=re.IGNORECASE)
    ud = mdir.group("dir") if mdir else None
    pr = int(mport.group("port")) if mport else None
    return ud, pr

def _list_opera_cmdlines_windows() -> List[Dict[str, Any]]:
    out_items: List[Dict[str, Any]] = []
    try:
        out = subprocess.check_output(
            ['wmic', 'process', 'where', '(name="opera.exe" or name="opera_gx.exe")',
             'get', 'ProcessId,CommandLine', '/VALUE'],
            encoding='utf-8', errors='ignore'
        )
        cur: Dict[str, Any] = {}
        for line in out.splitlines():
            line = line.strip()
            if not line:
                if cur:
                    out_items.append(cur); cur = {}
                continue
            if line.startswith("CommandLine="):
                cur["CommandLine"] = line[len("CommandLine="):]
            elif line.startswith("ProcessId="):
                v = line[len("ProcessId="):]
                cur["ProcessId"] = int(v) if v.isdigit() else None
        if cur:
            out_items.append(cur)
        if out_items:
            return out_items
    except Exception:
        out_items = []

    # Fallback PowerShell
    try:
        ps_cmd = (
            'Get-CimInstance Win32_Process -Filter "name = \'opera.exe\' or name = \'opera_gx.exe\'" '
            '| Select-Object ProcessId,CommandLine | Format-List'
        )
        out = subprocess.check_output(
            ['powershell', '-NoProfile', '-Command', ps_cmd],
            encoding='utf-8', errors='ignore'
        )
        cur = {}
        for line in out.splitlines():
            line = line.rstrip()
            if not line:
                if cur:
                    out_items.append(cur); cur = {}
                continue
            if line.lower().startswith("processid"):
                try:
                    cur["ProcessId"] = int(line.split(":",1)[1].strip())
                except Exception:
                    cur["ProcessId"] = None
            elif line.lower().startswith("commandline"):
                cur["CommandLine"] = line.split(":",1)[1].strip()
        if cur:
            out_items.append(cur)
    except Exception:
        pass
    return out_items

def _discover_port_for_profile(profile_dir: Path, host: str, diag: Dict[str, Any]) -> Optional[int]:
    f = _locate_active_port_file(profile_dir)
    diag["active_port_file"] = str(f) if f else None
    if f:
        p = _extract_port_from_active_port_file(f)
        diag["port_from_active_file"] = p
        if p:
            return p

    cache = _ports_map_load(profile_dir.parent)
    diag["ports_cache_path"] = str(_ports_map_path(profile_dir.parent))
    diag["port_from_cache"] = cache.get(profile_dir.name)
    if diag["port_from_cache"]:
        return int(diag["port_from_cache"])

    if _is_windows():
        plist = _list_opera_cmdlines_windows()
        diag["proc_checked"] = len(plist)
        target = _normalize_path(str(profile_dir))
        for it in plist:
            cl = it.get("CommandLine") or ""
            udir, port = _extract_dir_port_from_cmdline(cl)
            if udir and port and _normalize_path(udir) == target:
                diag["port_from_process"] = port
                return int(port)
    return None

async def _get_first_page_ws(profile_dir: Path, host: str, diag: Dict[str, Any]) -> Optional[str]:
    port = _discover_port_for_profile(profile_dir, host, diag)
    diag["port_final"] = port
    if not port:
        return None
    targets, http_err = _page_targets(host, port)
    diag["http_err"] = http_err
    diag["targets_len"] = len(targets)
    for t in targets:
        if t.get("type") == "page" and t.get("webSocketDebuggerUrl"):
            ws = t["webSocketDebuggerUrl"]
            diag["first_page_ws"] = ws
            return ws
    return None

async def _navigate_page_ws(page_ws: str, url: str, wait_after_nav_ms: int = 1000) -> bool:
    try:
        async with websockets.connect(page_ws) as ws_page:
            await ws_page.send(json.dumps({"id": 1001, "method": "Page.enable"}))
            await ws_page.send(json.dumps({"id": 1002, "method": "Page.navigate", "params": {"url": url}}))
            end = time.time() + max(0, wait_after_nav_ms) / 1000.0
            while time.time() < end:
                try:
                    _ = await asyncio.wait_for(ws_page.recv(), timeout=0.2)
                except Exception:
                    pass
            return True
    except Exception as e:
        log.warning("Navigate failed for %s: %s", page_ws, e)
        return False

# ---------- Waits ----------
async def _wait_document_complete(page_ws: str, timeout_ms: int = 12000, poll_ms: int = 200) -> bool:
    deadline = time.time() + max(0, timeout_ms) / 1000.0
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 3000, "method": "Runtime.enable"}))
            req_id = 3001
            while time.time() < deadline:
                await ws.send(json.dumps({
                    "id": req_id, "method": "Runtime.evaluate",
                    "params": {"expression": "document.readyState", "returnByValue": True}
                }))
                while True:
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    except Exception:
                        break
                    data = json.loads(msg)
                    if data.get("id") == req_id:
                        state = (data.get("result", {}).get("result", {}).get("value", "")) or ""
                        if str(state).lower() == "complete":
                            return True
                        break
                await asyncio.sleep(max(0.0, poll_ms/1000.0)); req_id += 1
    except Exception as e:
        log.warning("wait_document_complete failed: %s", e)
    return False

async def _wait_selector(page_ws: str, css_selector: str,
                         timeout_ms: int = 12000, poll_ms: int = 200,
                         visibility: Literal["present","visible"] = "present") -> bool:
    deadline = time.time() + max(0, timeout_ms) / 1000.0
    sel = json.dumps(css_selector)
    expr_present = f"!!document.querySelector({sel})"
    expr_visible = (
        "(()=>{const s=document.querySelector(%s);"
        "if(!s) return false;"
        "const r=s.getBoundingClientRect();"
        "const st=getComputedStyle(s);"
        "return st.display!=='none'&&st.visibility!=='hidden'&&r.width>0&&r.height>0;})()"
    ) % sel
    expr = expr_visible if visibility == "visible" else expr_present
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 3100, "method": "Runtime.enable"}))
            req_id = 3101
            while time.time() < deadline:
                await ws.send(json.dumps({"id": req_id, "method": "Runtime.evaluate",
                                          "params": {"expression": expr, "returnByValue": True}}))
                while True:
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    except Exception:
                        break
                    data = json.loads(msg)
                    if data.get("id") == req_id:
                        ok = bool((data.get("result", {}).get("result", {}).get("value", False)))
                        if ok:
                            return True
                        break
                await asyncio.sleep(max(0.0, poll_ms/1000.0)); req_id += 1
    except Exception as e:
        log.warning("wait_selector failed: %s", e)
    return False
# ---------------------------

# ---------- Detect active <input name="q"> & type (per-key + Enter) ----------
async def _is_active_input_q(page_ws: str, timeout_ms: int = 800) -> bool:
    deadline = time.time() + max(0, timeout_ms) / 1000.0
    expr = ("(()=>{const el=document.activeElement;"
            "if(!el) return false;"
            "if(el.tagName!=='INPUT') return false;"
            "return (el.getAttribute('name')||'').toLowerCase()==='q';})()")
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 4000, "method": "Runtime.enable"}))
            req_id = 4001
            while time.time() < deadline:
                await ws.send(json.dumps({"id": req_id, "method": "Runtime.evaluate",
                                          "params": {"expression": expr, "returnByValue": True}}))
                while True:
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    except Exception:
                        break
                    data = json.loads(msg)
                    if data.get("id") == req_id:
                        val = bool((data.get("result", {}).get("result", {}).get("value", False)))
                        if val: return True
                        break
                await asyncio.sleep(0.05); req_id += 1
    except Exception as e:
        log.warning("is_active_input_q failed: %s", e)
    return False

async def _press_enter(ws) -> bool:
    ok = True
    try:
        await ws.send(json.dumps({
            "id": 5001, "method": "Input.dispatchKeyEvent",
            "params": {"type": "rawKeyDown", "key": "Enter", "code": "Enter",
                       "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13,
                       "unmodifiedText": "\r", "text": "\r"}
        }))
        try: _ = await asyncio.wait_for(ws.recv(), timeout=0.25)
        except Exception: pass

        await ws.send(json.dumps({
            "id": 5002, "method": "Input.dispatchKeyEvent",
            "params": {"type": "char", "text": "\r"}
        }))
        try: _ = await asyncio.wait_for(ws.recv(), timeout=0.25)
        except Exception: pass

        await ws.send(json.dumps({
            "id": 5003, "method": "Input.dispatchKeyEvent",
            "params": {"type": "keyUp", "key": "Enter", "code": "Enter",
                       "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13}
        }))
        try: _ = await asyncio.wait_for(ws.recv(), timeout=0.25)
        except Exception: pass
    except Exception as e:
        log.warning("Press Enter failed: %s", e); ok = False
    return ok

async def _type_into_active(page_ws: str, text: str,
                            mode: Literal["bulk","per_key"] = "per_key",
                            clear_before: bool = False,
                            key_interval_ms: int = 80,
                            press_enter_after: bool = True,
                            enter_delay_ms: int = 150) -> Tuple[bool, bool]:
    typed_ok = False
    pressed_enter = False
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 4100, "method": "Input.enable"}))
            if clear_before:
                await ws.send(json.dumps({
                    "id": 4101, "method": "Runtime.evaluate",
                    "params": {"expression": "(()=>{if(document.activeElement){document.activeElement.value='';document.activeElement.dispatchEvent(new Event('input',{bubbles:true}));}})()"}
                }))
                try: _ = await asyncio.wait_for(ws.recv(), timeout=0.4)
                except Exception: pass

            if mode == "bulk":
                await ws.send(json.dumps({"id": 4102, "method": "Input.insertText", "params": {"text": text}}))
                try: _ = await asyncio.wait_for(ws.recv(), timeout=0.4)
                except Exception: pass
                typed_ok = True
            else:
                req_id = 4200
                for ch in text:
                    await ws.send(json.dumps({"id": req_id, "method": "Input.insertText", "params": {"text": ch}}))
                    try: _ = await asyncio.wait_for(ws.recv(), timeout=0.25)
                    except Exception: pass
                    await asyncio.sleep(max(0, key_interval_ms) / 1000.0)
                    req_id += 1
                typed_ok = True

            if typed_ok and press_enter_after:
                await asyncio.sleep(max(0, enter_delay_ms)/1000.0)
                pressed_enter = await _press_enter(ws)

    except Exception as e:
        log.warning("Typing failed: %s", e)

    if not typed_ok:
        try:
            async with websockets.connect(page_ws) as ws2:
                await ws2.send(json.dumps({
                    "id": 4110, "method": "Runtime.evaluate",
                    "params": {"expression": (
                        f"(()=>{{if(document.activeElement){{"
                        f"document.activeElement.value={json.dumps(text)};"
                        f"document.activeElement.dispatchEvent(new Event('input',{{bubbles:true}}));"
                        f"document.activeElement.dispatchEvent(new Event('change',{{bubbles:true}}));"
                        f"}}}})()"
                    )}
                }))
                try: _ = await asyncio.wait_for(ws2.recv(), timeout=0.8)
                except Exception: pass
                typed_ok = True
        except Exception as e2:
            log.warning("Fallback DOM typing failed: %s", e2)

    return typed_ok, pressed_enter
# -----------------------------------------------------------------

# ---------- PID từ PORT (ontop) ----------
def _pid_from_port_windows(port: int) -> Optional[int]:
    if not _is_windows():
        return None
    try:
        out = subprocess.check_output(["netstat", "-ano"], encoding="utf-8", errors="ignore")
        for line in out.splitlines():
            if f":{port} " in line and "LISTENING" in line:
                parts = line.split()
                if parts and parts[-1].isdigit():
                    return int(parts[-1])
    except Exception:
        pass
    return None
# ----------------------------------------

# ===========================
#  PROBING & MAPPING HELPERS
# ===========================
def _normalize_space(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())

def _match_text(txt: str, expect: str, mode: str, case_insensitive: bool, regex_pattern: Optional[str]) -> bool:
    a = txt or ""
    b = expect or ""
    if mode == "regex" and regex_pattern:
        flags = re.I if case_insensitive else 0
        try:
            return re.search(regex_pattern, a, flags) is not None
        except Exception:
            return False
    if case_insensitive:
        a = a.lower(); b = b.lower()
    if mode == "equals":
        return a == b
    if mode == "contains":
        return b in a
    if mode == "startswith":
        return a.startswith(b)
    return False

async def _get_dpr(page_ws: str) -> float:
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 9050, "method": "Runtime.evaluate",
                                      "params": {"expression": "window.devicePixelRatio||1", "returnByValue": True}}))
            for _ in range(20):
                msg = await asyncio.wait_for(ws.recv(), timeout=0.6)
                data = json.loads(msg)
                if data.get("id") == 9050:
                    return float(data.get("result", {}).get("result", {}).get("value", 1.0))
    except Exception:
        pass
    return 1.0

async def _probe_button_at_client_css(page_ws: str, client_x_css: float, client_y_css: float) -> Dict[str, Any]:
    expr = f"""
    (()=>{{
      const x={float(client_x_css)}, y={float(client_y_css)};
      function pick(x,y){{
        const btns = Array.from(document.querySelectorAll('button'));
        for (const b of btns){{
          const r=b.getBoundingClientRect();
          if (x>=r.left && x<=r.right && y>=r.top && y<=r.bottom){{
            const t=(b.innerText||b.textContent||'').trim();
            return {{tag:'BUTTON',text:t,e2e:b.getAttribute('data-e2e')||'',aria:b.getAttribute('aria-label')||'',
                     rect:{{left:r.left,top:r.top,width:r.width,height:r.height,right:r.right,bottom:r.bottom}}}};
          }}
        }}
        const el = document.elementFromPoint(x,y);
        const btn = el?((el.closest&&el.closest('button'))||(el.tagName==='BUTTON'?el:null)):null;
        if (btn){{
          const r=btn.getBoundingClientRect();
          const t=(btn.innerText||btn.textContent||'').trim();
          return {{tag:'BUTTON',text:t,e2e:btn.getAttribute('data-e2e')||'',aria:btn.getAttribute('aria-label')||'',
                   rect:{{left:r.left,top:r.top,width:r.width,height:r.height,right:r.right,bottom:r.bottom}}}};
        }}
        if (el){{
          const r=el.getBoundingClientRect();
          const t=(el.innerText||el.textContent||'').trim();
          return {{tag:el.tagName,text:t,e2e:el.getAttribute&&el.getAttribute('data-e2e')||'',aria:el.getAttribute&&el.getAttribute('aria-label')||'',
                   rect:{{left:r.left,top:r.top,width:r.width,height:r.height,right:r.right,bottom:r.bottom}}}};
        }}
        return {{tag:null,text:'',e2e:'',aria:'',rect:null}};
      }}
      const cand=pick(x,y);
      return {{ok:true, clientX:x, clientY:y, cand}};
    }})()
    """
    out: Dict[str, Any] = {"ok": False}
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 6120, "method": "Runtime.evaluate",
                                      "params": {"expression": expr, "returnByValue": True}}))
            for _ in range(30):
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=0.7)
                except Exception:
                    break
                data = json.loads(msg)
                if data.get("id") == 6120:
                    res = (data.get("result", {}).get("result", {}).get("value", {})) or {}
                    out.update(res)
                    break
    except Exception as e:
        out["error"] = f"probe_css_err:{e.__class__.__name__}"
    return out

async def _dom_click_button_at_client_point(page_ws: str, client_x_css: float, client_y_css: float) -> bool:
    expr = f"""
    (()=>{{
      const x={float(client_x_css)}, y={float(client_y_css)};
      const els = document.elementsFromPoint ? document.elementsFromPoint(x,y) : [document.elementFromPoint(x,y)];
      let btn=null;
      for (const el of els){{
        if (!el) continue;
        if (el.tagName==='BUTTON') {{ btn=el; break; }}
        if (el.closest) {{
          const b=el.closest('button'); if (b) {{ btn=b; break; }}
        }}
      }}
      if (btn) {{ btn.click(); return true; }}
      return false;
    }})()
    """
    try:
        async with websockets.connect(page_ws) as ws:
            await ws.send(json.dumps({"id": 6200, "method": "Runtime.evaluate",
                                      "params": {"expression": expr, "returnByValue": True}}))
            for _ in range(20):
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=0.6)
                except Exception:
                    break
                data = json.loads(msg)
                if data.get("id") == 6200:
                    return bool((data.get("result", {}).get("result", {}).get("value", False)))
    except Exception as e:
        log.warning("dom_click_button_at_client_point failed: %s", e)
    return False

async def _wait_follow_button_at_client_css(page_ws: str,
                                            client_x_css: float, client_y_css: float,
                                            expect_text: str,
                                            text_mode: str,
                                            case_insensitive: bool,
                                            regex_pattern: Optional[str],
                                            require_e2e: bool,
                                            e2e_value: Optional[str],
                                            timeout_ms: int,
                                            poll_ms: int) -> Dict[str, Any]:
    """
    Poll tới khi nút 'Follow' xuất hiện đúng điểm (client CSS px),
    xét BOTH innerText và aria-label để match text.
    """
    deadline = time.time() + max(0, timeout_ms) / 1000.0
    last: Dict[str, Any] = {"ok": False}
    while time.time() < deadline:
        probe = await _probe_button_at_client_css(page_ws, client_x_css, client_y_css)
        cand = (probe.get("cand") or {})
        tag  = (cand.get("tag") or "").upper()
        txt  = _normalize_space(cand.get("text") or "")
        aria = _normalize_space(cand.get("aria") or "")
        e2e  = cand.get("e2e") or ""

        text_ok = (
            _match_text(txt,  expect_text, text_mode, case_insensitive, regex_pattern) or
            _match_text(aria, expect_text, text_mode, case_insensitive, regex_pattern)
        )
        e2e_ok = (not require_e2e) or ((e2e or "").lower() == (e2e_value or "").lower())
        should_click = bool(probe.get("ok") and tag == "BUTTON" and text_ok and e2e_ok)

        last = {
            "ok": probe.get("ok", False),
            "clientX": probe.get("clientX"), "clientY": probe.get("clientY"),
            "cand": cand, "tag": tag, "text": txt, "aria": aria, "e2e": e2e,
            "text_ok": text_ok, "e2e_ok": e2e_ok, "should_click": should_click
        }
        if should_click:
            break
        await asyncio.sleep(max(0, poll_ms)/1000.0)
    return last

# ===========================
#  ĐỌC TOẠ ĐỘ TỪ mouse_coords.json
# ===========================
def _load_site_title_coords(coords_file: str, site: str, title: str) -> Optional[Dict[str, Any]]:
    p = Path(coords_file)
    if not p.exists():
        raise HTTPException(404, f"Không thấy coords_file: {coords_file}")
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        raise HTTPException(400, f"Không đọc được JSON từ {coords_file}: {e}")

    sites = data.get("sites") or {}
    arr = sites.get(site) or []
    title_lc = title.strip().lower()
    cand = [it for it in arr if str(it.get("title","")).strip().lower() == title_lc]
    if not cand:
        return None
    cand.sort(key=lambda x: str(x.get("ts","")), reverse=True)
    return cand[0]

# ===========================
#  API ROUTER
# ===========================
DEFAULT_PROFILES_ROOT = str(Path.home() / "OperaProfiles")
DEFAULT_DB_PATH = str(Path.cwd() / "data" / "search_click_history.db")

class SearchClickReq(BaseModel):
    site: str
    title: str
    profiles: List[str]
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    host: str = Field("127.0.0.1")
    coords_file: str = Field("mouse_coords.json")

    # Điều hướng URL riêng từng profile trước khi click
    profile_urls: Optional[Dict[str, str]] = Field(default=None)
    wait_after_nav_ms: int = Field(1000, ge=0, le=30000)

    # Waits (lần 1 trước click Search)
    wait_for_dom_complete: bool = Field(True)
    dom_complete_timeout_ms: int = Field(15000, ge=0, le=60000)
    wait_selector: Optional[str] = Field(None, description="CSS selector để chờ (tuỳ chọn)")
    selector_visibility: Literal["present","visible"] = "present"
    selector_timeout_ms: int = Field(12000, ge=0, le=60000)

    # Dùng toạ độ screenX/screenY nguyên bản
    use_raw_screen_coords: bool = Field(True)

    # Di chuyển/nhấp cho bước Search
    move_mode: Literal["sendinput_abs", "setcursorpos"] = "sendinput_abs"
    offset_x: int = Field(0)
    offset_y: int = Field(0)
    click_delay_ms: int = Field(120, ge=0, le=2000)
    repeats: int = Field(1, ge=1, le=10)
    interval_ms: int = Field(160, ge=20, le=5000)
    force_move_each_click: bool = Field(True)
    topmost_ms: int = Field(800, ge=0, le=10000)

    # DPR chỉ dùng khi use_raw_screen_coords=False
    prefer_cdp_dpr: bool = Field(True)
    dpr: Optional[float] = None

    # Xác minh toạ độ sau khi move
    verify_move: bool = Field(True)
    verify_tolerance_px: int = Field(3, ge=0, le=20)
    verify_timeout_ms: int = Field(350, ge=50, le=3000)

    # Auto type if <input name="q">
    type_if_input_q: bool = Field(True, description="Nếu activeElement là input[name='q'] thì gõ text")
    type_text: str = Field("xin chào!")
    type_delay_ms: int = Field(150, ge=0, le=3000)
    type_clear_before: bool = Field(False)
    type_check_timeout_ms: int = Field(800, ge=0, le=5000)
    type_mode: Literal["bulk","per_key"] = "per_key"
    key_interval_ms: int = Field(80, ge=0, le=2000)
    press_enter_after: bool = Field(True)
    enter_delay_ms: int = Field(150, ge=0, le=3000)

    # Wait sau khi Enter (BẮT BUỘC)
    after_enter_wait_dom_complete: bool = Field(True)
    after_enter_dom_timeout_ms: int = Field(15000, ge=0, le=60000)
    after_enter_extra_wait_ms: int = Field(400, ge=0, le=5000)

    # Bước Follow: selector tổng quát (tuỳ chọn) + toạ độ & điều kiện match
    follow_wait_selector: Optional[str] = Field(None, description="VD: button[data-e2e='follow-button']")
    follow_selector_visibility: Literal["present","visible"] = "present"
    follow_selector_timeout_ms: int = Field(12000, ge=0, le=60000)

    follow_title: str = Field("Search-Follow")
    follow_expect_text: str = Field("Follow")
    # Mặc định nới lỏng để dễ khớp hơn các biến thể text/aria
    follow_text_match: Literal["equals","contains","startswith","regex"] = "contains"
    follow_regex: Optional[str] = Field(None, description="Dùng khi follow_text_match='regex'")
    follow_case_insensitive: bool = Field(True)
    follow_require_e2e: bool = Field(False)
    follow_e2e_value: Optional[str] = Field("follow-button")

    # Đợi nút 'Follow' xuất hiện đúng tọa độ
    follow_appear_timeout_ms: int = Field(8000, ge=0, le=60000)
    follow_appear_poll_ms: int = Field(150, ge=20, le=2000)

    # Click Follow: chiến lược & timing
    follow_hover_ms: int = Field(100, ge=0, le=3000)
    follow_click_strategy: Literal["native","dom","both"] = "both"
    follow_click_delay_ms: int = Field(80, ge=0, le=2000)
    follow_post_click_ms: int = Field(160, ge=0, le=5000)

    # Re-ontop trước Follow + Forced click khi timeout
    re_ontop_before_follow: bool = Field(True)
    follow_force_timeout_click: bool = Field(True)
    follow_force_click_strategy: Literal["native","dom","both"] = "both"
    follow_force_click_delay_ms: int = Field(0, ge=0, le=2000)

    # Lưu history
    persist_history: bool = Field(True)
    history_db_path: str = Field(DEFAULT_DB_PATH, description="Đường dẫn file SQLite để lưu lịch sử")

    # Debug chi tiết
    diagnose: bool = Field(False)

    if _PD_V2:
        model_config = ConfigDict(extra="ignore")
    else:
        class Config:  # type: ignore
            extra = "ignore"

router = APIRouter()

@router.get("/v1/search/history")
def get_history(
    profile: Optional[str] = Query(None),
    site: Optional[str] = Query(None),
    title: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db_path: Optional[str] = Query(None, description="Override đường dẫn DB (tuỳ chọn)"),
):
    """Endpoint phụ để xem nhanh lịch sử đã lưu."""
    path = db_path or DEFAULT_DB_PATH
    try:
        rows = query_history(path, profile=profile, site=site, title=title, limit=limit, offset=offset)
        return {"count": len(rows), "rows": rows}
    except Exception as e:
        raise HTTPException(500, f"query_history_failed: {e}")


@router.post("/v1/search/click")
async def search_click(req: SearchClickReq):
    """
    Lần lượt ontop từng profile, chờ DOM/selector, click (Search), gõ & Enter,
    **chờ DOM 100% sau Enter**, (tuỳ chọn) chờ selector, rồi Follow: map SCREEN→CLIENT, poll & click.
    Sau cùng: lưu lịch sử vào SQLite (mỗi profile một record).
    """
    if not _is_windows():
        raise HTTPException(400, "Chức năng này chỉ hỗ trợ Windows (ontop & native input).")

    # Chuẩn bị DB nếu cần
    if req.persist_history:
        try:
            init_db(req.history_db_path)
        except Exception as e:
            # Không fail cả request nếu DB lỗi — chỉ log
            log.warning("init_db failed: %s", e)

    entry = _load_site_title_coords(req.coords_file, req.site, req.title)
    if not entry:
        raise HTTPException(404, f"Không tìm thấy toạ độ cho site='{req.site}', title='{req.title}' trong {req.coords_file}.")
    sx = entry.get("screenX"); sy = entry.get("screenY")
    if sx is None or sy is None:
        raise HTTPException(400, f"Entry không có screenX/screenY hợp lệ: {entry}")

    results: List[Dict[str, Any]] = []
    url_map = req.profile_urls or {}

    for prof in req.profiles:
        diag: Dict[str, Any] = {"profile": prof}
        profile_dir = Path(req.profiles_root) / prof
        if not profile_dir.exists():
            r = {"profile": prof, "ok": False, "error": "profile_dir_missing"}
            if req.diagnose: r["diag"] = diag
            results.append(r)

            # Lưu history (lỗi profile_dir_missing)
            if req.persist_history:
                try:
                    insert_history(req.history_db_path, {
                        "site": req.site, "title": req.title, "follow_title": None,
                        "profile": prof, "nav_url": url_map.get(prof),
                        "used_coords": None, "screenX": sx, "screenY": sy, "cursorX": None, "cursorY": None,
                        "clicked": False, "ok": False, "error": "profile_dir_missing",
                        "dom_ready": False, "selector_ok": False, "active_is_input_q": False,
                        "typed": False, "typed_text": None, "pressed_enter": False,
                        "dom_ready_after_enter": False,
                        "follow_clicked": False, "follow_clicked_via": [], "follow_forced": False,
                        "follow_text": None, "follow_aria": None, "follow_e2e": None, "follow_should_click": False,
                        "follow_map": None,
                        "result_json": r
                    })
                except Exception as e:
                    log.warning("insert_history failed: %s", e)
            continue

        # 1) CDP target
        page_ws = await _get_first_page_ws(profile_dir, req.host, diag)
        if not page_ws:
            r = {"profile": prof, "ok": False, "error": "devtools_not_ready"}
            if req.diagnose: r["diag"] = diag
            results.append(r)

            if req.persist_history:
                try:
                    insert_history(req.history_db_path, {
                        "site": req.site, "title": req.title, "follow_title": None,
                        "profile": prof, "nav_url": url_map.get(prof),
                        "used_coords": None, "screenX": sx, "screenY": sy, "cursorX": None, "cursorY": None,
                        "clicked": False, "ok": False, "error": "devtools_not_ready",
                        "dom_ready": False, "selector_ok": False, "active_is_input_q": False,
                        "typed": False, "typed_text": None, "pressed_enter": False,
                        "dom_ready_after_enter": False,
                        "follow_clicked": False, "follow_clicked_via": [], "follow_forced": False,
                        "follow_text": None, "follow_aria": None, "follow_e2e": None, "follow_should_click": False,
                        "follow_map": None,
                        "result_json": r
                    })
                except Exception as e:
                    log.warning("insert_history failed: %s", e)
            continue

        # 2) Điều hướng (tuỳ chọn)
        nav_url = url_map.get(prof); navigated = None
        if nav_url:
            navigated = await _navigate_page_ws(page_ws, nav_url, req.wait_after_nav_ms)
        diag["navigated"] = navigated; diag["nav_url"] = nav_url

        # 3) Waits (trước click Search)
        dom_ok = sel_ok = None
        if req.wait_for_dom_complete:
            t0 = time.time(); dom_ok = await _wait_document_complete(page_ws, req.dom_complete_timeout_ms)
            diag["dom_ready_ok"] = dom_ok; diag["dom_ready_ms"] = int((time.time()-t0)*1000)
        if req.wait_selector:
            t1 = time.time()
            sel_ok = await _wait_selector(page_ws, req.wait_selector, req.selector_timeout_ms, 200, req.selector_visibility)
            diag["selector_ok"] = sel_ok; diag["selector"] = req.wait_selector
            diag["selector_visibility"] = req.selector_visibility; diag["selector_ms"] = int((time.time()-t1)*1000)

        # 4) Toạ độ (Search)
        if req.use_raw_screen_coords:
            cx = int(round(float(sx))) + int(req.offset_x)
            cy = int(round(float(sy))) + int(req.offset_y)
            coords_mode = "screen_raw"
        else:
            dpr = 1.0
            try:
                async with websockets.connect(page_ws) as ws_page:
                    await ws_page.send(json.dumps({
                        "id": 9001, "method": "Runtime.evaluate",
                        "params": {"expression": "window.devicePixelRatio || 1", "returnByValue": True}
                    }))
                    for _ in range(20):
                        msg = await asyncio.wait_for(ws_page.recv(), timeout=0.6)
                        data = json.loads(msg)
                        if data.get("id") == 9001:
                            dpr = float(data["result"]["result"]["value"] or 1.0); break
            except Exception:
                dpr = float(req.dpr or 1.0)
            cx = int(round(float(sx) * dpr)) + int(req.offset_x)
            cy = int(round(float(sy) * dpr)) + int(req.offset_y)
            coords_mode = "device_scaled"
            diag["dpr_used"] = dpr
        diag["coords_mode"] = coords_mode; diag["cursorX"] = cx; diag["cursorY"] = cy

        # 5) Ontop
        pid = None; port = diag.get("port_final")
        if isinstance(port, int): pid = _pid_from_port_windows(port)
        diag["pid_from_port"] = pid
        hwnd = None
        try:
            if pid:
                hwnd = _win_enum_windows_for_pid(pid); diag["hwnd"] = int(hwnd) if hwnd else None
                if hwnd: _win_bring_window_ontop(hwnd, duration_ms=req.topmost_ms); time.sleep(0.10)
        except Exception as e:
            log.warning("Bring ontop failed %s: %s", prof, e)

        # 6) Move + Click (Search)
        try:
            if req.move_mode == "sendinput_abs": _sendinput_move_absolute(cx, cy)
            else: _set_cursor_pos(cx, cy)

            if req.verify_move:
                t0 = time.time(); tol = max(0, req.verify_tolerance_px); ok_pos = False
                while (time.time()-t0)*1000.0 < req.verify_timeout_ms:
                    px, py = _get_cursor_pos()
                    if abs(px-cx) <= tol and abs(py-cy) <= tol: ok_pos = True; break
                    time.sleep(0.01)
                if not ok_pos: _set_cursor_pos(cx, cy); time.sleep(0.02)

            time.sleep(max(0, req.click_delay_ms)/1000.0)
            _sendinput_left_click()

            for _ in range(max(0, req.repeats-1)):
                time.sleep(max(0, req.interval_ms)/1000.0)
                if req.force_move_each_click:
                    if req.move_mode == "sendinput_abs": _sendinput_move_absolute(cx, cy)
                    else: _set_cursor_pos(cx, cy)
                    time.sleep(max(0, req.click_delay_ms)/1000.0)
                _sendinput_left_click()

            # 7) Gõ + Enter nếu input[name='q']
            typed = None; pressed_enter = None; active_is_q = None
            if req.type_if_input_q:
                await asyncio.sleep(max(0, req.type_delay_ms)/1000.0)
                active_is_q = await _is_active_input_q(page_ws, req.type_check_timeout_ms)
                if active_is_q:
                    typed, pressed_enter = await _type_into_active(
                        page_ws,
                        text=req.type_text,
                        mode=req.type_mode,
                        clear_before=req.type_clear_before,
                        key_interval_ms=req.key_interval_ms,
                        press_enter_after=req.press_enter_after,
                        enter_delay_ms=req.enter_delay_ms
                    )

            # 8) Wait sau Enter — BẮT BUỘC
            t2 = time.time()
            dom_ok_after = await _wait_document_complete(page_ws, req.after_enter_dom_timeout_ms)
            diag["dom_ready_after_enter_ok"] = dom_ok_after
            diag["dom_ready_after_enter_ms"] = int((time.time()-t2)*1000)
            if req.after_enter_extra_wait_ms > 0:
                await asyncio.sleep(req.after_enter_extra_wait_ms/1000.0)

            # 8b) (TUỲ CHỌN) chờ selector tổng quát cho bước Follow
            follow_sel_ok = None
            if req.follow_wait_selector:
                t3 = time.time()
                follow_sel_ok = await _wait_selector(page_ws, req.follow_wait_selector,
                                                     req.follow_selector_timeout_ms, 200,
                                                     req.follow_selector_visibility)
                diag["follow_selector"] = req.follow_wait_selector
                diag["follow_selector_ok"] = follow_sel_ok
                diag["follow_selector_ms"] = int((time.time()-t3)*1000)

            # 9) Bước Follow
            follow = _load_site_title_coords(req.coords_file, req.site, req.follow_title)
            follow_result: Dict[str, Any] = {"error": "follow_coords_not_found"}
            follow_clicked = False
            clicked_via: List[str] = []
            forced = False

            if follow:
                fx = int(follow.get("screenX")); fy = int(follow.get("screenY"))

                # move tới điểm follow
                if req.move_mode == "sendinput_abs": _sendinput_move_absolute(fx, fy)
                else: _set_cursor_pos(fx, fy)

                # verify pos
                if req.verify_move:
                    t4 = time.time(); tol = max(0, req.verify_tolerance_px); ok2 = False
                    while (time.time()-t4)*1000.0 < req.verify_timeout_ms:
                        px, py = _get_cursor_pos()
                        if abs(px-fx) <= tol and abs(py-fy) <= tol: ok2 = True; break
                        time.sleep(0.01)
                    if not ok2: _set_cursor_pos(fx, fy); time.sleep(0.02)

                # hover delay
                await asyncio.sleep(max(0, req.follow_hover_ms)/1000.0)

                # Re-ontop lại trước Follow (tránh mất focus)
                if hwnd and req.re_ontop_before_follow:
                    _win_bring_window_ontop(hwnd, duration_ms=min(600, req.topmost_ms))
                    time.sleep(0.05)

                # ====== MAPPING CHUẨN WINDOWS ======
                map_debug: Dict[str, Any] = {"screen": [fx, fy]}
                client_dev_x = client_dev_y = None
                if hwnd:
                    try:
                        cdx, cdy = _win_screen_to_client(hwnd, fx, fy)  # device px trong client area
                        client_dev_x, client_dev_y = int(cdx), int(cdy)
                        map_debug["client_dev"] = [client_dev_x, client_dev_y]
                    except Exception as e:
                        map_debug["client_dev_error"] = str(e)
                # DPR
                dpr_val = await _get_dpr(page_ws)
                map_debug["dpr"] = dpr_val
                client_css_x = client_css_y = None
                if client_dev_x is not None and dpr_val > 0:
                    client_css_x = client_dev_x / dpr_val
                    client_css_y = client_dev_y / dpr_val
                    map_debug["client_css"] = [client_css_x, client_css_y]
                # ====================================

                # ĐỢI tới khi button Follow xuất hiện đúng toạ độ
                if client_css_x is not None and client_css_y is not None:
                    check = await _wait_follow_button_at_client_css(
                        page_ws, client_css_x, client_css_y,
                        expect_text=req.follow_expect_text,
                        text_mode=req.follow_text_match,
                        case_insensitive=req.follow_case_insensitive,
                        regex_pattern=req.follow_regex,
                        require_e2e=req.follow_require_e2e,
                        e2e_value=req.follow_e2e_value,
                        timeout_ms=req.follow_appear_timeout_ms,
                        poll_ms=req.follow_appear_poll_ms
                    )
                else:
                    # Fallback: ước lượng từ JS nếu không lấy được hwnd/dpr
                    probe_expr = f"""
                    (()=>{{
                      const ABSX = {int(fx)}, ABSY = {int(fy)};
                      const sx=(window.screenX ?? window.screenLeft)||0;
                      const sy=(window.screenY ?? window.screenTop)||0;
                      const outerW=window.outerWidth||0, outerH=window.outerHeight||0;
                      const innerW=window.innerWidth||0, innerH=window.innerHeight||0;
                      const chromeW=Math.max(0, outerW-innerW);
                      const chromeH=Math.max(0, outerH-innerH);
                      const borderX=Math.round(chromeW/2);
                      const topBar=Math.max(0, chromeH-borderX);
                      let clientX=(ABSX - sx - borderX);
                      let clientY=(ABSY - sy - topBar);
                      if (window.visualViewport){{ clientX+=(window.visualViewport.offsetLeft||0); clientY+=(window.visualViewport.offsetTop||0); }}
                      return {{clientX,clientY}};
                    }})()
                    """
                    c_est = {"clientX": None, "clientY": None}
                    try:
                        async with websockets.connect(page_ws) as ws_est:
                            await ws_est.send(json.dumps({"id": 6110, "method": "Runtime.evaluate",
                                                          "params": {"expression": probe_expr, "returnByValue": True}}))
                            for _ in range(20):
                                msg = await asyncio.wait_for(ws_est.recv(), timeout=0.6)
                                data = json.loads(msg)
                                if data.get("id") == 6110:
                                    v = (data.get("result", {}).get("result", {}).get("value", {})) or {}
                                    c_est["clientX"] = v.get("clientX"); c_est["clientY"] = v.get("clientY"); break
                    except Exception:
                        pass
                    map_debug["client_css_fallback"] = [c_est.get("clientX"), c_est.get("clientY")]
                    check = await _wait_follow_button_at_client_css(
                        page_ws, float(c_est.get("clientX") or 0.0), float(c_est.get("clientY") or 0.0),
                        expect_text=req.follow_expect_text, text_mode=req.follow_text_match,
                        case_insensitive=req.follow_case_insensitive, regex_pattern=req.follow_regex,
                        require_e2e=req.follow_require_e2e, e2e_value=req.follow_e2e_value,
                        timeout_ms=req.follow_appear_timeout_ms, poll_ms=req.follow_appear_poll_ms
                    )

                follow_result = {**check, "map": map_debug, "strategy": req.follow_click_strategy}

                # CLICK theo strategy (hoặc Forced click)
                clicked_via = []
                if check.get("should_click"):
                    await asyncio.sleep(max(0, req.follow_click_delay_ms)/1000.0)

                    if req.follow_click_strategy in ("native", "both"):
                        _sendinput_left_click()
                        clicked_via.append("native")

                    if req.follow_click_strategy in ("dom", "both"):
                        cxp = check.get("clientX"); cyp = check.get("clientY")
                        if isinstance(cxp, (int,float)) and isinstance(cyp, (int,float)):
                            ok_dom = await _dom_click_button_at_client_point(page_ws, float(cxp), float(cyp))
                            if ok_dom: clicked_via.append("dom")

                    follow_clicked = len(clicked_via) > 0
                    await asyncio.sleep(max(0, req.follow_post_click_ms)/1000.0)

                elif req.follow_force_timeout_click:
                    # Hết timeout nhưng vẫn click tại điểm đã map
                    forced = True
                    await asyncio.sleep(max(0, req.follow_force_click_delay_ms)/1000.0)

                    if req.follow_force_click_strategy in ("native", "both"):
                        _sendinput_left_click()
                        clicked_via.append("native")

                    if req.follow_force_click_strategy in ("dom", "both"):
                        cxp = check.get("clientX"); cyp = check.get("clientY")
                        if not (isinstance(cxp,(int,float)) and isinstance(cyp,(int,float))):
                            # nếu không có từ check, lấy từ map_debug
                            css = map_debug.get("client_css") or map_debug.get("client_css_fallback")
                            if isinstance(css, list) and len(css) == 2:
                                cxp, cyp = css[0], css[1]
                        if isinstance(cxp,(int,float)) and isinstance(cyp,(int,float)):
                            ok_dom = await _dom_click_button_at_client_point(page_ws, float(cxp), float(cyp))
                            if ok_dom: clicked_via.append("dom")

                    follow_clicked = len(clicked_via) > 0
                    await asyncio.sleep(max(0, req.follow_post_click_ms)/1000.0)

            # Tổng hợp kết quả cho profile này
            r = {
                "profile": prof, "ok": True, "clicked": True,
                "used_coords": coords_mode, "screenX": sx, "screenY": sy,
                "cursorX": cx, "cursorY": cy, "navigated": navigated, "nav_url": nav_url,
                "dom_ready": dom_ok, "selector_ok": sel_ok,
                "active_is_input_q": active_is_q, "typed": bool(typed),
                "typed_text": (req.type_text if typed else None),
                "pressed_enter": bool(pressed_enter),
                "dom_ready_after_enter": dom_ok_after,
                "follow": {
                    "title": req.follow_title,
                    "clicked": follow_clicked,
                    "clicked_via": clicked_via,
                    "forced": forced,
                    "check": follow_result
                }
            }
            if req.diagnose: r["diag"] = diag
            results.append(r)

            # Lưu history
            if req.persist_history:
                try:
                    fr = r.get("follow", {}) or {}
                    fcheck = fr.get("check", {}) or {}
                    insert_history(req.history_db_path, {
                        "site": req.site,
                        "title": req.title,
                        "follow_title": fr.get("title"),
                        "profile": prof,
                        "nav_url": nav_url,
                        "used_coords": coords_mode,
                        "screenX": sx, "screenY": sy, "cursorX": cx, "cursorY": cy,
                        "clicked": True, "ok": True, "error": None,
                        "dom_ready": dom_ok, "selector_ok": sel_ok, "active_is_input_q": active_is_q,
                        "typed": bool(typed), "typed_text": r.get("typed_text"), "pressed_enter": bool(pressed_enter),
                        "dom_ready_after_enter": dom_ok_after,
                        "follow_clicked": fr.get("clicked"), "follow_clicked_via": fr.get("clicked_via"),
                        "follow_forced": fr.get("forced"),
                        "follow_text": fcheck.get("text"),
                        "follow_aria": fcheck.get("aria"),
                        "follow_e2e": fcheck.get("e2e"),
                        "follow_should_click": fcheck.get("should_click"),
                        "follow_map": fcheck.get("map"),
                        "result_json": r
                    })
                except Exception as e:
                    log.warning("insert_history failed: %s", e)

        except Exception as e:
            r = {
                "profile": prof, "ok": False, "error": str(e),
                "used_coords": coords_mode, "screenX": sx, "screenY": sy,
                "cursorX": cx, "cursorY": cy, "navigated": navigated, "nav_url": nav_url,
                "dom_ready": dom_ok, "selector_ok": sel_ok
            }
            if req.diagnose: r["diag"] = diag
            results.append(r)

            if req.persist_history:
                try:
                    insert_history(req.history_db_path, {
                        "site": req.site, "title": req.title, "follow_title": req.follow_title,
                        "profile": prof, "nav_url": nav_url,
                        "used_coords": coords_mode, "screenX": sx, "screenY": sy, "cursorX": cx, "cursorY": cy,
                        "clicked": False, "ok": False, "error": str(e),
                        "dom_ready": dom_ok, "selector_ok": sel_ok, "active_is_input_q": False,
                        "typed": False, "typed_text": None, "pressed_enter": False,
                        "dom_ready_after_enter": False,
                        "follow_clicked": False, "follow_clicked_via": [], "follow_forced": False,
                        "follow_text": None, "follow_aria": None, "follow_e2e": None, "follow_should_click": False,
                        "follow_map": None,
                        "result_json": r
                    })
                except Exception as e2:
                    log.warning("insert_history failed: %s", e2)

    return {
        "site": req.site, "title": req.title, "source_file": req.coords_file,
        "entry_ts": entry.get("ts"), "db_path": (req.history_db_path if req.persist_history else None),
        "count": len(results), "results": results
    }
