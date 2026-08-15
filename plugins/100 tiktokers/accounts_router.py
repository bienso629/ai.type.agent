from pydantic import BaseModel, Field
import os
import re
import json
import time
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional, Literal

import requests
from fastapi import APIRouter, Query

# Thử dùng websocket-client cho CDP; nếu thiếu thì một số tính năng sẽ hạ cấp
try:
    import websocket  # type: ignore
except Exception:
    websocket = None  # type: ignore

# Tái sử dụng hạ tầng sẵn có từ profiles_router
from profiles_router import (  # type: ignore
    DEFAULT_HOST,
    DEFAULT_PROFILES_ROOT,
    _profile_dir,
    _load_cached_ports_file,
    _read_devtools_port,
    _devtools_ok,
    _tabs_list,
)

router = APIRouter(prefix="/v1/opera/accounts", tags=["opera-accounts"])

# ===== Cấu hình & hằng số =====
_TIKTOK_HOSTS = [
    ".tiktok.com",
    "tiktok.com",
    "www.tiktok.com",
    "m.tiktok.com",
]
_FACEBOOK_HOSTS = [
    ".facebook.com",
    "facebook.com",
    "www.facebook.com",
    "m.facebook.com",
]

# Cookie tiêu biểu để xác định đăng nhập
_TIKTOK_LOGIN_COOKIES = {"sessionid", "sid_tt", "sessionid_ss"}
_FACEBOOK_LOGIN_COOKIES = {"c_user", "xs"}

_LOGIN_URLS = {
    "tiktok": "https://www.tiktok.com/login",
    "facebook": "https://www.facebook.com/login",
}

# ===== CDP helpers (nhẹ gọn) =====

def _cdp_call(ws, msg: dict, timeout: float = 1.6):
    ws.settimeout(timeout)
    ws.send(json.dumps(msg))
    try:
        raw = ws.recv()
        return json.loads(raw) if raw else None
    except Exception:
        return None


def _pick_any_page_ws_url(host: str, port: int) -> Optional[str]:
    tabs = _tabs_list(host, port) or []
    for t in tabs:
        if (t.get("type") == "page") and t.get("webSocketDebuggerUrl"):
            return t["webSocketDebuggerUrl"]
    # fallback: /json/version (browser ws) có thể không phù hợp với Network.* trong 1 số bản
    # Ở đây ưu tiên page target; nếu không có page => None
    return None


def _cdp_get_all_cookies(host: str, port: int, timeout: float = 2.5) -> Optional[List[Dict[str, Any]]]:
    if websocket is None:
        return None
    ws_url = _pick_any_page_ws_url(host, port)
    if not ws_url:
        return None
    try:
        ws = websocket.create_connection(ws_url, timeout=timeout, origin="devtools://devtools")
        _cdp_call(ws, {"id": 1, "method": "Network.enable"}, timeout)
        resp = _cdp_call(ws, {"id": 2, "method": "Network.getAllCookies"}, timeout)
        ws.close()
        if resp and isinstance(resp.get("result"), dict):
            return resp["result"].get("cookies") or []
    except Exception:
        return None
    return None


def _cdp_delete_cookie_scoped(host: str, port: int, name: str, domain: str, path: str = "/", timeout: float = 1.6) -> bool:
    if websocket is None:
        return False
    ws_url = _pick_any_page_ws_url(host, port)
    if not ws_url:
        return False
    try:
        ws = websocket.create_connection(ws_url, timeout=timeout, origin="devtools://devtools")
        _cdp_call(ws, {"id": 1, "method": "Network.enable"}, timeout)
        params = {"name": name, "domain": domain}
        if path:
            params["path"] = path
        resp = _cdp_call(ws, {"id": 2, "method": "Network.deleteCookies", "params": params}, timeout)
        ws.close()
        return bool(resp)
    except Exception:
        return False


# ===== SQLite helpers =====

