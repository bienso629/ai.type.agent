#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Colab Agent & MCP Bridge Plugin for ai.type
Provides automated connection management, remote code execution,
PDF parsing with MinerU GPU, FAISS indexing, and automatic tunnel registration.
"""

__version__ = "1.0.1"

import os
import sys

# Xử lý cờ --version ngay lập tức để Electron đọc siêu nhanh (0ms)
if "--version" in sys.argv or "-v" in sys.argv:
    print(__version__)
    sys.exit(0)

import json
import time
import base64
import argparse
import logging
from typing import Optional, Dict, Any, List
from pathlib import Path

import requests
import uvicorn
import socket
import urllib.request

_orig_getaddrinfo = socket.getaddrinfo
_dns_cache = {}

def custom_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    try:
        return _orig_getaddrinfo(host, port, family, type, proto, flags)
    except socket.gaierror:
        if host in _dns_cache:
            return _orig_getaddrinfo(_dns_cache[host], port, family, type, proto, flags)
        for doh_url in [f"https://1.1.1.1/dns-query?name={host}&type=A", f"https://8.8.8.8/resolve?name={host}&type=A"]:
            try:
                req = urllib.request.Request(doh_url, headers={"accept": "application/dns-json"})
                with urllib.request.urlopen(req, timeout=3) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    for ans in data.get("Answer", []):
                        if ans.get("type") == 1:
                            ip = ans.get("data")
                            _dns_cache[host] = ip
                            return _orig_getaddrinfo(ip, port, family, type, proto, flags)
            except Exception:
                continue
        raise

socket.getaddrinfo = custom_getaddrinfo

from fastapi import FastAPI, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Cấu hình logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S"
)
logger = logging.getLogger("ColabAgent")

# Thư mục cấu hình cục bộ
DATA_DIR = Path.home() / "Documents" / "ai.type" / "data" / "colab"
DATA_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = DATA_DIR / "agent_config.json"

def load_config() -> Dict[str, Any]:
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "colab_url": "",
        "last_connected": "",
        "gpu_info": "",
        "auto_connect": True
    }

def save_config(cfg: Dict[str, Any]):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logger.error(f"Lỗi lưu cấu hình: {e}")

class ColabState:
    def __init__(self):
        self.version = __version__
        self.config = load_config()
        self.colab_url = self.config.get("colab_url", "")
        self.is_connected = False
        self.gpu_info = ""
        self.available_tools = []
        self.last_heartbeat = 0
        self.session_logs = []
        self.oauth_flow = None

    def log(self, msg: str):
        ts = time.strftime("%H:%M:%S")
        entry = f"[{ts}] {msg}"
        logger.info(entry)
        self.session_logs.append(entry)
        if len(self.session_logs) > 200:
            self.session_logs.pop(0)

    def test_connection(self, url: Optional[str] = None) -> Dict[str, Any]:
        target = (url or self.colab_url).strip()
        if not target:
            return {"success": False, "error": "Chưa có địa chỉ Colab URL"}

        # Chuẩn hóa URL
        target = target.rstrip("/")
        if target.endswith("/sse"):
            target = target[:-4]

        try:
            self.log(f"Đang kiểm tra kết nối tới Colab: {target}")
            resp = requests.get(f"{target}/status", timeout=8)
            if resp.status_code == 200:
                data = resp.json()
                self.is_connected = True
                self.colab_url = target
                self.gpu_info = data.get("gpu", "NVIDIA GPU")
                self.available_tools = data.get("tools", [])
                self.last_heartbeat = time.time()
                
                # Lưu cấu hình
                self.config["colab_url"] = target
                self.config["last_connected"] = time.strftime("%Y-%m-%d %H:%M:%S")
                self.config["gpu_info"] = self.gpu_info
                save_config(self.config)

                self.log(f"Kết nối thành công! GPU: {self.gpu_info}")
                return {
                    "success": True,
                    "colab_url": self.colab_url,
                    "gpu": self.gpu_info,
                    "tools": self.available_tools
                }
        except Exception as e:
            self.is_connected = False
            self.log(f"Kết nối thất bại: {e}")
            return {"success": False, "error": str(e)}

    def execute_remote_tool(self, tool_name: str, args: Dict[str, Any], timeout: int = 300) -> Dict[str, Any]:
        if not self.colab_url:
            raise HTTPException(status_code=400, detail="Chưa kết nối tới máy chủ Colab")

        url = f"{self.colab_url}/call_tool"
        payload = {"name": tool_name, "arguments": args}
        try:
            self.log(f"Đang gọi tool '{tool_name}' trên Colab GPU...")
            resp = requests.post(url, json=payload, timeout=timeout)
            if resp.status_code == 200:
                return resp.json()
            else:
                return {"error": f"HTTP {resp.status_code}: {resp.text[:200]}"}
        except Exception as e:
            return {"error": f"Lỗi gọi tool: {str(e)}"}

state = ColabState()

# Tạo FastAPI App
app = FastAPI(title="ai.type Colab Agent & MCP Bridge", version=__version__)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class ConnectRequest(BaseModel):
    url: str

class ExecuteCodeRequest(BaseModel):
    code: str
    language: Optional[str] = "python"

class ParsePdfRequest(BaseModel):
    pdf_base64: str
    filename: str
    doc_type: Optional[str] = "qa_detailed"
    google_api_key: Optional[str] = ""

class TunnelRegisterRequest(BaseModel):
    url: str
    username: Optional[str] = "admin"
    gpu: Optional[str] = ""

@app.get("/")
def root():
    return {
        "app": "ai.type-colab-agent",
        "version": __version__,
        "status": "online",
        "is_colab_connected": state.is_connected,
        "colab_url": state.colab_url,
        "gpu": state.gpu_info
    }

@app.get("/status")
def get_status():
    return {
        "status": "online",
        "version": __version__,
        "is_connected": state.is_connected,
        "colab_url": state.colab_url,
        "gpu": state.gpu_info,
        "tools": state.available_tools,
        "logs": state.session_logs[-30:]
    }

@app.post("/connect")
def connect_colab(req: ConnectRequest):
    res = state.test_connection(req.url)
    return res

@app.post("/disconnect")
def disconnect_colab():
    state.is_connected = False
    state.log("Đã ngắt kết nối với Colab")
    return {"success": True}

@app.post("/register_tunnel")
def register_tunnel(req: TunnelRegisterRequest):
    """
    Webhook tự động: Khi Colab vừa bật Cloudflare Tunnel,
    Colab sẽ tự động bắn URL vào đây để App tự kết nối ngay lập tức!
    """
    state.log(f"Nhận webhook tự động từ Colab! URL: {req.url}")
    res = state.test_connection(req.url)
    return {"success": True, "registered_url": req.url, "connection": res}

@app.post("/execute_code")
def execute_code(req: ExecuteCodeRequest):
    """
    Thực thi mã Python hoặc lệnh bash trực tiếp trên Colab GPU
    """
    res = state.execute_remote_tool("execute_code", {"code": req.code, "language": req.language})
    return res

@app.post("/parse_pdf")
def parse_pdf(req: ParsePdfRequest):
    """
    Bóc tách PDF bằng MinerU AI trên Colab GPU
    """
    res = state.execute_remote_tool("build_faiss_from_pdf", {
        "pdf_base64": req.pdf_base64,
        "filename": req.filename,
        "doc_type": req.doc_type,
        "google_api_key": req.google_api_key
    }, timeout=400)
    
    # Fallback nếu cần
    if res.get("error") and "Unknown tool" in str(res.get("error")):
        res = state.execute_remote_tool("mineru_parse_pdf", {
            "pdf_base64": req.pdf_base64,
            "filename": req.filename
        }, timeout=400)
        
    return res

# --- MULTI-ACCOUNT MANAGEMENT ---
ACCOUNTS_DIR = Path.home() / ".config" / "colab-cli" / "accounts"
ACCOUNTS_DIR.mkdir(parents=True, exist_ok=True)
ACCOUNTS_INDEX_FILE = ACCOUNTS_DIR / "accounts.json"

GOOGLE_CLIENT_CONFIG = {
    "installed": {
        "client_id": "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com",
        "project_id": "colab-cli",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_secret": "d-FL95Q19q7MQmFpd7hHD0Ty",
        "redirect_uris": ["http://localhost"]
    }
}

PUBLIC_OAUTH_SCOPES = [
    "openid",
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/colaboratory",
    "https://www.googleapis.com/auth/drive.file",
]

class ExchangeTokenRequest(BaseModel):
    code: str

class SwitchAccountRequest(BaseModel):
    email: str

class RemoveAccountRequest(BaseModel):
    email: str

def load_accounts_index() -> Dict[str, Any]:
    if ACCOUNTS_INDEX_FILE.exists():
        try:
            with open(ACCOUNTS_INDEX_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"active_email": "", "accounts": []}

def save_accounts_index(data: Dict[str, Any]):
    try:
        with open(ACCOUNTS_INDEX_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logger.error(f"Lỗi lưu accounts.json: {e}")

def get_account_userinfo(token_data: Dict[str, Any]) -> Dict[str, Any]:
    """Lấy thông tin Google profile từ token_data (refresh nếu hết hạn)"""
    try:
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
        creds = Credentials(
            token=token_data.get("token"),
            refresh_token=token_data.get("refresh_token"),
            token_uri=token_data.get("token_uri", "https://oauth2.googleapis.com/token"),
            client_id=token_data.get("client_id", GOOGLE_CLIENT_CONFIG["installed"]["client_id"]),
            client_secret=token_data.get("client_secret", GOOGLE_CLIENT_CONFIG["installed"]["client_secret"]),
            scopes=PUBLIC_OAUTH_SCOPES
        )
        if creds.expired or not creds.valid:
            try:
                creds.refresh(Request())
                token_data["token"] = creds.token
                token_data["expiry"] = creds.expiry.isoformat() if creds.expiry else ""
            except Exception as re:
                logger.warning(f"Lỗi refresh token: {re}")

        resp = requests.get(
            "https://www.googleapis.com/oauth2/v3/userinfo",
            headers={"Authorization": f"Bearer {creds.token}"},
            timeout=8
        )
        if resp.status_code == 200:
            info = resp.json()
            return {
                "email": info.get("email", ""),
                "name": info.get("name", ""),
                "picture": info.get("picture", ""),
                "updated_token": token_data
            }
    except Exception as e:
        logger.warning(f"Không thể lấy userinfo từ Google: {e}")
    return {"email": "", "name": "", "picture": "", "updated_token": token_data}

def sync_existing_token():
    """Đồng bộ token.json hiện có vào danh sách đa tài khoản nếu chưa có"""
    token_path = Path.home() / ".config" / "colab-cli" / "token.json"
    if not token_path.exists():
        return
    try:
        with open(token_path, "r", encoding="utf-8") as f:
            token_data = json.load(f)
        idx = load_accounts_index()
        info = get_account_userinfo(token_data)
        email = info.get("email")
        if not email:
            return
        account_token_file = ACCOUNTS_DIR / f"{email}.json"
        with open(account_token_file, "w", encoding="utf-8") as f:
            json.dump(info.get("updated_token", token_data), f, ensure_ascii=False, indent=2)

        existing = next((a for a in idx.get("accounts", []) if a.get("email") == email), None)
        if existing:
            existing["name"] = info.get("name") or existing.get("name") or email.split("@")[0]
            existing["picture"] = info.get("picture") or existing.get("picture") or ""
        else:
            idx.setdefault("accounts", []).append({
                "email": email,
                "name": info.get("name") or email.split("@")[0],
                "picture": info.get("picture") or "",
                "status": "ready"
            })
        if not idx.get("active_email"):
            idx["active_email"] = email
        save_accounts_index(idx)
    except Exception as e:
        logger.error(f"Lỗi sync existing token: {e}")

# Chạy sync ngay khi khởi động
sync_existing_token()

@app.get("/auth_status")
def get_auth_status():
    """Kiểm tra trạng thái đăng nhập và danh sách tài khoản Google Colab"""
    sync_existing_token()
    idx = load_accounts_index()
    token_path = Path.home() / ".config" / "colab-cli" / "token.json"
    is_auth = token_path.exists() and len(idx.get("accounts", [])) > 0
    return {
        "authenticated": is_auth,
        "token_path": str(token_path),
        "active_email": idx.get("active_email", ""),
        "accounts": idx.get("accounts", [])
    }

@app.get("/auth_url")
def get_google_auth_url():
    """Tạo đường dẫn đăng nhập Google OAuth2 (buộc hiện màn hình chọn tài khoản prompt=select_account)"""
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
        flow = InstalledAppFlow.from_client_config(GOOGLE_CLIENT_CONFIG, PUBLIC_OAUTH_SCOPES)
        flow.redirect_uri = "https://sdk.cloud.google.com/applicationdefaultauthcode.html"
        auth_url, _ = flow.authorization_url(prompt="select_account consent", token_usage="remote")
        state.oauth_flow = flow
        return {"success": True, "auth_url": auth_url}
    except Exception as e:
        logger.error(f"Lỗi tạo auth url: {e}")
        return {"success": False, "error": str(e)}

@app.post("/exchange_token")
def exchange_google_token(req: ExchangeTokenRequest):
    """Xác thực mã Authorization Code, lấy email và lưu vào danh sách đa tài khoản"""
    try:
        if not state.oauth_flow:
            raise ValueError("Không tìm thấy phiên xác thực OAuth đang chờ. Vui lòng bấm mở lại link đăng nhập.")

        state.oauth_flow.fetch_token(code=req.code.strip())
        creds = state.oauth_flow.credentials
        token_data = json.loads(creds.to_json())

        # Lấy thông tin user (email, avatar)
        info = get_account_userinfo(token_data)
        email = info.get("email") or f"user_{int(time.time())}@google.com"
        name = info.get("name") or email.split("@")[0]
        picture = info.get("picture") or ""
        saved_token = info.get("updated_token", token_data)

        # Lưu token riêng theo email
        account_token_file = ACCOUNTS_DIR / f"{email}.json"
        with open(account_token_file, "w", encoding="utf-8") as f:
            json.dump(saved_token, f, ensure_ascii=False, indent=2)

        # Cập nhật token.json chính cho colab-cli
        token_dir = Path.home() / ".config" / "colab-cli"
        token_dir.mkdir(parents=True, exist_ok=True)
        main_token_file = token_dir / "token.json"
        with open(main_token_file, "w", encoding="utf-8") as f:
            json.dump(saved_token, f, ensure_ascii=False, indent=2)

        # Cập nhật danh sách accounts
        idx = load_accounts_index()
        existing = next((a for a in idx.get("accounts", []) if a.get("email") == email), None)
        if existing:
            existing["name"] = name
            existing["picture"] = picture
            existing["status"] = "ready"
        else:
            idx.setdefault("accounts", []).append({
                "email": email,
                "name": name,
                "picture": picture,
                "status": "ready"
            })
        idx["active_email"] = email
        save_accounts_index(idx)

        state.log(f"Đã liên kết tài khoản Google Colab: {email} ({name})")
        return {
            "success": True,
            "message": f"Đã liên kết tài khoản {email} thành công!",
            "account": {"email": email, "name": name, "picture": picture},
            "accounts": idx.get("accounts", []),
            "active_email": email
        }
    except Exception as e:
        logger.error(f"Lỗi exchange token: {e}")
        return {"success": False, "error": str(e)}

@app.post("/switch_account")
def switch_google_account(req: SwitchAccountRequest):
    """Chuyển đổi tài khoản Google Colab đang hoạt động"""
    target_email = req.email.strip()
    account_token_file = ACCOUNTS_DIR / f"{target_email}.json"
    if not account_token_file.exists():
        return {"success": False, "error": f"Không tìm thấy token của tài khoản: {target_email}"}

    try:
        with open(account_token_file, "r", encoding="utf-8") as f:
            token_data = json.load(f)

        main_token_file = Path.home() / ".config" / "colab-cli" / "token.json"
        with open(main_token_file, "w", encoding="utf-8") as f:
            json.dump(token_data, f, ensure_ascii=False, indent=2)

        idx = load_accounts_index()
        idx["active_email"] = target_email
        for acc in idx.get("accounts", []):
            if acc.get("email") == target_email:
                acc["status"] = "active"
            elif acc.get("status") == "active":
                acc["status"] = "ready"
        save_accounts_index(idx)

        state.log(f"Đã chuyển sang tài khoản Colab: {target_email}")
        return {"success": True, "active_email": target_email, "accounts": idx.get("accounts", [])}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/remove_account")
def remove_google_account(req: RemoveAccountRequest):
    """Xóa tài khoản khỏi danh sách"""
    target_email = req.email.strip()
    account_token_file = ACCOUNTS_DIR / f"{target_email}.json"
    if account_token_file.exists():
        try:
            account_token_file.unlink()
        except Exception:
            pass

    idx = load_accounts_index()
    idx["accounts"] = [a for a in idx.get("accounts", []) if a.get("email") != target_email]
    if idx.get("active_email") == target_email:
        if len(idx["accounts"]) > 0:
            new_active = idx["accounts"][0]["email"]
            idx["active_email"] = new_active
            new_file = ACCOUNTS_DIR / f"{new_active}.json"
            if new_file.exists():
                with open(new_file, "r") as nf, open(Path.home() / ".config" / "colab-cli" / "token.json", "w") as tf:
                    tf.write(nf.read())
        else:
            idx["active_email"] = ""
            main_token = Path.home() / ".config" / "colab-cli" / "token.json"
            if main_token.exists():
                main_token.unlink()

    save_accounts_index(idx)
    state.log(f"Đã xóa tài khoản: {target_email}")
    return {"success": True, "active_email": idx.get("active_email", ""), "accounts": idx.get("accounts", [])}

def format_colab_cli_error(raw_err: str) -> str:
    if not raw_err:
        return "Lỗi tạo phiên Colab không xác định."
    if "TooManyAssignmentsError" in raw_err or "412" in raw_err or "Too many assignments" in raw_err:
        return "Tài khoản Google đã đạt giới hạn cấp phát GPU hôm nay từ Google Colab. Vui lòng đổi sang tài khoản Google khác."
    if "Unauthenticated" in raw_err or "401" in raw_err or "invalid_grant" in raw_err:
        return "Phiên đăng nhập Google Colab đã hết hạn. Vui lòng liên kết lại mã xác thực Google Colab."
    if "ResourceExhausted" in raw_err or "no accelerators" in raw_err.lower():
        return "Google Colab hiện đang hết tài nguyên GPU T4 miễn phí. Vui lòng thử lại sau."
    clean_lines = [line.strip().strip("|").strip() for line in raw_err.split("\n") if line.strip() and not line.strip().startswith("Traceback") and not line.strip().startswith("File ") and not "site-packages" in line]
    for line in reversed(clean_lines):
        if line and not line.startswith("|") and len(line) > 5:
            return line[:120]
    return raw_err[:120]

def try_allocate_gpu_with_account_rotation(colab_bin: str) -> Dict[str, Any]:
    """Thử khởi tạo GPU T4. Nếu tài khoản đạt giới hạn quota, tự động luân phiên sang tài khoản khác"""
    import subprocess
    idx = load_accounts_index()
    accounts = idx.get("accounts", [])
    active_email = idx.get("active_email", "")

    # Sắp xếp danh sách tài khoản, đưa tài khoản đang active lên đầu
    ordered_accounts = []
    if active_email:
        curr = next((a for a in accounts if a.get("email") == active_email), None)
        if curr:
            ordered_accounts.append(curr)
    for a in accounts:
        if a not in ordered_accounts:
            ordered_accounts.append(a)

    if not ordered_accounts:
        # Thử với token.json mặc định
        state.log("Đang tạo mới Colab VM GPU T4 (colab new -s aitype --gpu T4)...")
        n_res = subprocess.run([colab_bin, "new", "-s", "aitype", "--gpu", "T4"], capture_output=True, text=True, timeout=90)
        if n_res.returncode != 0:
            return {"success": False, "error": format_colab_cli_error(n_res.stderr or n_res.stdout)}
        return {"success": True}

    last_error = ""
    for acc in ordered_accounts:
        email = acc.get("email")
        state.log(f"Đang kiểm tra và kích hoạt tài khoản Colab: {email}...")
        
        # Nạp token của tài khoản này vào token.json
        acc_file = ACCOUNTS_DIR / f"{email}.json"
        if acc_file.exists():
            with open(acc_file, "r") as af, open(Path.home() / ".config" / "colab-cli" / "token.json", "w") as tf:
                tf.write(af.read())
            idx["active_email"] = email
            save_accounts_index(idx)

        state.log(f"Thử cấp phát Colab VM GPU T4 với tài khoản {email}...")
        n_res = subprocess.run([colab_bin, "new", "-s", "aitype", "--gpu", "T4"], capture_output=True, text=True, timeout=90)
        if n_res.returncode == 0:
            acc["status"] = "active"
            save_accounts_index(idx)
            state.log(f"Đã cấp phát máy ảo GPU T4 thành công với tài khoản: {email}!")
            return {"success": True, "active_email": email}

        raw_out = (n_res.stderr or "") + "\n" + (n_res.stdout or "")
        clean_err = format_colab_cli_error(raw_out)
        last_error = clean_err

        # Đánh dấu trạng thái tài khoản
        if "TooManyAssignmentsError" in raw_out or "412" in raw_out or "Too many assignments" in raw_out:
            acc["status"] = "limit_reached"
            state.log(f"Tài khoản {email} đã đạt giới hạn quota Colab hôm nay. Đang chuyển sang tài khoản tiếp theo...")
            save_accounts_index(idx)
            continue
        elif "Unauthenticated" in raw_out or "401" in raw_out:
            acc["status"] = "expired"
            save_accounts_index(idx)
            continue
        else:
            return {"success": False, "error": clean_err}

    return {"success": False, "error": f"Tất cả tài khoản Google đã đạt giới hạn hôm nay: {last_error}"}

@app.post("/start_gpu")
def start_gpu_session():
    """Khởi chạy VM GPU qua Google Colab CLI và kết nối Tunnel tự động (hỗ trợ luân chuyển tài khoản)"""
    import subprocess
    import re
    try:
        colab_bin = os.path.expanduser("~/.local/bin/colab")
        if not os.path.exists(colab_bin):
            colab_bin = "colab"

        # 1. Kiểm tra session hiện có
        state.log("Đang kiểm tra phiên Colab GPU hiện có...")
        s_res = subprocess.run([colab_bin, "sessions"], capture_output=True, text=True, timeout=15)
        has_aitype = "aitype" in (s_res.stdout or "")
        if not has_aitype:
            alloc_res = try_allocate_gpu_with_account_rotation(colab_bin)
            if not alloc_res.get("success"):
                return alloc_res

        # 2. Thực thi script worker nền trên session aitype
        state.log("Đang khởi động MinerU GPU & Cloudflare Tunnel trên Colab...")
        script_candidates = [
            Path(__file__).resolve().parent / "colab_mineru_mcp.py",
            Path.home() / "Documents" / "Projects" / "Typing" / "ai.type" / "electron" / "scripts" / "colab_mineru_mcp.py",
            Path.home() / "Documents" / "ai.type" / "plugins" / "colab_mineru_mcp.py"
        ]
        script_path = None
        for p in script_candidates:
            if p.exists():
                script_path = p
                break

        if not script_path:
            return {"success": False, "error": "Không tìm thấy script colab_mineru_mcp.py"}

        e_res = subprocess.run([colab_bin, "exec", "-s", "aitype", "-f", str(script_path), "--timeout", "60"], capture_output=True, text=True, timeout=75)
        out = (e_res.stdout or "") + "\n" + (e_res.stderr or "")
        state.log(f"Colab exec output:\n{out}")

        # 3. Trích xuất URL Cloudflare
        match = re.search(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", out)
        if match:
            tunnel_url = match.group(0)
            state.log(f"Tìm thấy URL Colab Tunnel: {tunnel_url}. Đang kiểm tra kết nối...")
            time.sleep(2)
            conn_res = state.test_connection(tunnel_url)
            if conn_res.get("success"):
                return {"success": True, "url": tunnel_url, "gpu": state.gpu_info, "tools": state.available_tools}
            else:
                time.sleep(3)
                conn_res = state.test_connection(tunnel_url)
                return {"success": conn_res.get("success", False), "url": tunnel_url, "gpu": state.gpu_info, "error": conn_res.get("error")}

        return {"success": False, "error": f"Không tìm thấy URL Cloudflare trong output: {out[:200]}"}
    except Exception as e:
        logger.error(f"Lỗi khởi chạy GPU: {e}")
        return {"success": False, "error": str(e)}

@app.post("/stop_gpu")
def stop_gpu_session():
    """Dừng và giải phóng Colab VM GPU"""
    import subprocess
    try:
        colab_bin = os.path.expanduser("~/.local/bin/colab")
        if not os.path.exists(colab_bin):
            colab_bin = "colab"
        state.log("Đang dừng Colab VM GPU (colab stop -s aitype)...")
        res = subprocess.run([colab_bin, "stop", "-s", "aitype"], capture_output=True, text=True, timeout=30)
        state.is_connected = False
        return {"success": True, "stdout": res.stdout}
    except Exception as e:
        return {"success": False, "error": str(e)}

def main():
    parser = argparse.ArgumentParser(description="ai.type Colab Agent Plugin")
    parser.add_argument("-v", "--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument("--port", type=int, default=7868, help="Port to listen on (default 7868)")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Host (default 127.0.0.1)")
    parser.add_argument("--url", type=str, default="", help="Initial Colab URL")
    args = parser.parse_args()

    if args.url:
        state.colab_url = args.url
        state.test_connection(args.url)
    elif state.colab_url:
        state.test_connection()

    logger.info(f"Khởi động Colab Agent Plugin v{__version__} trên http://{args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")

if __name__ == "__main__":
    main()
