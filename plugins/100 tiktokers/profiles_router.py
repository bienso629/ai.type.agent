import os
import re
import json
import time
import random
import socket
import subprocess
import sqlite3         # <— NEW: cần cho include_accounts
from pathlib import Path
from typing import Any, Dict, List, Optional, Literal
from urllib.parse import urlparse, quote

import psutil
import requests
from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

# Optional: Win32 APIs for setting window titles (Windows only)
try:
    import win32gui, win32process  # type: ignore
except Exception:  # graceful fallback if pywin32 isn't installed
    win32gui = None
    win32process = None

# Optional: websocket client for Chrome DevTools Protocol
try:
    import websocket  # type: ignore
except Exception:
    websocket = None

router = APIRouter(prefix="/v1/opera/profiles", tags=["opera-profiles"])

# -------- Defaults --------
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PROFILES_ROOT = r"D:\\OperaProfiles"
DEFAULT_OPERA_PATHS = [
    r"C:\\Users\\%USERNAME%\\AppData\\Local\\Programs\\Opera\\opera.exe",
    r"C:\\Users\\%USERNAME%\\AppData\\Local\\Programs\\Opera GX\\opera.exe",
    r"C:\\Program Files\\Opera\\opera.exe",
    r"C:\\Program Files\\Opera GX\\opera.exe",
]

# -------- Utils --------
def _expand_vars(p: str) -> str:
    try:
        return os.path.expandvars(p)
    except Exception:
        return p


def _find_opera_exe(custom: Optional[str] = None) -> str:
    if custom and os.path.exists(custom):
        return custom
    for p in DEFAULT_OPERA_PATHS:
        pp = _expand_vars(p)
        if os.path.exists(pp):
            return pp
    return "opera.exe"


def _canon_path(p: str) -> str:
    try:
        p2 = os.path.abspath(p).replace('/', '\\')
        if p2.startswith('\\??\\UNC\\'):
            p2 = '\\\\' + p2[8:]
        elif p2.startswith('\\??\\'):
            p2 = p2[4:]
        return os.path.normcase(os.path.normpath(p2))
    except Exception:
        return (p or "").lower()


# --- Avatar helper ---
_AVATAR_EXTS = [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".ico"]


def _find_avatar_file(root: Path, profile_name: str) -> Optional[str]:
    """Return absolute path to avatar file if exists in root with same basename as profile."""
    try:
        for ext in _AVATAR_EXTS:
            fp = root / f"{profile_name}{ext}"
            if fp.exists() and fp.is_file():
                return str(fp)
            fp2 = root / f"{profile_name}{ext.upper()}"
            if fp2.exists() and fp2.is_file():
                return str(fp2)
        for p in root.glob(f"{profile_name}.*"):
            if p.is_file() and p.suffix.lower() in _AVATAR_EXTS:
                return str(p)
    except Exception:
        pass
    return None


# --- Window Title helpers (Windows) ---
def _iter_hwnds_for_pid(pid: int) -> List[int]:
    hwnds: List[int] = []
    if not win32gui or not win32process:
        return hwnds

    def _cb(hwnd, _):
        try:
            if win32gui.IsWindow(hwnd) and win32gui.IsWindowVisible(hwnd):
                _, p = win32process.GetWindowThreadProcessId(hwnd)
                if int(p) == int(pid):
                    hwnds.append(hwnd)
        except Exception:
            pass
        return True

    try:
        win32gui.EnumWindows(_cb, None)
    except Exception:
        return hwnds
    return hwnds


def _set_window_title_for_pid(pid: int, prefix: str, retries: int = 40, interval: float = 0.2) -> Dict[str, Any]:
    if not prefix:
        return {"ok": False, "detail": "empty_prefix"}
    if not win32gui or not win32process:
        return {"ok": False, "detail": "pywin32_not_available"}

    changed_total = 0
    windows_seen = 0
    last_err = None
    deadline = time.perf_counter() + retries * interval
    desired_prefix = f"{prefix} | "
    while time.perf_counter() < deadline:
        try:
            hwnds = _iter_hwnds_for_pid(pid)
            windows_seen = max(windows_seen, len(hwnds))
            for h in hwnds:
                try:
                    old = win32gui.GetWindowText(h) or ""
                    if not old.startswith(desired_prefix):
                        new = desired_prefix + old if old else prefix
                        win32gui.SetWindowText(h, new)
                        changed_total += 1
                except Exception as e:
                    last_err = e
        except Exception as e:
            last_err = e
        time.sleep(interval)

    return {
        "ok": changed_total > 0,
        "changed": changed_total,
        "windows": windows_seen,
        "detail": None if changed_total > 0 else f"last_err:{type(last_err).__name__ if last_err else 'none'}",
    }


# --- DevTools helpers for persistent title prefix ---