def _read_sqlite_cookie_names(profile_dir: Path, host_suffixes: List[str]) -> Dict[str, List[str]]:
    """Đọc nhanh tên cookie theo host từ file Chromium Cookies (không giải mã giá trị)."""
    cookies_path = profile_dir / "Network" / "Cookies"
    out: Dict[str, List[str]] = {}
    if not cookies_path.exists():
        return out
    try:
        # Mở read-only, tránh lock; Windows hỗ trợ URI mode
        conn = sqlite3.connect(f"file:{cookies_path}?mode=ro", uri=True)
        cur = conn.cursor()
        # host_key có thể dạng .domain; dùng LIKE cho đơn giản
        likes = " OR ".join(["host_key LIKE ?" for _ in host_suffixes])
        cur.execute(f"SELECT host_key, name FROM cookies WHERE {likes}", [f"%{h}" for h in host_suffixes])
        for host_key, name in cur.fetchall():
            host_key = str(host_key or "").lower()
            name = str(name or "")
            out.setdefault(host_key, []).append(name)
        cur.close(); conn.close()
    except Exception:
        return out
    return out


# ===== Phân tích trạng thái đăng nhập =====

def _match_any_host(host_key: str, targets: List[str]) -> bool:
    h = (host_key or "").lower().lstrip(".")
    for t in targets:
        t2 = t.lower().lstrip(".")
        if h == t2 or h.endswith("." + t2):
            return True
    return False


def _analyze_platform_from_cookie_names(platform: str, by_host: Dict[str, List[str]]) -> Dict[str, Any]:
    names = []
    for hk, ns in by_host.items():
        if platform == "tiktok" and _match_any_host(hk, _TIKTOK_HOSTS):
            names += ns
        if platform == "facebook" and _match_any_host(hk, _FACEBOOK_HOSTS):
            names += ns
    name_set = set(names)
    if platform == "tiktok":
        logged_in = bool(name_set & _TIKTOK_LOGIN_COOKIES)
        return {"logged_in": logged_in, "cookies_found": sorted(name_set)[:50]}
    if platform == "facebook":
        logged_in = _FACEBOOK_LOGIN_COOKIES.issubset(name_set)
        return {"logged_in": logged_in, "cookies_found": sorted(name_set)[:50]}
    return {"logged_in": False, "cookies_found": sorted(name_set)[:50]}


def _analyze_platform_from_cdp_cookies(platform: str, cookies: List[Dict[str, Any]]) -> Dict[str, Any]:
    by_name_for_domain: Dict[str, Dict[str, Any]] = {}
    for c in cookies or []:
        domain = str(c.get("domain") or "").lower()
        name = str(c.get("name") or "")
        value = c.get("value")
        if platform == "tiktok" and _match_any_host(domain, _TIKTOK_HOSTS):
            by_name_for_domain[name] = {"domain": domain, "value": value}
        if platform == "facebook" and _match_any_host(domain, _FACEBOOK_HOSTS):
            by_name_for_domain[name] = {"domain": domain, "value": value}

    names = set(by_name_for_domain.keys())
    user_id: Optional[str] = None

    if platform == "tiktok":
        logged_in = bool(names & _TIKTOK_LOGIN_COOKIES)
        # TikTok: khó lấy username offline; ở đây để user_id = None (có thể mở thêm API truy vấn sau)
        return {
            "logged_in": logged_in,
            "user_id": user_id,
            "cookies_found": sorted(list(names))[:50],
        }

    if platform == "facebook":
        # FB: c_user chính là UID
        logged_in = _FACEBOOK_LOGIN_COOKIES.issubset(names)
        if "c_user" in by_name_for_domain:
            user_id = str(by_name_for_domain["c_user"].get("value") or "") or None
        return {
            "logged_in": logged_in,
            "user_id": user_id,
            "cookies_found": sorted(list(names))[:50],
        }

    return {"logged_in": False, "cookies_found": sorted(list(names))[:50]}


