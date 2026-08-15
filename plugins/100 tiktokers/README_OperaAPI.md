# Opera Profiles Launcher API — README

> FastAPI service to manage multiple Opera/Chromium profiles, inspect DevTools targets, and resolve logged-in accounts for TikTok/Facebook. This app aggregates modular routers so you can scale features without bloating a single file.

- **Entrypoint:** `opera_api.py` (aggregator; includes routers)
- **Routers included (by this README):**
  - `profiles_router.py` → `/v1/opera/profiles/*`
  - `accounts_router.py` → `/v1/opera/accounts/*` (includes `resolve` + `quick`)
- **Utility endpoints:** `/`, `/health`, `/meta/routes`, `/v1/opera/session/keepalive`

---

## 1) Requirements

- Python 3.9+ (tested on 3.11/3.12)
- OS: Windows recommended (required for cookie decrypt in **accounts quick**)
- Dependencies:
  ```bash
  pip install fastapi uvicorn requests websocket-client pycryptodomex
  ```
  - `websocket-client` → needed for **/accounts/resolve** (CDP)
  - `pycryptodomex` → needed for **/accounts/quick** (decrypt AES‑GCM cookies)

### Environment variables (optional)
- `OPERA_API_HOST` (default `0.0.0.0`)
- `OPERA_API_PORT` (default `8000`)
- `CORS_ALLOW_ORIGINS` (default `*`; comma‑separated list)
- (Optional) Set Opera path per request via API (`start` endpoint), or rely on router default.

---

## 2) Run

```bash
python opera_api.py
# or
OPERA_API_HOST=0.0.0.0 OPERA_API_PORT=8000 python opera_api.py
```

Open:
- Docs (Swagger): `http://localhost:8000/docs`
- Health: `http://localhost:8000/health`
- Route list: `http://localhost:8000/meta/routes`

---

## 3) API Overview

| Method | Path | Purpose |
|---|---|---|
| GET  | `/` | Service info & router prefixes |
| GET  | `/health` | Health check |
| GET  | `/meta/routes` | List all registered routes |
| GET  | `/v1/opera/session/keepalive` | Simple keepalive ping |
| GET  | `/v1/opera/profiles/list` | List profiles & DevTools status |
| GET  | `/v1/opera/profiles/ws` | Get a profile’s `wsEndpoint` |
| POST | `/v1/opera/profiles/start` | Start Opera with a profile (remote debugging on) |
| POST | `/v1/opera/profiles/start-range` | Start a range of profiles |
| POST | `/v1/opera/profiles/kill-all` | Close all running profiles (graceful/force) |
| POST | `/v1/opera/accounts/quick` | **FAST**: Check login status via cookies (Windows) |
| POST | `/v1/opera/accounts/resolve` | **DEEP**: Resolve TikTok/Facebook account details via CDP |

> **Tip:** Use `/accounts/quick` for lightweight “logged_in?” checks. Use `/accounts/resolve` when you need **email/username/uid** (it may open a tab briefly).

---

## 4) Utility Endpoints

### GET `/`
Returns app info and detected route prefixes.
```json
{
  "name": "Opera Profiles Launcher API",
  "version": "2.6.0",
  "message": "OK",
  "routers": ["/v1/opera/profiles","/v1/opera/accounts", "..."]
}
```

### GET `/health`
```json
{"status":"healthy","version":"2.6.0"}
```

### GET `/meta/routes`
Lists all routes (methods, paths, names) to help with debugging.

### GET `/v1/opera/session/keepalive`
Simple timestamped response for polling.
```json
{"ok":true,"ts": 1725600000.123,"version":"2.6.0"}
```

---

## 5) Profiles API (`/v1/opera/profiles/*`)

### GET `/v1/opera/profiles/list`
List all directories named `Profile*` under `profiles_root`, and detect if DevTools is active.

**Query params**
- `profiles_root` (str) — e.g. `D:\OperaProfiles`
- `host` (str, default `127.0.0.1`) — DevTools host