def _build_title_prefix_js(prefix: str) -> str:
    """
    JS cực bám để giữ prefix dù TikTok/SPA đổi tiêu đề theo mọi cách có thể.
    Chiến thuật:
      - Patch setter của document.title (shadow own accessor trên document)
      - Patch textContent cho HTMLTitleElement và Node (chỉ khi node là <title>)
      - Patch appendChild/replaceChild/insertBefore để chuẩn hoá mọi <title> mới
      - MutationObserver toàn bộ <head> + characterData
      - Hook pushState/replaceState/popstate + visibilitychange + load
      - rAF spam 8s đầu + setInterval 250ms lâu dài
    """
    p = json.dumps(prefix)
    return (
        "(function(prefix){"
        "try{"
        "var EXPECT = prefix + ' | ';"
        "function withPrefix(s){s=String(s||'');if(s.slice(0,EXPECT.length).toLowerCase()===EXPECT.toLowerCase())s=s.slice(EXPECT.length);return EXPECT + s;}"
        "function getTitleEl(){var el=document.querySelector('head>title');if(!el){el=document.createElement('title');(document.head||document.documentElement).appendChild(el);}return el;}"
        "function setTitleRaw(v){var el=getTitleEl();try{if(el.firstChild&&el.firstChild.nodeType===3){el.firstChild.nodeValue=String(v);}else{el.textContent=String(v);}}catch(e){el.textContent=String(v);}}"
        "function apply(){var cur=(document.title||getTitleEl().textContent||'');var want=withPrefix(cur);if(cur!==want){try{_setTitle(want);}catch(e){setTitleRaw(want);}}}"
        "var _desc=(Object.getOwnPropertyDescriptor(Document.prototype,'title')||Object.getOwnPropertyDescriptor(HTMLDocument.prototype,'title'));"
        "function _setTitle(v){if(_desc&&_desc.set){_desc.set.call(document,String(v));}else{setTitleRaw(v);}}"
        "// 1) Shadow accessor trên document để chặn mọi lần gán document.title"
        "try{Object.defineProperty(document,'title',{configurable:true,enumerable:true,"
        "get:function(){return _desc&&_desc.get?_desc.get.call(this):(getTitleEl().textContent||'');},"
        "set:function(v){_setTitle(withPrefix(v));}});}catch(e){}"
        "// 2) Patch textContent cho <title>"
        "function patchTextContent(proto){try{var d=Object.getOwnPropertyDescriptor(proto,'textContent');if(!d||!d.set)return;Object.defineProperty(proto,'textContent',{configurable:true,get:d.get,set:function(v){if(this&&this.tagName&&this.tagName.toLowerCase()==='title'){d.set.call(this,withPrefix(v));}else{d.set.call(this,v);}}});}catch(e){}}"
        "try{patchTextContent(HTMLTitleElement.prototype);}catch(e){}"
        "try{patchTextContent(Node.prototype);}catch(e){}"
        "// 3) Patch thao tác gắn node <title> vào DOM"
        "['appendChild','replaceChild','insertBefore'].forEach(function(fn){var o=Node.prototype[fn];if(!o)return;Node.prototype[fn]=function(a,b){try{if(a&&a.nodeType===1&&a.tagName&&a.tagName.toLowerCase()==='title'){if(a.textContent!=null)a.textContent=withPrefix(a.textContent);} }catch(_){} return o.apply(this,arguments);};});"
        "// 4) Observe toàn bộ head"
        "try{var head=document.head||document.getElementsByTagName('head')[0]||document.documentElement;new MutationObserver(function(muts){for(var i=0;i<muts.length;i++){var m=muts[i];if(m.type==='childList'){for(var j=0;j<m.addedNodes.length;j++){var n=m.addedNodes[j];if(n&&n.nodeType===1&&n.tagName&&n.tagName.toLowerCase()==='title'){try{n.textContent=withPrefix(n.textContent||'');}catch(_){}}}}else if(m.type==='characterData'){var el=m.target&&m.target.parentNode;if(el&&el.tagName&&el.tagName.toLowerCase()==='title'){try{el.textContent=withPrefix(el.textContent||'');}catch(_){}}}}apply();}).observe(head,{childList:true,subtree:true,characterData:true});}catch(e){}"
        "// 5) Hook SPA navigation"
        "['pushState','replaceState'].forEach(function(fn){var o=history[fn];if(o){history[fn]=function(){var r=o.apply(this,arguments);setTimeout(apply,0);return r;};}});"
        "window.addEventListener('popstate',function(){setTimeout(apply,0);});"
        "document.addEventListener('visibilitychange',function(){if(!document.hidden)setTimeout(apply,0);});"
        "window.addEventListener('load',function(){setTimeout(apply,0);});"
        "// 6) Nhồi liên tục: 8s đầu dùng rAF, sau đó nhắc 250ms"
        "(function jam(){apply();var t0=window.__pf_t0||(window.__pf_t0=Date.now());if(Date.now()-t0<8000){try{requestAnimationFrame(jam);}catch(e){setTimeout(jam,50);}}})();"
        "setInterval(apply,250);"
        "apply();"
        "}catch(e){}"
        "})(" + p + ");"
    )


def _cdp_call(ws, msg: dict, timeout: float = 1.6):
    ws.settimeout(timeout)
    ws.send(json.dumps(msg))
    try:
        return json.loads(ws.recv())
    except Exception:
        return None


def _cdp_add_script_on_new_document(ws_url: str, source: str, timeout: float = 1.6) -> Dict[str, Any]:
    """Connect via WebSocket with a safe Origin to bypass Chromium's strict origin checks.
    Works even if the browser was launched without --remote-allow-origins."""
    if websocket is None:
        return {"ok": False, "error": "websocket_client_not_installed"}
    try:
        # Use devtools://devtools origin which is allowed by Chromium by default
        ws = websocket.create_connection(ws_url, timeout=timeout, origin="devtools://devtools")
        _cdp_call(ws, {"id": 1, "method": "Page.enable"}, timeout)
        resp = _cdp_call(ws, {"id": 2, "method": "Page.addScriptToEvaluateOnNewDocument", "params": {"source": source}}, timeout)
        ws.close()
        ok = bool(resp) and ("result" in resp)
        ident = resp.get("result", {}).get("identifier") if resp else None
        return {"ok": ok, "identifier": ident}
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def _cdp_eval(ws_url: str, expression: str, timeout: float = 1.6) -> Dict[str, Any]:
    if websocket is None:
        return {"ok": False, "error": "websocket_client_not_installed"}
    try:
        # Use devtools origin to avoid 403 Forbidden on handshake
        ws = websocket.create_connection(ws_url, timeout=timeout, origin="devtools://devtools")
        _cdp_call(ws, {"id": 1, "method": "Runtime.enable"}, timeout)
        resp = _cdp_call(ws, {"id": 2, "method": "Runtime.evaluate", "params": {"expression": expression, "returnByValue": True}}, timeout)
        ws.close()
        return {"ok": True, "resp": resp}
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def _apply_title_prefix_to_all_tabs(host: str, port: int, prefix: Optional[str]) -> Dict[str, Any]:
    if not prefix:
        return {"ok": False, "count": 0, "detail": "no_prefix"}
    tabs = _tabs_list(host, port)
    count = 0
    errors: List[Dict[str, Any]] = []
    js = _build_title_prefix_js(prefix)
    for t in tabs:
        if t.get("type") != "page":
            continue
        ws_url = t.get("webSocketDebuggerUrl")
        if not ws_url:
            continue
        add = _cdp_add_script_on_new_document(ws_url, js)
        evl = _cdp_eval(ws_url, js)
        if add.get("ok") or evl.get("ok"):
            count += 1
        else:
            errors.append({"id": t.get("id"), "error": add.get("error") or evl.get("error")})
    return {"ok": count > 0, "count": count, "errors": errors}


def _is_port_free(port: int, host: str = DEFAULT_HOST) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        try:
            s.bind((host, port))
            return True
        except Exception:
            return False


def _ensure_port(p: Optional[int], host: str = DEFAULT_HOST) -> int:
    if p is not None:
        return int(p)
    for _ in range(200):
        cand = random.randint(49160, 59990)
        if _is_port_free(cand, host):
            return cand
    return 49499


def _profile_dir(root: str, profile: str) -> Path:
    return Path(root) / profile


def _read_devtools_port(profile_dir: Path) -> Optional[int]:
    for rel in ["DevToolsActivePort", "Default/DevToolsActivePort"]:
        fp = profile_dir / rel
        try:
            if fp.exists():
                first = fp.read_text(encoding="utf-8", errors="ignore").splitlines()[0].strip()
                return int(first)
        except Exception:
            continue
    return None