# ===== API: LIST =====
@router.get("/list")
def list_accounts(
    profiles_root: str = Query(DEFAULT_PROFILES_ROOT),
    host: str = Query(DEFAULT_HOST),
    platform: Literal["all", "tiktok", "facebook"] = Query("all"),
    filter_: Literal["all", "logged_in", "logged_out"] = Query("all", alias="filter"),
    verify: bool = Query(False, description="Nếu true và profile đang chạy: dùng CDP lấy cookie chính xác."),
    include_pids: bool = Query(False),
    include_ports: bool = Query(True),
) -> Dict[str, Any]:
    root = Path(profiles_root)
    if not root.exists():
        return {"ok": True, "count": 0, "results": []}

    # Liệt kê profile chuẩn
    names: List[str] = []
    for d in root.iterdir():
        if d.is_dir() and re.fullmatch(r"Profile\d{3}", d.name, re.IGNORECASE):
            names.append(d.name)
    def _key(n: str):
        m = re.fullmatch(r"Profile0*([0-9]+)", n, flags=re.IGNORECASE)
        return (0, int(m.group(1))) if m else (1, n.lower())
    names.sort(key=_key)

    cache = _load_cached_ports_file(str(root))
    out: List[Dict[str, Any]] = []

    for name in names:
        pdir = _profile_dir(str(root), name)
        port = cache.get(name) or _read_devtools_port(pdir)
        running = bool(port) and _devtools_ok(host or DEFAULT_HOST, int(port))

        # Thu thập cookie theo 2 con đường
        tiktok_info: Optional[Dict[str, Any]] = None
        facebook_info: Optional[Dict[str, Any]] = None
        source = "none"

        if running and verify:
            cookies = _cdp_get_all_cookies(host or DEFAULT_HOST, int(port))
            if cookies is not None:
                source = "cdp"
                if platform in ("all", "tiktok"):
                    tiktok_info = _analyze_platform_from_cdp_cookies("tiktok", cookies)
                if platform in ("all", "facebook"):
                    facebook_info = _analyze_platform_from_cdp_cookies("facebook", cookies)
        if (tiktok_info is None and facebook_info is None):
            # Fallback SQLite (kể cả khi đang chạy nhưng verify=False hoặc CDP lỗi)
            source = "sqlite"
            by_host = _read_sqlite_cookie_names(pdir, _TIKTOK_HOSTS + _FACEBOOK_HOSTS)
            if platform in ("all", "tiktok"):
                tiktok_info = _analyze_platform_from_cookie_names("tiktok", by_host)
            if platform in ("all", "facebook"):
                facebook_info = _analyze_platform_from_cookie_names("facebook", by_host)

        # Áp dụng filter
        def _any_logged_in() -> bool:
            vals = []
            if platform in ("all", "tiktok") and tiktok_info is not None:
                vals.append(bool(tiktok_info.get("logged_in")))
            if platform in ("all", "facebook") and facebook_info is not None:
                vals.append(bool(facebook_info.get("logged_in")))
            return any(vals) if vals else False

        if filter_ == "logged_in" and not _any_logged_in():
            continue
        if filter_ == "logged_out" and _any_logged_in():
            continue

        item: Dict[str, Any] = {
            "profile": name,
            "dir": str(pdir),
            "running": running,
            "source": source,
        }
        if include_ports and port:
            item["devtools_port"] = int(port)
        if include_pids:
            # Optional: chỉ lấy pids khi cần (tránh tốn thời gian)
            try:
                from profiles_router import _collect_pids_by_cmdline  # lazy import
                pids = _collect_pids_by_cmdline(str(pdir), ["opera.exe", "opera_beta.exe", "opera_gx.exe", "opera_browser.exe"])  # type: ignore
                if pids:
                    item["pids"] = sorted(set(int(x) for x in pids))
            except Exception:
                pass

        if platform in ("all", "tiktok"):
            item["tiktok"] = tiktok_info
        if platform in ("all", "facebook"):
            item["facebook"] = facebook_info

        out.append(item)

    return {"ok": True, "count": len(out), "results": out}


# ===== API: Mở trang đăng nhập nhanh =====
class OpenLoginReq(BaseModel):
    profiles_root: str = DEFAULT_PROFILES_ROOT
    profiles: Optional[List[str]] = None
    indices: Optional[List[int]] = None
    zero_pad: int = 3
    host: str = DEFAULT_HOST
    platform: Literal["tiktok", "facebook"]
    activate_opened_tab: bool = True