**Response (example)**
```json
{
  "count": 2,
  "items": [
    {
      "profile": "Profile001",
      "dir": "D:\\OperaProfiles\\Profile001",
      "wsEndpoint": "ws://127.0.0.1:54949/devtools/browser/....",
      "devtools_port": 54949,
      "running_ws": true,
      "running_http": true,
      "running": true
    },
    {
      "profile": "Profile002",
      "dir": "D:\\OperaProfiles\\Profile002",
      "wsEndpoint": null,
      "devtools_port": null,
      "running_ws": false,
      "running_http": false,
      "running": false
    }
  ]
}
```

### GET `/v1/opera/profiles/ws`
Get a single profile’s websocket debugger URL.

**Query params**
- `profiles_root` (str)
- `profile` (str) — e.g. `Profile001`
- `host` (str, default `127.0.0.1`)

**Response**
```json
{"profile":"Profile001","wsEndpoint":"ws://127.0.0.1:54949/devtools/browser/...."}
```

### POST `/v1/opera/profiles/start`
Start Opera with a profile on a **random free** or given port, with remote debugging enabled.

**Body**
```json
{
  "profile": "Profile001",
  "profiles_root": "D:\\OperaProfiles",
  "opera_path": null,
  "remote_debug_port": null,
  "extra_args": []
}
```
- `opera_path` (optional) — explicit path to `opera.exe`
- `remote_debug_port` (optional) — if omitted, a free port is chosen
- `extra_args` (optional) — extra Chromium flags

**Response**
```json
{"profile":"Profile001","pid":12345,"port":54949,"dir":"D:\\OperaProfiles\\Profile001"}
```

### POST `/v1/opera/profiles/start-range`
Start multiple profiles (`Profile{start..end}`) and prepare DevTools.

**Body**
```json
{
  "start": 1,
  "end": 3,
  "profiles_root": "D:\\OperaProfiles",
  "zero_pad": 3,
  "extra_args": [],
  "host": "127.0.0.1",
  "devtools_ready_timeout_ms": 20000,
  "close_tabs_on_start": true,
  "leave_one_tab": true,
  "new_tab_url": "about:blank",
  "close_types": ["page"]
}
```

**Response (example)**
```json
{
  "count": 3,
  "results": [
    {
      "profile":"Profile001","pid":12345,"port":54949,
      "wsEndpoint":"ws://127.0.0.1:54949/devtools/browser/....",
      "dir":"D:\\OperaProfiles\\Profile001","detail":null
    },
    {"profile":"Profile002", "...": "..."}
  ]
}
```

### POST `/v1/opera/profiles/kill-all`
Close all profiles by reading DevTools ports from each profile.

**Query params**
- `profiles_root` (str)
- `mode` (str: `graceful`|`force`, default: `graceful`)
- `host` (str, default `127.0.0.1`)

**Response (example)**
```json
{
  "count": 2,
  "results": [
    {"profile":"Profile001","ok":true,"action":"graceful","port":54949},
    {"profile":"Profile002","ok":false,"action":"force","port":null,"detail":"pid_not_found"}
  ]
}
```

> **Note (Windows):** `mode=force` may call `taskkill /PID <pid> /F` after mapping PID from `netstat -ano`.

---

## 6) Accounts API (`/v1/opera/accounts/*`)

### A) FAST — POST `/v1/opera/accounts/quick`
Read login state **from cookies** (no browser/CDP). **Windows only** (uses DPAPI) for now.

**Body**
```json
{
  "profiles_root": "D:\\OperaProfiles",
  "profiles": ["Profile001","Profile005"],
  "tiktok_cookie_names": ["sessionid","sessionid_ss","sid_guard"],
  "expose_values": false
}
```
- `profiles` optional — omit to scan all `Profile*`
- `expose_values` — if `true`, returns plaintext cookie values (⚠️ sensitive; use only for debugging)

**Response**
```json
{
  "count": 2,
  "items": [
    {
      "profile": "Profile001",
      "ok": true,
      "accounts": {
        "facebook": {"logged_in": true, "user_id": "1000xxxxxxxxx"},
        "tiktok":   {"logged_in": true, "cookies": {"sessionid": true,"sessionid_ss": false,"sid_guard": true}}
      }
    },
    {"profile":"Profile005","ok":false,"error":"..."}
  ]
}
```

> Facebook cookies expose **user_id** via `c_user`, not email. TikTok cookies indicate session presence, not email/username.