def _extract_uddir_from_cmdline(cmd: List[str]) -> Optional[str]:
    if not cmd:
        return None
    s = " ".join(cmd)
    key = "--user-data-dir="
    i = s.lower().find(key)
    if i < 0:
        return None
    val = s[i + len(key):].strip()
    if val.startswith('"') or val.startswith("'"):
        q = val[0]
        j = val.find(q, 1)
        if j > 0:
            val = val[1:j]
    else:
        sp = val.find(" ")
        if sp > 0:
            val = val[:sp]
    return val


def _collect_pids_by_cmdline(root: str, image_names: List[str]) -> List[int]:
    root_c = _canon_path(root)
    lower_images = {n.lower() for n in image_names or []}
    pids: List[int] = []
    for p in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            name = (p.info.get("name") or "").lower()
            if name not in lower_images:
                continue
            udd = _extract_uddir_from_cmdline(p.info.get("cmdline") or [])
            if udd and _canon_path(udd).startswith(root_c):
                pids.append(p.pid)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return pids


def _taskkill_by_images(image_names: List[str]) -> Dict[str, Any]:
    stats = {"attempts": 0, "ok": 0, "errors": []}
    for img in image_names or []:
        try:
            r = subprocess.run(["taskkill", "/F", "/T", "/IM", img], capture_output=True, text=True, timeout=5)
            stats["attempts"] += 1
            if r.returncode in (0, 128, 255):
                stats["ok"] += 1
            else:
                stats["errors"].append({"image": img, "code": r.returncode, "out": r.stdout, "err": r.stderr})
        except Exception as e:
            stats["errors"].append({"image": img, "ex": f"{type(e).__name__}: {e}"})
    return stats