@router.post("/open-login")
def open_login(req: OpenLoginReq) -> Dict[str, Any]:
    root = Path(req.profiles_root)
    host = req.host or DEFAULT_HOST
    url = _LOGIN_URLS.get(req.platform)
    if not url:
        return {"ok": False, "error": "unsupported_platform"}

    # Xác định danh sách profile mục tiêu
    names: List[str] = []
    if req.profiles:
        names += [str(x).strip() for x in req.profiles if str(x).strip()]
    if req.indices:
        z = int(req.zero_pad)
        names += [f"Profile{str(i).zfill(z)}" for i in req.indices]
    names = [n for n in names if n]
    if not names:
        return {"ok": False, "results": [], "detail": "empty_profiles"}

    res: List[Dict[str, Any]] = []
    for name in names:
        pdir = _profile_dir(str(root), name)
        port = _read_devtools_port(pdir)
        if not (port and _devtools_ok(host, int(port))):
            res.append({"profile": name, "ok": False, "detail": "not_running_or_port_unknown"})
            continue
        try:
            # Tận dụng REST DevTools để mở tab mới
            r = requests.get(f"http://{host}:{int(port)}/json/new?{url}", timeout=1.8)
            ok = bool(r.ok)
            res.append({"profile": name, "ok": ok, "port": int(port), "detail": "opened" if ok else "open_failed"})
        except Exception as e:
            res.append({"profile": name, "ok": False, "port": int(port), "error": f"{type(e).__name__}: {e}"})
    return {"ok": True, "count": len(res), "results": res}


# ===== API: Đăng xuất nhanh (xóa cookie theo platform, chỉ khi đang chạy) =====
class LogoutReq(BaseModel):
    profiles_root: str = DEFAULT_PROFILES_ROOT
    profiles: Optional[List[str]] = None
    indices: Optional[List[int]] = None
    zero_pad: int = 3
    host: str = DEFAULT_HOST
    platform: Literal["tiktok", "facebook"]
    scoped: bool = True  # True = xóa cookie theo domain platform; False = xóa toàn bộ cookie (nguy hiểm)


@router.post("/logout-running")
def logout_running(req: LogoutReq) -> Dict[str, Any]:
    host = req.host or DEFAULT_HOST
    root = Path(req.profiles_root)

    names: List[str] = []
    if req.profiles:
        names += [str(x).strip() for x in req.profiles if str(x).strip()]
    if req.indices:
        z = int(req.zero_pad)
        names += [f"Profile{str(i).zfill(z)}" for i in req.indices]
    if not names:
        return {"ok": False, "results": [], "detail": "empty_profiles"}

    results: List[Dict[str, Any]] = []
    for name in names:
        pdir = _profile_dir(str(root), name)
        port = _read_devtools_port(pdir)
        if not (port and _devtools_ok(host, int(port))):
            results.append({"profile": name, "ok": False, "detail": "not_running_or_port_unknown"})
            continue

        if websocket is None:
            results.append({"profile": name, "ok": False, "detail": "websocket_client_not_installed"})
            continue

        # Lấy toàn bộ cookie trước để biết domain/path chính xác
        cookies = _cdp_get_all_cookies(host, int(port)) or []
        target_hosts = _TIKTOK_HOSTS if req.platform == "tiktok" else _FACEBOOK_HOSTS

        if not req.scoped:
            # Xóa toàn bộ cookie của trình duyệt (cho profile đó) — khá mạnh tay, cân nhắc sử dụng
            try:
                ws_url = _pick_any_page_ws_url(host, int(port))
                if not ws_url:
                    results.append({"profile": name, "ok": False, "detail": "no_page_target"})
                    continue
                ws = websocket.create_connection(ws_url, timeout=2.5, origin="devtools://devtools")
                _cdp_call(ws, {"id": 1, "method": "Network.enable"}, 2.0)
                resp = _cdp_call(ws, {"id": 2, "method": "Network.clearBrowserCookies"}, 2.0)
                ws.close()
                results.append({"profile": name, "ok": bool(resp), "detail": "cleared_all_cookies"})
                continue
            except Exception as e:
                results.append({"profile": name, "ok": False, "detail": f"clear_all_failed:{type(e).__name__}: {e}"})
                continue

        # scoped: chỉ xóa cookie thuộc domain target
        deleted = 0; attempted = 0
        for c in cookies:
            domain = str(c.get("domain") or "").lower()
            if any(_match_any_host(domain, [h]) for h in target_hosts):
                name = str(c.get("name") or "")
                path = c.get("path") or "/"
                attempted += 1
                if _cdp_delete_cookie_scoped(host, int(port), name, domain, path=path):
                    deleted += 1
        results.append({
            "profile": name,
            "ok": True,
            "deleted": deleted,
            "attempted": attempted,
            "detail": f"scoped_delete:{req.platform}",
        })

    return {"ok": True, "count": len(results), "results": results}