### B) DEEP — POST `/v1/opera/accounts/resolve`
Resolve account details using **Chrome DevTools Protocol** (can open a tab briefly; then closes).

**Body**
```json
{
  "profiles_root": "D:\\OperaProfiles",
  "host": "127.0.0.1",
  "profiles": ["Profile001","Profile002"],
  "targets": ["tiktok","facebook"],
  "open_if_needed": true,
  "timeout_ms": 12000
}
```
- Uses in‑page `fetch` + DOM to get TikTok `email|username|uid` and Facebook `user_id|email|name` when available.

**Response (example)**
```json
{
  "count": 1,
  "items": [
    {
      "profile": "Profile001",
      "ok": true,
      "summary": {
        "facebook": {"user_id":"1000...","email":"...@gmail.com","name":"Your Name"},
        "tiktok": {"email":"...@gmail.com","username":"yourhandle","uid":"7123...","source":"passport.web.account.info"}
      },
      "raw": {
        "facebook.com": {"ok": true, "opened_new": true, "data": {"userId":"1000...","email":"...","name":"..."}},
        "tiktok.com":   {"ok": true, "opened_new": false, "data": {"email":"...","username":"...","uid":"..."}}
      }
    }
  ]
}
```

> If a profile isn’t running or the DevTools port is unknown you’ll get `not_running_or_port_unknown` for that profile.

---

## 7) Examples (curl)

```bash
# List
curl "http://localhost:8000/v1/opera/profiles/list?profiles_root=D:\\OperaProfiles&host=127.0.0.1"

# Start one
curl -X POST http://localhost:8000/v1/opera/profiles/start ^
  -H "Content-Type: application/json" ^
  -d "{\"profile\":\"Profile001\",\"profiles_root\":\"D:\\\\OperaProfiles\"}"

# Start range
curl -X POST http://localhost:8000/v1/opera/profiles/start-range ^
  -H "Content-Type: application/json" ^
  -d "{\"start\":1,\"end\":3,\"profiles_root\":\"D:\\\\OperaProfiles\",\"close_tabs_on_start\":true}"

# Kill all (graceful)
curl -X POST "http://localhost:8000/v1/opera/profiles/kill-all?profiles_root=D:\\OperaProfiles&mode=graceful"

# QUICK (cookies)
curl -X POST http://localhost:8000/v1/opera/accounts/quick ^
  -H "Content-Type: application/json" ^
  -d "{\"profiles_root\":\"D:\\\\OperaProfiles\"}"

# RESOLVE (CDP)
curl -X POST http://localhost:8000/v1/opera/accounts/resolve ^
  -H "Content-Type: application/json" ^
  -d "{\"profiles_root\":\"D:\\\\OperaProfiles\",\"profiles\":[\"Profile001\"],\"targets\":[\"tiktok\",\"facebook\"],\"open_if_needed\":true}"
```

---

## 8) Troubleshooting

- `Thiếu websocket-client` → install: `pip install websocket-client`
- `ImportError: No module named Cryptodome` → install: `pip install pycryptodomex`
- `profiles_root_not_found` → check your path; ensure `Profile*` directories exist
- `Windows-only quick cookie decrypt` → quick cookies currently only supported on Windows (DPAPI). macOS/Linux support can be added via Keychain/libsecret.
- `pid_not_found` or `port_unknown` → The profile may not be running with remote debugging enabled, or DevTools file is missing.
- Opera doesn’t start → confirm `opera_path`, or set via API `start` payload. Try launching Opera manually to confirm installation.
- If tabs remain open after `/accounts/resolve` → the router attempts to close **only the tab it opened**. If you started with existing tabs, they remain untouched.

---

## 9) Security Notes

- **Never** enable `expose_values` in production; it returns **plaintext cookie values**.
- Treat all outputs (emails, usernames, user IDs) as **sensitive**.
- Limit access to this API (bind to localhost, use reverse proxy auth, etc.).
- Adjust CORS as needed (`CORS_ALLOW_ORIGINS`).

---

## 10) Version

- App: `2.6.0`
- Routers: `profiles_router.py`, `accounts_router.py`

Changelog highlights:
- 2.6.0 — Split routers; added `accounts/quick` (cookie) + `accounts/resolve` (CDP); expanded docs.