def _normalize_url(u: Optional[str]) -> str:
    s = (u or "").strip()
    if not s:
        return "about:blank"
    if re.match(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:', s):
        return s
    return f"https://{s}"


def _netloc(u: str) -> str:
    try:
        return urlparse(u).netloc.lower()
    except Exception:
        return ""


def _same_site(target: str, actual: str) -> bool:
    t = _netloc(target)
    if not t:
        return False
    a = _netloc(actual)
    return (a == t) or a.endswith("." + t)


def _devtools_ok(host: str, port: int) -> bool:
    try:
        r = requests.get(f"http://{host}:{port}/json/version", timeout=1.0)
        return r.ok
    except Exception:
        return False


def _tabs_list(host: str, port: int) -> List[Dict[str, Any]]:
    try:
        r = requests.get(f"http://{host}:{port}/json/list", timeout=1.2)
        if r.ok:
            v = r.json()
            return v if isinstance(v, list) else []
    except Exception:
        pass
    return []


def _activate_tab(host: str, port: int, tab_id: str) -> bool:
    try:
        r = requests.get(f"http://{host}:{port}/json/activate/{tab_id}", timeout=0.8)
        return r.ok
    except Exception:
        return False


def _find_tab_for_url(host: str, port: int, url: str) -> Optional[Dict[str, Any]]:
    target = _normalize_url(url)
    tabs = _tabs_list(host, port)
    for t in tabs:
        u = t.get("url") or ""
        if _same_site(target, u):
            return t
    return None


def _close_tabs(host: str, port: int, leave_one: bool, prefer_url: Optional[str] = None) -> Dict[str, Any]:
    tabs = _tabs_list(host, port)
    if not tabs:
        return {"closed": 0, "kept": None}

    keep_id: Optional[str] = None
    if leave_one:
        if prefer_url:
            t = _find_tab_for_url(host, port, prefer_url)
            keep_id = t.get("id") if t else None
        if not keep_id:
            for t in tabs:
                if t.get("type") == "page" and t.get("id"):
                    keep_id = t["id"]
                    break
            if not keep_id and tabs and tabs[0].get("id"):
                keep_id = tabs[0]["id"]

    closed = 0
    for t in tabs:
        tid = t.get("id")
        if not tid:
            continue
        if leave_one and keep_id and tid == keep_id:
            continue
        try:
            r = requests.get(f"http://{host}:{port}/json/close/{tid}", timeout=0.6)
            if r.ok:
                closed += 1
        except Exception:
            continue
    return {"closed": closed, "kept": keep_id}


def _open_tab_multi(host: str, port: int, url: str, activate: bool = True) -> Dict[str, Any]:
    normalized = _normalize_url(url)
    details: Dict[str, Any] = {"ok": False, "method": None, "tab_id": None, "final_url": None, "activated": False}

    def _find_new_tab() -> Optional[Dict[str, Any]]:
        t = _find_tab_for_url(host, port, normalized)
        if t:
            return t
        return None

    # Try 1: /json/new?{url}
    try:
        r1 = requests.get(f"http://{host}:{port}/json/new?{normalized}", timeout=1.5)
        if r1.ok:
            time.sleep(0.2)
            t = _find_new_tab()
            if t:
                details.update({"ok": True, "method": "GET /json/new?{url}", "tab_id": t.get("id"), "final_url": t.get("url")})
                if activate and t.get("id"):
                    details["activated"] = _activate_tab(host, port, t["id"])
                return details
    except Exception:
        pass

    # Try 2: /json/new?url={encoded}
    try:
        enc = quote(normalized, safe="")
        r2 = requests.get(f"http://{host}:{port}/json/new?url={enc}", timeout=1.5)
        if r2.ok:
            time.sleep(0.2)
            t = _find_new_tab()
            if t:
                details.update({"ok": True, "method": "GET /json/new?url={encoded}", "tab_id": t.get("id"), "final_url": t.get("url")})
                if activate and t.get("id"):
                    details["activated"] = _activate_tab(host, port, t["id"])
                return details
    except Exception:
        pass

    # Try 3: POST /json/new {"url": "..."}
    try:
        r3 = requests.post(f"http://{host}:{port}/json/new", json={"url": normalized}, timeout=1.8)
        if r3.ok:
            time.sleep(0.2)
            t = _find_new_tab()
            if t:
                details.update({"ok": True, "method": "POST /json/new (json)", "tab_id": t.get("id"), "final_url": t.get("url")})
                if activate and t.get("id"):
                    details["activated"] = _activate_tab(host, port, t["id"])
                return details
    except Exception:
        pass

    return details


def _launch_opera(
    profile_dir: Path,
    port: int,
    opera_path: Optional[str],
    extra_args: Optional[List[str]],
    initial_url: Optional[str] = None,
    window_state: Literal["normal", "maximized", "fullscreen", "kiosk"] = "fullscreen",
    window_title_prefix: Optional[str] = None,
) -> Dict[str, Any]:
    exe = _find_opera_exe(opera_path)
    args = [
        exe,
        f"--user-data-dir={str(profile_dir)}",
        f"--remote-debugging-port={int(port)}",
        "--remote-debugging-address=127.0.0.1",
        "--remote-allow-origins=*",
        "--no-first-run",
        "--disable-background-networking",
        "--disable-features=Translate,BackgroundMode,ExtensionsToolbarMenu",
    ]

    ws = (window_state or "fullscreen").lower()
    if ws == "maximized":
        args.append("--start-maximized")
    elif ws == "fullscreen":
        args.append("--start-fullscreen")
    elif ws == "kiosk":
        args.append("--kiosk")

    if extra_args:
        args += extra_args

    if initial_url:
        args.append(_normalize_url(initial_url))

    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    title_info = None
    if window_title_prefix:
        try:
            title_info = _set_window_title_for_pid(proc.pid, window_title_prefix)
        except Exception:
            title_info = {"ok": False, "detail": "set_title_exception"}

    return {"pid": proc.pid, "port": port, "title": title_info}


# -------- Models --------
class StartRangeReq(BaseModel):
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    start: int
    end: int
    zero_pad: int = 3
    base_debug_port: Optional[int] = None
    opera_path: Optional[str] = None
    extra_args: Optional[List[str]] = None
    host: str = Field(DEFAULT_HOST)
    devtools_ready_timeout_ms: int = 5000
    close_tabs_on_start: bool = False
    leave_one_tab: bool = False
    new_tab_url: Optional[str] = None
    mode: Literal["skip", "reuse", "replace"] = "skip"
    update_cache: bool = True
    post_open_wait_ms: int = 0
    activate_opened_tab: bool = True
    window_state: Literal["normal", "maximized", "fullscreen", "kiosk"] = "fullscreen"
    # Title prefix options
    prefix_title_with_profile: bool = True
    title_prefix_text: Optional[str] = None  # supports placeholders {profile} / {PROFILE}
    title_prefix_apply_all_tabs: bool = True


class KillAllReq(BaseModel):
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    image_names: List[str] = Field(default_factory=lambda: [
        "opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"
    ])
    mode: Literal["by-cmdline", "taskkill-image", "hybrid"] = "taskkill-image"
    force: bool = True
    include_children: bool = True
    dry_run: bool = False
    timeout_ms: int = 200
    grace_ms: int = 100
    host: str = Field(DEFAULT_HOST)
    cache_action: Literal["leave", "prune", "clear"] = "prune"


class RangeReq(BaseModel):
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    start: int
    end: int
    zero_pad: int = 3
    host: str = Field(DEFAULT_HOST)


class KillRangeReq(RangeReq):
    cache_action: Literal["leave", "prune", "clear"] = "prune"


class OpenUrlsReq(RangeReq):
    urls: List[str]
    activate_opened_tab: bool = True
    # Optional: also enforce title prefix when just opening urls
    prefix_title_with_profile: bool = True
    title_prefix_text: Optional[str] = None
    title_prefix_apply_all_tabs: bool = True


class StartProfilesReq(BaseModel):
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    profiles: List[str] = Field(default_factory=list)
    indices: Optional[List[int]] = None
    zero_pad: int = 3
    base_debug_port: Optional[int] = None
    opera_path: Optional[str] = None
    extra_args: Optional[List[str]] = None
    host: str = Field(DEFAULT_HOST)
    devtools_ready_timeout_ms: int = 5000
    close_tabs_on_start: bool = False
    leave_one_tab: bool = False
    new_tab_url: Optional[str] = None
    mode: Literal["skip", "reuse", "replace"] = "skip"
    update_cache: bool = True
    post_open_wait_ms: int = 0
    activate_opened_tab: bool = True
    window_state: Literal["normal", "maximized", "fullscreen", "kiosk"] = "fullscreen"
    # Title prefix options
    prefix_title_with_profile: bool = True
    title_prefix_text: Optional[str] = None
    title_prefix_apply_all_tabs: bool = True


class KillProfilesReq(BaseModel):
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    profiles: List[str] = Field(default_factory=list)
    indices: Optional[List[int]] = None
    zero_pad: int = 3
    mode: Literal["force", "graceful"] = "force"
    host: str = Field(DEFAULT_HOST)
    cache_action: Literal["leave", "prune", "clear"] = "prune"


# -------- Cache helper --------
def _load_cached_ports_file(root: str) -> Dict[str, int]:
    f = Path(root) / ".devtools_ports.json"
    try:
        if f.exists():
            data = json.loads(f.read_text(encoding="utf-8"))
            out: Dict[str, int] = {}
            if isinstance(data, dict):
                for k, v in data.items():
                    try:
                        port = int(v)
                        if 1 <= port <= 65535:
                            out[str(k)] = port
                    except Exception:
                        continue
            return out
    except Exception:
        return {}
    return {}


def _handle_cache_action(profiles_root: str, host: str, action: str) -> Dict[str, Any]:
    cache_path = Path(profiles_root) / ".devtools_ports.json"
    details: Dict[str, Any] = {"action": action}
    try:
        if action == "clear":
            if cache_path.exists():
                cache_path.write_text("{}", encoding="utf-8")
            details["changed"] = True
        elif action == "prune":
            mapping: Dict[str, Any] = {}
            if cache_path.exists():
                try:
                    mapping = json.loads(cache_path.read_text(encoding="utf-8"))
                except Exception:
                    mapping = {}
            removed: List[str] = []
            if isinstance(mapping, dict):
                for name, port in list(mapping.items()):
                    try:
                        pi = int(port)
                    except Exception:
                        removed.append(name)
                        mapping.pop(name, None)
                        continue
                    if not _devtools_ok(host or DEFAULT_HOST, pi):
                        removed.append(name)
                        mapping.pop(name, None)
            cache_path.write_text(json.dumps(mapping, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
            details["removed"] = removed
            details["changed"] = True
        else:
            details["changed"] = False
    except Exception as e:
        details["error"] = f"{type(e).__name__}: {e}"
    return details


# -------- LIST (GET) --------
@router.get("/list")
def list_profiles(
    profiles_root: str = Query(DEFAULT_PROFILES_ROOT),
    host: str = Query(DEFAULT_HOST),
    use_cache: bool = Query(True),
    verify: bool = Query(False),
    verify_timeout_ms: int = Query(200, ge=1, le=5000),
    include_pids: bool = Query(False),
    include_ports: bool = Query(True),
    include_all: bool = Query(False, description="Liệt kê cả folder lạ (không đúng pattern ProfileNNN/Default)"),
    filter_: Literal["all", "running", "stopped"] = Query("all", alias="filter"),
    # tìm kiếm + phân trang + sắp xếp
    q: Optional[str] = Query(None, description="Tìm theo tên profile (substring, case-insensitive)"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    order_by: Literal["profile", "running", "port"] = Query("profile"),
    order_dir: Literal["asc", "desc"] = Query("asc"),
    include_total: bool = Query(True),
    # gắn accounts từ .accounts.db (chỉ khi cần)
    include_accounts: bool = Query(False, description="Gắn danh sách accounts theo profile từ SQLite"),
    only_active_accounts: bool = Query(True, description="Chỉ lấy accounts active khi include_accounts=true"),
    accounts_db_path: Optional[str] = Query(None, description="Đường dẫn .db; mặc định <profiles_root>/.accounts.db"),
    # Lọc danh sách ACCOUNTS hiển thị theo nền tảng; KHÔNG loại profile
    platform: Literal["all", "tiktok", "facebook"] = Query("all"),
) -> Dict[str, Any]:
    root_path = Path(profiles_root)
    if not root_path.exists():
        return {"ok": True, "root": str(root_path), "count": 0, "total": 0, "results": []}

    host_use = host or DEFAULT_HOST

    def _canon_profile(name: str) -> str:
        # Chuẩn hoá về ProfileNNN (nếu khớp pattern)
        m = re.fullmatch(r"(?i)profile0*([0-9]+)", name.strip())
        if m:
            return f"Profile{int(m.group(1)):03d}"
        return name.strip()

    def _sorted_names(seq):
        def _key(name: str):
            m = re.fullmatch(r"Profile0*([0-9]+)", name, flags=re.IGNORECASE)
            if m:
                return (0, int(m.group(1)), name.lower())
            return (1, 0, name.lower())
        names = list(seq)
        names.sort(key=_key)
        return names

    # Liệt kê tên profile
    entries = [d for d in root_path.iterdir() if d.is_dir()]
    if include_all:
        names = [d.name for d in entries]
    else:
        _padded = re.compile(r"^Profile\d{3}$", re.IGNORECASE)
        names = [d.name for d in entries if (d.name == "Default") or _padded.fullmatch(d.name)]
    names = _sorted_names(names)

    # Tìm kiếm theo q
    if q:
        q_low = q.lower()
        names = [n for n in names if q_low in n.lower()]

    cache = _load_cached_ports_file(str(root_path)) if use_cache else {}

    # ===== Nạp accounts_map chỉ khi cần gắn accounts =====
    need_accounts = include_accounts
    accounts_map: Dict[str, List[Dict[str, Any]]] = {}
    accounts_error: Optional[str] = None
    accounts_db_used: Optional[str] = None

    if need_accounts:
        dbfile = Path(accounts_db_path) if accounts_db_path else (root_path / ".accounts.db")
        accounts_db_used = str(dbfile)
        try:
            if dbfile.exists():
                conn = sqlite3.connect(str(dbfile))
                conn.row_factory = sqlite3.Row
                where = "WHERE active=1" if only_active_accounts else ""
                cur = conn.execute(
                    f"SELECT id, platform, email, alias, note, profiles_json, active FROM accounts {where}"
                )
                rows = cur.fetchall()
                conn.close()
                for r in rows:
                    try:
                        profs = json.loads(r["profiles_json"] or "[]")
                    except Exception:
                        profs = []
                    acct = {
                        "id": int(r["id"]),
                        "platform": str(r["platform"]),
                        "email": str(r["email"]),
                        "alias": r["alias"],
                        "note": r["note"],
                        "active": bool(r["active"]),
                    }
                    for p in profs:
                        if isinstance(p, str) and p.strip():
                            cp = _canon_profile(p)
                            accounts_map.setdefault(cp.lower(), []).append(acct)
            else:
                accounts_error = f"db_not_found: {dbfile}"
        except Exception as e:
            accounts_error = f"{type(e).__name__}: {e}"

    rows_out: List[Dict[str, Any]] = []

    for name in names:
        pdir = root_path / name
        info: Dict[str, Any] = {"profile": name, "dir": str(pdir)}

        # avatar (nếu có)
        avatar_path = _find_avatar_file(root_path, name)
        info["avatar"] = avatar_path

        # Đọc port (dù include_ports=False vẫn cần để xác định trạng thái/sort)
        port_candidate: Optional[int] = None
        try:
            if name in cache:
                port_candidate = int(cache.get(name))
        except Exception:
            port_candidate = None
        if port_candidate is None:
            port_candidate = _read_devtools_port(pdir)

        if include_ports and port_candidate is not None:
            info["devtools_port"] = int(port_candidate)

        # running?
        running = False
        if verify and port_candidate:
            try:
                r = requests.get(f"http://{host_use}:{port_candidate}/json/version", timeout=verify_timeout_ms / 1000.0)
                running = bool(r.ok)
            except Exception:
                running = False
        else:
            running = bool(port_candidate)

        # Áp dụng filter chạy/tắt
        if filter_ == "running" and not running:
            continue
        if filter_ == "stopped" and running:
            continue

        info["running"] = running

        # PIDs nếu cần
        if include_pids:
            pids = _collect_pids_by_cmdline(
                str(pdir),
                ["opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"],
            )
            if pids:
                info["pids"] = sorted(set(int(x) for x in pids))

        # Gắn accounts (lọc theo platform CHỈ TRONG DANH SÁCH ACCOUNTS, không loại profile)
        if include_accounts and need_accounts:
            key = _canon_profile(name).lower()
            accts = accounts_map.get(key, [])
            if platform != "all":
                accts = [a for a in accts if a.get("platform") == platform]
            info["accounts"] = accts

        rows_out.append(info)

    # Sắp xếp
    reverse = (order_dir.lower() == "desc")

    def _num_from_profile(prof: str) -> int:
        m = re.fullmatch(r"Profile0*([0-9]+)", prof, flags=re.IGNORECASE)
        return int(m.group(1)) if m else 10**9  # để Default/khác xuống cuối khi asc

    if order_by == "profile":
        rows_out.sort(key=lambda r: (_num_from_profile(r["profile"]), r["profile"].lower()), reverse=reverse)
    elif order_by == "running":
        rows_out.sort(key=lambda r: (not bool(r.get("running")), r["profile"].lower()), reverse=reverse)
    elif order_by == "port":
        rows_out.sort(key=lambda r: (int(r.get("devtools_port") or -1), r["profile"].lower()), reverse=reverse)
    else:
        rows_out.sort(key=lambda r: (_num_from_profile(r["profile"]), r["profile"].lower()), reverse=reverse)

    total = len(rows_out)
    page_rows = rows_out[offset: offset + limit]

    resp: Dict[str, Any] = {
        "ok": True,
        "root": str(root_path),
        "count": len(page_rows),
        "total": total if include_total else None,
        "limit": limit,
        "offset": offset,
        "order_by": order_by,
        "order_dir": order_dir,
        "results": page_rows,
    }
    if include_accounts and accounts_error:
        resp["accounts_error"] = accounts_error
    if include_accounts:
        resp["accounts_db_path_used"] = accounts_db_used
    return resp


# -------- START RANGE --------
@router.post("/start-range")
def start_range(req: StartRangeReq) -> Dict[str, Any]:
    root = req.profiles_root
    zero = int(req.zero_pad)
    host = req.host or DEFAULT_HOST
    timeout_s = max(0.1, req.devtools_ready_timeout_ms / 1000.0)

    cache = _load_cached_ports_file(root)
    results: List[Dict[str, Any]] = []

    def _wait_ready(port: int, deadline: float) -> bool:
        while time.perf_counter() < deadline:
            if _devtools_ok(host, port):
                return True
            time.sleep(0.05)
        return _devtools_ok(host, port)

    def _make_prefix(profile_name: str) -> Optional[str]:
        if req.title_prefix_text:
            txt = str(req.title_prefix_text)
            return txt.replace("{profile}", profile_name).replace("{PROFILE}", profile_name)
        if req.prefix_title_with_profile:
            return profile_name
        return None

    for i in range(int(req.start), int(req.end) + 1):
        prof = f"Profile{str(i).zfill(zero)}"
        pdir = _profile_dir(root, prof)
        pdir.mkdir(parents=True, exist_ok=True)

        existing_port = cache.get(prof) or _read_devtools_port(pdir)
        is_running = bool(existing_port) and _devtools_ok(host, int(existing_port))

        open_result: Dict[str, Any] = {}

        def _pick_port(idx: int) -> int:
            base = req.base_debug_port if (req.base_debug_port and req.base_debug_port > 0) else None
            if base is None:
                return _ensure_port(None, host)
            return int(base) + idx

        launched_new = False
        use_port: int
        info: Dict[str, Any] = {}

        if req.mode == "skip" and is_running:
            use_port = int(existing_port)
        elif req.mode == "replace" and is_running:
            pids = _collect_pids_by_cmdline(str(pdir), ["opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"])
            for pid in pids:
                try:
                    psutil.Process(pid).terminate()
                except Exception:
                    pass
            time.sleep(0.2)
            use_port = _pick_port(i - int(req.start))
            info = _launch_opera(
                pdir, int(use_port), req.opera_path, req.extra_args,
                initial_url=req.new_tab_url, window_state=req.window_state,
                window_title_prefix=prof if req.prefix_title_with_profile or req.title_prefix_text else None,
            )
            launched_new = True
        elif req.mode == "reuse" and existing_port and not is_running:
            use_port = int(existing_port)
            info = _launch_opera(
                pdir, int(use_port), req.opera_path, req.extra_args,
                initial_url=req.new_tab_url, window_state=req.window_state,
                window_title_prefix=prof if req.prefix_title_with_profile or req.title_prefix_text else None,
            )
            launched_new = True
        elif not is_running:
            use_port = _pick_port(i - int(req.start))
            info = _launch_opera(
                pdir, int(use_port), req.opera_path, req.extra_args,
                initial_url=req.new_tab_url, window_state=req.window_state,
                window_title_prefix=prof if req.prefix_title_with_profile or req.title_prefix_text else None,
            )
            launched_new = True
        else:
            use_port = int(existing_port)

        ready = _wait_ready(int(use_port), time.perf_counter() + timeout_s)

        if ready and req.new_tab_url:
            if launched_new:
                t = _find_tab_for_url(host, int(use_port), req.new_tab_url)
                if t and t.get("id") and req.activate_opened_tab:
                    _activate_tab(host, int(use_port), t["id"])
            else:
                open_result = _open_tab_multi(host, int(use_port), req.new_tab_url, activate=req.activate_opened_tab)

        if ready and req.close_tabs_on_start:
            _ = _close_tabs(host, int(use_port), leave_one=req.leave_one_tab, prefer_url=req.new_tab_url)

        if ready:
            cache[prof] = int(use_port)

        # Apply CDP title prefix persistently to all page tabs
        title_prefix = _make_prefix(prof)
        title_apply = None
        if ready and req.title_prefix_apply_all_tabs and title_prefix:
            title_apply = _apply_title_prefix_to_all_tabs(host, int(use_port), title_prefix)

        if req.post_open_wait_ms > 0:
            time.sleep(req.post_open_wait_ms / 1000.0)

        results.append({
            "profile": prof,
            "dir": str(pdir),
            "pid": None if not launched_new else info.get("pid"),
            "port": int(use_port),
            "launched_new": launched_new,
            "devtools_ready": ready,
            "opened": bool(open_result.get("ok")) if open_result else (req.new_tab_url is not None and launched_new),
            "open_result": open_result or None,
            "window_state": req.window_state,
            "closed_tabs": req.close_tabs_on_start,
            "leave_one_tab": req.leave_one_tab,
            "title_prefix": title_prefix,
            "title_applied": title_apply,
        })

    if req.update_cache:
        try:
            (Path(root) / ".devtools_ports.json").write_text(
                json.dumps(cache, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
        except Exception:
            pass

    return {"count": len(results), "results": results}


# -------- START PROFILES --------
@router.post("/start-profiles")
def start_profiles(req: StartProfilesReq) -> Dict[str, Any]:
    root = req.profiles_root
    host = req.host or DEFAULT_HOST
    timeout_s = max(0.1, req.devtools_ready_timeout_ms / 1000.0)

    names: List[str] = []
    if req.profiles:
        names += [str(x).strip() for x in req.profiles if str(x).strip()]
    if req.indices:
        z = int(req.zero_pad)
        names += [f"Profile{str(i).zfill(z)}" for i in req.indices]

    seen = set()
    ordered: List[str] = []
    for n in names:
        if n not in seen:
            seen.add(n)
            ordered.append(n)

    if not ordered:
        return {"count": 0, "results": [], "detail": "empty_profiles"}

    cache = _load_cached_ports_file(root)
    results: List[Dict[str, Any]] = []

    def _wait_ready(port: int, deadline: float) -> bool:
        while time.perf_counter() < deadline:
            if _devtools_ok(host, port):
                return True
            time.sleep(0.05)
        return _devtools_ok(host, port)

    def _pick_port(idx: int) -> int:
        base = req.base_debug_port if (req.base_debug_port and req.base_debug_port > 0) else None
        if base is None:
            return _ensure_port(None, host)
        return int(base) + idx

    def _make_prefix(profile_name: str) -> Optional[str]:
        if req.title_prefix_text:
            txt = str(req.title_prefix_text)
            return txt.replace("{profile}", profile_name).replace("{PROFILE}", profile_name)
        if req.prefix_title_with_profile:
            return profile_name
        return None

    for idx, prof in enumerate(ordered):
        pdir = _profile_dir(root, prof)
        pdir.mkdir(parents=True, exist_ok=True)

        existing_port = cache.get(prof) or _read_devtools_port(pdir)
        is_running = bool(existing_port) and _devtools_ok(host, int(existing_port))

        launched_new = False
        use_port: int
        info: Dict[str, Any] = {}
        open_result: Dict[str, Any] = {}

        if req.mode == "skip" and is_running:
            use_port = int(existing_port)
        elif req.mode == "replace" and is_running:
            pids = _collect_pids_by_cmdline(str(pdir), ["opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"])
            for pid in pids:
                try:
                    psutil.Process(pid).terminate()
                except Exception:
                    pass
            time.sleep(0.2)
            use_port = _pick_port(idx)
            info = _launch_opera(
                pdir, int(use_port), req.opera_path, req.extra_args,
                initial_url=req.new_tab_url, window_state=req.window_state,
                window_title_prefix=prof if req.prefix_title_with_profile or req.title_prefix_text else None,
            )
            launched_new = True
        elif req.mode == "reuse" and existing_port and not is_running:
            use_port = int(existing_port)
            info = _launch_opera(
                pdir, int(use_port), req.opera_path, req.extra_args,
                initial_url=req.new_tab_url, window_state=req.window_state,
                window_title_prefix=prof if req.prefix_title_with_profile or req.title_prefix_text else None,
            )
            launched_new = True
        elif not is_running:
            use_port = _pick_port(idx)
            info = _launch_opera(
                pdir, int(use_port), req.opera_path, req.extra_args,
                initial_url=req.new_tab_url, window_state=req.window_state,
                window_title_prefix=prof if req.prefix_title_with_profile or req.title_prefix_text else None,
            )
            launched_new = True
        else:
            use_port = int(existing_port)

        ready = _wait_ready(int(use_port), time.perf_counter() + timeout_s)

        if ready and req.new_tab_url:
            if launched_new:
                t = _find_tab_for_url(host, int(use_port), req.new_tab_url)
                if t and t.get("id") and req.activate_opened_tab:
                    _activate_tab(host, int(use_port), t["id"])
            else:
                open_result = _open_tab_multi(host, int(use_port), req.new_tab_url, activate=req.activate_opened_tab)

        if ready and req.close_tabs_on_start:
            _ = _close_tabs(host, int(use_port), leave_one=req.leave_one_tab, prefer_url=req.new_tab_url)

        if ready:
            cache[prof] = int(use_port)

        title_prefix = _make_prefix(prof)
        title_apply = None
        if ready and req.title_prefix_apply_all_tabs and title_prefix:
            title_apply = _apply_title_prefix_to_all_tabs(host, int(use_port), title_prefix)

        if req.post_open_wait_ms > 0:
            time.sleep(req.post_open_wait_ms / 1000.0)

        results.append({
            "profile": prof,
            "dir": str(pdir),
            "pid": None if not launched_new else info.get("pid"),
            "port": int(use_port),
            "launched_new": launched_new,
            "devtools_ready": ready,
            "opened": bool(open_result.get("ok")) if open_result else (req.new_tab_url is not None and launched_new),
            "open_result": open_result or None,
            "window_state": req.window_state,
            "closed_tabs": req.close_tabs_on_start,
            "leave_one_tab": req.leave_one_tab,
            "title_prefix": title_prefix,
            "title_applied": title_apply,
        })

    if req.update_cache:
        try:
            (Path(root) / ".devtools_ports.json").write_text(
                json.dumps(cache, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
        except Exception:
            pass

    return {"count": len(results), "results": results}


# -------- KILL ALL --------
@router.post("/kill-all")
def kill_all(req: KillAllReq) -> Dict[str, Any]:
    t0 = time.perf_counter()
    killed: List[int] = []
    failed: List[int] = []
    details: Dict[str, Any] = {"mode": req.mode}

    if req.mode in ("taskkill-image", "hybrid"):
        if req.dry_run:
            dt = (time.perf_counter() - t0) * 1000
            return {"ok": True, "dry_run": True, "images": req.image_names, "time_ms": int(dt)}
        details["taskkill"] = _taskkill_by_images(req.image_names)

    if req.mode in ("by-cmdline", "hybrid"):
        pids = _collect_pids_by_cmdline(req.profiles_root, req.image_names)
        details["match_by_cmdline"] = {"count": len(pids), "pids_preview": pids[:50] + (["..."] if len(pids) > 50 else [])}
        if req.dry_run:
            dt = (time.perf_counter() - t0) * 1000
            return {"ok": True, "dry_run": True, "targets": pids, "time_ms": int(dt)}

        uniq = sorted(set(pid for pid in pids if pid > 0))
        procs: List[psutil.Process] = []
        for pid in uniq:
            try:
                p = psutil.Process(pid)
                procs.append(p)
                if req.include_children:
                    procs += p.children(recursive=True)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        seen = set(); procs2 = []
        for p in procs:
            if p.pid not in seen:
                seen.add(p.pid); procs2.append(p)
        for p in procs2:
            try:
                p.terminate()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        _, alive = psutil.wait_procs(procs2, timeout=max(0.05, req.timeout_ms / 1000.0))
        if req.force and alive:
            for p in alive:
                try:
                    p.kill()
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            _, alive2 = psutil.wait_procs(alive, timeout=max(0.05, req.grace_ms / 1000.0))
            alive = alive2
        for p in procs2:
            try:
                if not p.is_running():
                    killed.append(p.pid)
                else:
                    failed.append(p.pid)
            except psutil.NoSuchProcess:
                killed.append(p.pid)

    cache = _handle_cache_action(req.profiles_root, req.host, req.cache_action)

    dt = (time.perf_counter() - t0) * 1000
    return {
        "ok": True,
        "time_ms": int(dt),
        "used_mode": req.mode,
        "killed": sorted(set(killed)),
        "failed": sorted(set(failed)),
        "details": details,
        "cache": cache,
    }


# -------- KILL RANGE --------
@router.post("/kill-range")
def kill_range(req: KillRangeReq) -> Dict[str, Any]:
    previews: List[int] = []
    for i in range(int(req.start), int(req.end) + 1):
        prof = f"Profile{str(i).zfill(int(req.zero_pad))}"
        pdir = _profile_dir(req.profiles_root, prof)
        pids = _collect_pids_by_cmdline(str(pdir), ["opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"])
        previews += pids
    if not previews:
        cache = _handle_cache_action(req.profiles_root, req.host, req.cache_action)
        return {"ok": True, "killed": [], "failed": [], "detail": "no_match", "cache": cache}

    killed: List[int] = []
    failed: List[int] = []
    uniq = sorted(set(previews))
    procs: List[psutil.Process] = []
    for pid in uniq:
        try:
            p = psutil.Process(pid)
            procs.append(p)
            procs += p.children(recursive=True)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    seen = set(); procs2: List[psutil.Process] = []
    for p in procs:
        if p.pid not in seen:
            seen.add(p.pid)
            procs2.append(p)
    for p in procs2:
        try:
            p.terminate()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    _, alive = psutil.wait_procs(procs2, timeout=0.2)
    for p in alive:
        try:
            p.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    _, alive2 = psutil.wait_procs(alive, timeout=0.1)
    for p in procs2:
        try:
            if not p.is_running():
                killed.append(p.pid)
            else:
                failed.append(p.pid)
        except psutil.NoSuchProcess:
            killed.append(p.pid)

    cache = _handle_cache_action(req.profiles_root, req.host, req.cache_action)

    return {"ok": True, "killed": sorted(set(killed)), "failed": sorted(set(failed)), "cache": cache}


# -------- KILL PROFILES --------
@router.post("/kill-profiles")
def kill_profiles(req: KillProfilesReq) -> Dict[str, Any]:
    names: List[str] = []
    if req.profiles:
        names += [str(x).strip() for x in req.profiles if str(x).strip()]
    if req.indices:
        z = int(req.zero_pad)
        names += [f"Profile{str(i).zfill(z)}" for i in req.indices]

    seen = set()
    ordered: List[str] = []
    for n in names:
        if n not in seen:
            seen.add(n); ordered.append(n)

    if not ordered:
        cache = _handle_cache_action(req.profiles_root, req.host, req.cache_action)
        return {"ok": True, "results": [], "detail": "empty_profiles", "cache": cache}

    host = req.host or DEFAULT_HOST
    cache_map = _load_cached_ports_file(req.profiles_root)
    results: List[Dict[str, Any]] = []

    if req.mode == "graceful":
        for name in ordered:
            pdir = _profile_dir(req.profiles_root, name)
            port = cache_map.get(name) or _read_devtools_port(pdir)
            if port and _devtools_ok(host, int(port)):
                try:
                    closed = _close_tabs(host, int(port), leave_one=False)
                    results.append({"profile": name, "ok": True, "action": "graceful", "detail": "tabs_closed", "closed": closed})
                except Exception as e:
                    results.append({"profile": name, "ok": False, "action": "graceful", "detail": f"error:{type(e).__name__}: {e}"})
            else:
                results.append({"profile": name, "ok": False, "action": "graceful", "detail": "port_unknown"})
        cache = _handle_cache_action(req.profiles_root, req.host, req.cache_action)
        return {"ok": True, "mode": "graceful", "results": results, "cache": cache}

    killed: List[int] = []; failed: List[int] = []
    for name in ordered:
        pdir = _profile_dir(req.profiles_root, name)
        pids = _collect_pids_by_cmdline(str(pdir), ["opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"])
        if not pids:
            results.append({"profile": name, "ok": False, "action": "force", "detail": "no_pids"})
            continue
        uniq = sorted(set(pids))
        procs: List[psutil.Process] = []
        for pid in uniq:
            try:
                p = psutil.Process(pid); procs.append(p); procs += p.children(recursive=True)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        seen = set(); procs2: List[psutil.Process] = []
        for p in procs:
            if p.pid not in seen:
                seen.add(p.pid); procs2.append(p)
        for p in procs2:
            try:
                p.terminate()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        _, alive = psutil.wait_procs(procs2, timeout=0.2)
        for p in alive:
            try:
                p.kill()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        _, alive2 = psutil.wait_procs(alive, timeout=0.1)
        ok = True
        for p in procs2:
            try:
                if p.is_running():
                    ok = False; failed.append(p.pid)
                else:
                    killed.append(p.pid)
            except psutil.NoSuchProcess:
                killed.append(p.pid)
        results.append({"profile": name, "ok": ok, "action": "force", "detail": f"terminated:{len(uniq)}" if ok else "partial"})
    cache = _handle_cache_action(req.profiles_root, req.host, req.cache_action)
    return {"ok": True, "mode": "force", "results": results, "killed_count": len(set(killed)), "cache": cache}


# -------- OPEN URLS --------
@router.post("/open-urls")
def open_urls(req: OpenUrlsReq) -> Dict[str, Any]:
    host = req.host or DEFAULT_HOST
    results: List[Dict[str, Any]] = []

    start = int(req.start); end = int(req.end); zero = int(req.zero_pad)
    normalized_urls = [_normalize_url(u) for u in req.urls]

    def _make_prefix(profile_name: str) -> Optional[str]:
        if req.title_prefix_text:
            txt = str(req.title_prefix_text)
            return txt.replace("{profile}", profile_name).replace("{PROFILE}", profile_name)
        if req.prefix_title_with_profile:
            return profile_name
        return None

    for i in range(start, end + 1):
        prof = f"Profile{str(i).zfill(zero)}"
        pdir = _profile_dir(req.profiles_root, prof)
        port = _read_devtools_port(pdir)
        if not port:
            results.append({"profile": prof, "ok": False, "detail": "no_devtools_port"})
            continue

        opened_any = False
        opened_list: List[Dict[str, Any]] = []

        for url in normalized_urls:
            try:
                rs = _open_tab_multi(host, int(port), url, activate=req.activate_opened_tab)
                opened_any = opened_any or bool(rs.get("ok"))
                opened_list.append({"url": url, **rs})
            except Exception as e:
                opened_list.append({"url": url, "ok": False, "error": f"{type(e).__name__}: {e}"})

        # Also apply persistent title prefix to all current tabs
        title_prefix = _make_prefix(prof)
        title_apply = None
        if title_prefix and req.title_prefix_apply_all_tabs:
            try:
                title_apply = _apply_title_prefix_to_all_tabs(host, int(port), title_prefix)
            except Exception:
                title_apply = {"ok": False, "detail": "apply_exception"}

        results.append({
            "profile": prof,
            "ok": opened_any,
            "port": int(port),
            "opened": opened_list,
            "title_prefix": title_prefix,
            "title_applied": title_apply,
        })

    return {"count": len(results), "results": results}