# ===== (Tuỳ chọn) Lưu alias/ghi chú tài khoản (metadata đơn giản) =====
_META_FILE = ".accounts_meta.json"

class SetMetaReq(BaseModel):
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT)
    profile: str
    platform: Literal["tiktok", "facebook"]
    alias: Optional[str] = None
    note: Optional[str] = None


def _read_meta(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except Exception:
        return {}


def _write_meta(path: Path, data: Dict[str, Any]) -> None:
    try:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass


@router.get("/meta")
def get_meta(profiles_root: str = Query(DEFAULT_PROFILES_ROOT)) -> Dict[str, Any]:
    root = Path(profiles_root)
    m = _read_meta(root / _META_FILE)
    return {"ok": True, "meta": m}


@router.post("/meta/set")
def set_meta(req: SetMetaReq) -> Dict[str, Any]:
    root = Path(req.profiles_root)
    path = root / _META_FILE
    data = _read_meta(path)
    key = f"{req.profile}:{req.platform}"
    data[key] = {"alias": req.alias, "note": req.note, "ts": int(time.time())}
    _write_meta(path, data)
    return {"ok": True, "saved": key, "value": data[key]}


# =====================
# SQLite SIMPLE ACCOUNT CRUD (manual input – no passwords)
# Prefix: /v1/opera/accounts/sqlite/*
# =====================
_ACCOUNTS_DB_FILENAME = ".accounts.db"

class AccountCreate(BaseModel):
    profiles_root: str = DEFAULT_PROFILES_ROOT
    platform: Literal["tiktok", "facebook"]
    email: str
    alias: Optional[str] = None
    note: Optional[str] = None
    profiles: Optional[List[str]] = None  # danh sách ProfileNNN gắn với tài khoản (tùy chọn)
    active: bool = True
    db_path: Optional[str] = None  # nếu muốn chỉ định đường dẫn .db riêng


class AccountKey(BaseModel):
    profiles_root: str = DEFAULT_PROFILES_ROOT
    id: Optional[int] = None
    platform: Optional[Literal["tiktok", "facebook"]] = None
    email: Optional[str] = None
    db_path: Optional[str] = None


class AccountUpdate(BaseModel):
    profiles_root: str = DEFAULT_PROFILES_ROOT
    id: Optional[int] = None
    platform: Optional[Literal["tiktok", "facebook"]] = None
    email: Optional[str] = None
    alias: Optional[str] = None
    note: Optional[str] = None
    profiles: Optional[List[str]] = None
    active: Optional[bool] = None
    db_path: Optional[str] = None


class AccountListQuery(BaseModel):
    profiles_root: str = DEFAULT_PROFILES_ROOT
    platform: Optional[Literal["tiktok", "facebook", "all"]] = "all"
    active: Optional[bool] = None
    q: Optional[str] = None  # search email/alias/note
    profile: Optional[str] = None  # lọc theo ProfileNNN (tìm trong JSON)
    limit: int = 100
    offset: int = 0
    order_by: Literal["created_at", "updated_at", "email", "alias"] = "updated_at"
    order_dir: Literal["asc", "desc"] = "desc"
    db_path: Optional[str] = None


def _now_ts() -> int:
    return int(time.time())


def _db_path_from_root(root: Path, db_path: Optional[str]) -> Path:
    return Path(db_path) if db_path else (root / _ACCOUNTS_DB_FILENAME)


def _ensure_db(dbfile: Path) -> None:
    dbfile.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(dbfile))
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS accounts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              platform TEXT NOT NULL CHECK(platform IN ('tiktok','facebook')),
              email TEXT NOT NULL,
              alias TEXT,
              note TEXT,
              profiles_json TEXT,
              active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              UNIQUE(platform, email)
            );
            """
        )
        conn.commit()
    finally:
        conn.close()


def _profiles_to_json(profiles: Optional[List[str]]) -> str:
    if not profiles:
        return json.dumps([])
    # chuẩn hóa, unique, sort
    uniq = sorted({str(p).strip() for p in profiles if str(p).strip()})
    return json.dumps(uniq, ensure_ascii=False)


def _row_to_account(row: sqlite3.Row) -> Dict[str, Any]:
    return {
        "id": row[0],
        "platform": row[1],
        "email": row[2],
        "alias": row[3],
        "note": row[4],
        "profiles": json.loads(row[5] or "[]"),
        "active": bool(row[6]),
        "created_at": row[7],
        "updated_at": row[8],
    }


@router.post("/sqlite/upsert")
def sqlite_upsert(account: AccountCreate) -> Dict[str, Any]:
    root = Path(account.profiles_root)
    dbfile = _db_path_from_root(root, account.db_path)
    _ensure_db(dbfile)

    ts = _now_ts()
    profiles_json = _profiles_to_json(account.profiles)

    conn = sqlite3.connect(str(dbfile))
    try:
        conn.execute(
            """
            INSERT INTO accounts(platform,email,alias,note,profiles_json,active,created_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(platform,email) DO UPDATE SET
              alias=excluded.alias,
              note=excluded.note,
              profiles_json=excluded.profiles_json,
              active=excluded.active,
              updated_at=excluded.updated_at;
            """,
            (
                account.platform,
                account.email.strip(),
                account.alias,
                account.note,
                profiles_json,
                1 if account.active else 0,
                ts,
                ts,
            ),
        )
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "detail": "upserted", "platform": account.platform, "email": account.email.strip()}


@router.post("/sqlite/update")
def sqlite_update(req: AccountUpdate) -> Dict[str, Any]:
    root = Path(req.profiles_root)
    dbfile = _db_path_from_root(root, req.db_path)
    _ensure_db(dbfile)

    # Xác định bản ghi theo id hoặc (platform,email)
    where = []
    args: List[Any] = []
    if req.id is not None:
        where.append("id = ?")
        args.append(int(req.id))
    elif req.platform and req.email:
        where.append("platform = ? AND email = ?")
        args.extend([req.platform, req.email.strip()])
    else:
        return {"ok": False, "error": "missing_identifier", "hint": "Cần id hoặc (platform,email)"}

    fields = []
    fargs: List[Any] = []
    if req.alias is not None:
        fields.append("alias = ?")
        fargs.append(req.alias)
    if req.note is not None:
        fields.append("note = ?")
        fargs.append(req.note)
    if req.profiles is not None:
        fields.append("profiles_json = ?")
        fargs.append(_profiles_to_json(req.profiles))
    if req.active is not None:
        fields.append("active = ?")
        fargs.append(1 if req.active else 0)
    if req.platform is not None and req.id is not None:
        fields.append("platform = ?")
        fargs.append(req.platform)
    if req.email is not None and req.id is not None:
        fields.append("email = ?")
        fargs.append(req.email.strip())

    if not fields:
        return {"ok": False, "error": "nothing_to_update"}

    fields.append("updated_at = ?")
    fargs.append(_now_ts())

    sql = f"UPDATE accounts SET {', '.join(fields)} WHERE {' AND '.join(where)}"

    conn = sqlite3.connect(str(dbfile))
    try:
        cur = conn.execute(sql, fargs + args)
        conn.commit()
        return {"ok": True, "updated": cur.rowcount}
    finally:
        conn.close()


@router.post("/sqlite/delete")
def sqlite_delete(req: AccountKey) -> Dict[str, Any]:
    root = Path(req.profiles_root)
    dbfile = _db_path_from_root(root, req.db_path)
    _ensure_db(dbfile)

    if req.id is None and not (req.platform and req.email):
        return {"ok": False, "error": "missing_identifier", "hint": "Cần id hoặc (platform,email)"}

    where = []
    args: List[Any] = []
    if req.id is not None:
        where.append("id = ?")
        args.append(int(req.id))
    if req.platform and req.email:
        where.append("platform = ? AND email = ?")
        args.extend([req.platform, req.email.strip()])

    sql = f"DELETE FROM accounts WHERE {' OR '.join(where)}"

    conn = sqlite3.connect(str(dbfile))
    try:
        cur = conn.execute(sql, args)
        conn.commit()
        return {"ok": True, "deleted": cur.rowcount}
    finally:
        conn.close()


@router.get("/sqlite/get")
def sqlite_get(
    profiles_root: str = Query(DEFAULT_PROFILES_ROOT),
    id: Optional[int] = Query(None),
    platform: Optional[Literal["tiktok", "facebook"]] = Query(None),
    email: Optional[str] = Query(None),
    db_path: Optional[str] = Query(None),
) -> Dict[str, Any]:
    root = Path(profiles_root)
    dbfile = _db_path_from_root(root, db_path)
    _ensure_db(dbfile)

    if id is None and not (platform and email):
        return {"ok": False, "error": "missing_identifier", "hint": "Cần id hoặc (platform,email)"}

    where = []
    args: List[Any] = []
    if id is not None:
        where.append("id = ?")
        args.append(int(id))
    if platform and email:
        where.append("platform = ? AND email = ?")
        args.extend([platform, email.strip()])

    conn = sqlite3.connect(str(dbfile))
    try:
        conn.row_factory = sqlite3.Row
        cur = conn.execute(f"SELECT * FROM accounts WHERE {' OR '.join(where)} LIMIT 1", args)
        row = cur.fetchone()
        if not row:
            return {"ok": False, "error": "not_found"}
        return {"ok": True, "account": _row_to_account(row)}
    finally:
        conn.close()


@router.get("/sqlite/list")
def sqlite_list(
    profiles_root: str = Query(DEFAULT_PROFILES_ROOT),
    platform: Optional[Literal["tiktok", "facebook", "all"]] = Query("all"),
    active: Optional[bool] = Query(None),
    q: Optional[str] = Query(None),
    profile: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    order_by: Literal["created_at", "updated_at", "email", "alias"] = Query("updated_at"),
    order_dir: Literal["asc", "desc"] = Query("desc"),
    db_path: Optional[str] = Query(None),
) -> Dict[str, Any]:
    root = Path(profiles_root)
    dbfile = _db_path_from_root(root, db_path)
    _ensure_db(dbfile)

    wh = []
    args: List[Any] = []
    if platform and platform != "all":
        wh.append("platform = ?")
        args.append(platform)
    if active is not None:
        wh.append("active = ?")
        args.append(1 if active else 0)
    if q:
        like = f"%{q}%"
        wh.append("(email LIKE ? OR IFNULL(alias,'') LIKE ? OR IFNULL(note,'') LIKE ?)")
        args.extend([like, like, like])
    if profile:
        # tìm chuỗi "ProfileXYZ" bên trong JSON
        wh.append("IFNULL(profiles_json,'') LIKE ?")
        args.append(f"%\"{profile}\"%")

    where_sql = (" WHERE " + " AND ".join(wh)) if wh else ""
    order_sql = f" ORDER BY {order_by} {order_dir.upper()}"
    limit_sql = " LIMIT ? OFFSET ?"
    args2 = args + [int(limit), int(offset)]

    conn = sqlite3.connect(str(dbfile))
    try:
        conn.row_factory = sqlite3.Row
        cur = conn.execute(f"SELECT * FROM accounts{where_sql}{order_sql}{limit_sql}", args2)
        rows = cur.fetchall()
        data = [_row_to_account(r) for r in rows]

        # tổng số bản ghi (để phân trang phía client)
        cur2 = conn.execute(f"SELECT COUNT(1) FROM accounts{where_sql}", args)
        total = int(cur2.fetchone()[0])
        return {"ok": True, "count": len(data), "total": total, "results": data}
    finally:
        conn.close()
