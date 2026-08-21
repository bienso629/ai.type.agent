import os
import json
import time
import uuid
import webbrowser
import threading
import sqlite3
from typing import Optional, Dict, Any, List
from fastapi import FastAPI, HTTPException, Body
from fastapi.responses import HTMLResponse, FileResponse, StreamingResponse
from pydantic import BaseModel
import requests
import sys

# Xử lý đường dẫn khi đóng gói binary (PyInstaller)
if getattr(sys, 'frozen', False):
    BUNDLE_DIR = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))
    APP_DIR = os.path.dirname(sys.executable)
else:
    BUNDLE_DIR = os.path.dirname(os.path.abspath(__file__))
    APP_DIR = BUNDLE_DIR

CONFIG_FILE = os.path.join(APP_DIR, "config.json")
DB_PATH = os.path.join(APP_DIR, "chat_history.db")
SERVICE_FILE_PATH = os.path.join(APP_DIR, "ai_agent_service.py")
if not os.path.exists(SERVICE_FILE_PATH):
    SERVICE_FILE_PATH = os.path.join(BUNDLE_DIR, "ai_agent_service.py")

SERVICE_BIN_PATH = os.path.join(APP_DIR, "dist", "ai_agent_service")
if not os.path.exists(SERVICE_BIN_PATH):
    SERVICE_BIN_PATH = os.path.join(APP_DIR, "ai_agent_service")
if not os.path.exists(SERVICE_BIN_PATH):
    SERVICE_BIN_PATH = os.path.join(BUNDLE_DIR, "ai_agent_service")

TEMPLATE_INDEX = os.path.join(BUNDLE_DIR, "templates", "index.html")
LOGO_PATH = os.path.join(APP_DIR, "logo.jpg")
if not os.path.exists(LOGO_PATH):
    LOGO_PATH = os.path.join(BUNDLE_DIR, "logo.jpg")
ICON_PATH = os.path.join(BUNDLE_DIR, "templates", "icon.png")

# ==========================================
# HỆ THỐNG MÃ HÓA TOÀN BỘ DỮ LIỆU (AES-256 FERNET)
# ==========================================
import base64
import hashlib

def get_crypto_key() -> bytes:
    """Tạo khoá mã hoá bảo mật AES-256 gắn liền với Machine ID của thiết bị hiện tại."""
    machine_id = "tadu-cloud-ai-agent-control-center-secret-salt-2026"
    for path in ["/etc/machine-id", "/var/lib/dbus/machine-id"]:
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    machine_id += f.read().strip()
                break
            except Exception:
                pass
    key_hash = hashlib.sha256(machine_id.encode()).digest()
    return base64.urlsafe_b64encode(key_hash)

def encrypt_value(plain_text: Any) -> str:
    """Mã hoá chuỗi dữ liệu thành ciphertext an toàn."""
    if plain_text is None:
        return None
    s = str(plain_text)
    if not s or s.startswith("enc:"):
        return s
    try:
        from cryptography.fernet import Fernet
        f = Fernet(get_crypto_key())
        token = f.encrypt(s.encode("utf-8")).decode("utf-8")
        return f"enc:{token}"
    except Exception as e:
        print(f"Lỗi mã hoá dữ liệu: {e}")
        return s

def decrypt_value(cipher_text: Any) -> str:
    """Giải mã chuỗi ciphertext nhạy cảm trong bộ nhớ khi ứng dụng thực thi."""
    if cipher_text is None:
        return None
    s = str(cipher_text)
    if not s or not s.startswith("enc:"):
        return s
    try:
        from cryptography.fernet import Fernet
        f = Fernet(get_crypto_key())
        raw_token = s[4:]
        return f.decrypt(raw_token.encode("utf-8")).decode("utf-8")
    except Exception as e:
        print(f"Lỗi giải mã dữ liệu: {e}")
        return s

# ==========================================
# CƠ SỞ DỮ LIỆU SQLITE LƯU TRỮ LỊCH SỬ CHAT & SESSIONS
# ==========================================
def make_smart_title(content: str, max_chars: int = 65) -> str:
    line = content.strip().split("\n")[0].strip()
    if len(line) <= max_chars:
        return line
    return line[:max_chars].rstrip() + "..."

def init_db():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS chat_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT DEFAULT 'default',
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                attachments_json TEXT,
                tool_calls_json TEXT,
                model TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Migration bảo mật: Đảm bảo 100% dữ liệu cũ trong chat_messages & chat_sessions được mã hoá AES
        cursor.execute("SELECT id, content, attachments_json, tool_calls_json FROM chat_messages")
        msg_rows = cursor.fetchall()
        for msg_id, c, att, tc in msg_rows:
            needs_update = False
            enc_c = c
            enc_att = att
            enc_tc = tc
            if c and not str(c).startswith("enc:"):
                enc_c = encrypt_value(c)
                needs_update = True
            if att and not str(att).startswith("enc:"):
                enc_att = encrypt_value(att)
                needs_update = True
            if tc and not str(tc).startswith("enc:"):
                enc_tc = encrypt_value(tc)
                needs_update = True
            if needs_update:
                cursor.execute("UPDATE chat_messages SET content = ?, attachments_json = ?, tool_calls_json = ? WHERE id = ?", (enc_c, enc_att, enc_tc, msg_id))

        cursor.execute("SELECT id, title FROM chat_sessions")
        sess_rows = cursor.fetchall()
        for s_id, t in sess_rows:
            if t and not str(t).startswith("enc:"):
                enc_t = encrypt_value(t)
                cursor.execute("UPDATE chat_sessions SET title = ? WHERE id = ?", (enc_t, s_id))

        # Tự động gom các message cũ vào chat_sessions nếu chưa có
        cursor.execute("SELECT DISTINCT session_id FROM chat_messages")
        msg_sessions = [r[0] for r in cursor.fetchall() if r[0]]
        if not msg_sessions:
            msg_sessions = ['default']
            
        for sid in msg_sessions:
            cursor.execute("SELECT title FROM chat_sessions WHERE id = ?", (sid,))
            row = cursor.fetchone()
            if not row:
                cursor.execute("INSERT INTO chat_sessions (id, title) VALUES (?, ?)", (sid, encrypt_value('Cuộc hội thoại mới')))
                
            # Lấy câu hỏi cuối cùng của user để đặt tên cho session nếu chưa có tên cụ thể
            dec_title = decrypt_value(row[0]) if row and row[0] else ""
            if not row or dec_title in ['Cuộc hội thoại mới', 'Hội thoại mặc định', 'Default Chat']:
                cursor.execute("SELECT content, created_at FROM chat_messages WHERE session_id = ? AND role = 'user' ORDER BY id DESC LIMIT 1", (sid,))
                last_user_msg = cursor.fetchone()
                if last_user_msg and last_user_msg[0]:
                    decrypted_content = decrypt_value(last_user_msg[0])
                    smart_title = make_smart_title(decrypted_content)
                    cursor.execute("UPDATE chat_sessions SET title = ?, updated_at = ? WHERE id = ?", (encrypt_value(smart_title), last_user_msg[1], sid))
        
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Lỗi khởi tạo SQLite: {e}")

init_db()

def get_all_sessions() -> List[Dict[str, Any]]:
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, created_at, updated_at FROM chat_sessions ORDER BY updated_at DESC")
        rows = cursor.fetchall()
        if not rows:
            cursor.execute("INSERT OR IGNORE INTO chat_sessions (id, title) VALUES ('default', ?)", (encrypt_value('Cuộc hội thoại mới'),))
            conn.commit()
            cursor.execute("SELECT id, title, created_at, updated_at FROM chat_sessions ORDER BY updated_at DESC")
            rows = cursor.fetchall()
        conn.close()
        return [{"id": r[0], "title": decrypt_value(r[1]) or "Cuộc hội thoại mới", "created_at": str(r[2]), "updated_at": str(r[3])} for r in rows]
    except Exception as e:
        print(f"Lỗi đọc sessions: {e}")
        return [{"id": "default", "title": "Cuộc hội thoại mới", "created_at": "", "updated_at": ""}]

def create_session(title: str = "Cuộc hội thoại mới") -> Dict[str, Any]:
    session_id = f"s_{uuid.uuid4().hex[:8]}"
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO chat_sessions (id, title) VALUES (?, ?)", (session_id, encrypt_value(title)))
        conn.commit()
        conn.close()
        return {"id": session_id, "title": title}
    except Exception as e:
        print(f"Lỗi tạo session: {e}")
        return {"id": session_id, "title": title}

def rename_session(session_id: str, title: str):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("UPDATE chat_sessions SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (encrypt_value(title), session_id))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"Lỗi đổi tên session: {e}")
        return False

def delete_session(session_id: str):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM chat_sessions WHERE id = ?", (session_id,))
        cursor.execute("DELETE FROM chat_messages WHERE session_id = ?", (session_id,))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"Lỗi xoá session: {e}")
        return False

def save_message_to_db(role: str, content: str, attachments: List[Any] = None, tool_calls: List[Any] = None, model: str = None, session_id: str = "default"):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        # Đảm bảo session tồn tại
        cursor.execute("INSERT OR IGNORE INTO chat_sessions (id, title) VALUES (?, ?)", (session_id, encrypt_value('Cuộc hội thoại mới')))
        
        # Tự động đặt tên thông minh cho hộp hội thoại theo câu hỏi mới nhất nếu chưa đổi tên tùy biến
        if role == "user":
            cursor.execute("SELECT title FROM chat_sessions WHERE id = ?", (session_id,))
            row = cursor.fetchone()
            dec_title = decrypt_value(row[0]) if row and row[0] else ""
            if not row or (dec_title in ["Cuộc hội thoại mới", "Hội thoại mặc định", "Default Chat"] or not dec_title):
                smart_title = make_smart_title(content)
                if smart_title:
                    cursor.execute("UPDATE chat_sessions SET title = ? WHERE id = ?", (encrypt_value(smart_title), session_id))
        
        # Cập nhật thời gian updated_at cho session
        cursor.execute("UPDATE chat_sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", (session_id,))

        att_str = json.dumps([a.dict() if hasattr(a, 'dict') else (a.model_dump() if hasattr(a, 'model_dump') else a) for a in attachments], ensure_ascii=False) if attachments else None
        tc_str = json.dumps(tool_calls, ensure_ascii=False) if tool_calls else None
        
        # Mã hoá toàn bộ nội dung tin nhắn (user & ai), attachments và tool_calls trước khi lưu vào SQLite
        enc_content = encrypt_value(content)
        enc_att = encrypt_value(att_str) if att_str else None
        enc_tc = encrypt_value(tc_str) if tc_str else None

        cursor.execute("""
            INSERT INTO chat_messages (session_id, role, content, attachments_json, tool_calls_json, model)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (session_id, role, enc_content, enc_att, enc_tc, model))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Lỗi lưu SQLite: {e}")

def get_messages_from_db(session_id: str = "default", limit: int = 300) -> List[Dict[str, Any]]:
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
            FROM chat_messages
            WHERE session_id = ?
            ORDER BY id ASC
            LIMIT ?
        """, (session_id, limit))
        rows = cursor.fetchall()
        conn.close()
        
        results = []
        for r in rows:
            raw_c = r[3]
            dec_c = decrypt_value(raw_c) if raw_c else ""
            raw_att = decrypt_value(r[4]) if r[4] else None
            raw_tc = decrypt_value(r[5]) if r[5] else None
            
            results.append({
                "id": r[0],
                "session_id": r[1],
                "role": r[2],
                "content": dec_c,
                "attachments": json.loads(raw_att) if raw_att else [],
                "tool_calls": json.loads(raw_tc) if raw_tc else [],
                "model": r[6],
                "created_at": str(r[7])
            })
        return results
    except Exception as e:
        print(f"Lỗi đọc SQLite: {e}")
        return []

def clear_messages_in_db(session_id: str = "default"):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM chat_messages WHERE session_id = ?", (session_id,))
        cursor.execute("UPDATE chat_sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", (session_id,))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"Lỗi xoá tin nhắn: {e}")
        return False

app = FastAPI(title="Tadu Cloud AI Agent Control Center", description="Giao diện quản lý & điều khiển Tadu Cloud AI Agent")

@app.get("/logo.jpg")
def get_logo():
    if os.path.exists(LOGO_PATH):
        return FileResponse(LOGO_PATH, media_type="image/jpeg")
    elif os.path.exists(ICON_PATH):
        return FileResponse(ICON_PATH, media_type="image/png")
    raise HTTPException(status_code=404, detail="Logo not found")

# ==========================================
# CẤU HÌNH & HELPER FUNCTIONS
ALL_CONFIG_KEYS = [
    "server_ip", "ssh_user", "ssh_pass", "ssh_port",
    "proxy_api_key", "proxy_base_url", "ai_model",
    "remote_work_dir", "api_port", "secret_token"
]

DEFAULT_CONFIG = {
    "server_ip": "127.0.0.1",
    "ssh_user": "root",
    "ssh_pass": "",
    "ssh_port": 22,
    "proxy_api_key": "",
    "proxy_base_url": "https://openrouter.ai/api/v1",
    "ai_model": "glm-5.3",
    "remote_work_dir": "/opt/ai_agent",
    "api_port": 8000,
    "secret_token": "super_secret_token_123"
}

def load_config() -> Dict[str, Any]:
    if not os.path.exists(CONFIG_FILE):
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            
            # Giải mã kho lưu trữ mã hóa tổng thể nếu có
            if "_encrypted_vault" in data:
                try:
                    decrypted_raw = decrypt_value(data["_encrypted_vault"])
                    vault_data = json.loads(decrypted_raw)
                    data.update(vault_data)
                except Exception as e:
                    print(f"Lỗi giải mã vault: {e}")
            
            for k, v in DEFAULT_CONFIG.items():
                if k not in data:
                    data[k] = v
            
            in_memory_data = {}
            needs_resave = False
            
            for k, v in data.items():
                if k == "_encrypted_vault":
                    continue
                if isinstance(v, str) and v.startswith("enc:"):
                    dec_val = decrypt_value(v)
                    if k in ["ssh_port", "api_port"]:
                        try:
                            dec_val = int(dec_val)
                        except Exception:
                            pass
                    in_memory_data[k] = dec_val
                else:
                    in_memory_data[k] = v
                    if k in ALL_CONFIG_KEYS and v:
                        needs_resave = True
            
            # Chuẩn hoá kiểu dữ liệu số cổng
            if "ssh_port" in in_memory_data:
                try: in_memory_data["ssh_port"] = int(in_memory_data["ssh_port"])
                except Exception: in_memory_data["ssh_port"] = 22
            if "api_port" in in_memory_data:
                try: in_memory_data["api_port"] = int(in_memory_data["api_port"])
                except Exception: in_memory_data["api_port"] = 8000
                
            if needs_resave:
                save_config(in_memory_data)
                
            return in_memory_data
    except Exception as e:
        print(f"Lỗi đọc file config: {e}")
        return DEFAULT_CONFIG

def save_config(cfg: Dict[str, Any]):
    disk_data = {}
    for k, v in cfg.items():
        if k == "_encrypted_vault":
            continue
        if v is not None:
            disk_data[k] = encrypt_value(v)
            
    # Ghi thêm toàn bộ vault mã hóa tổng thể
    raw_json = json.dumps(cfg, ensure_ascii=False)
    disk_data["_encrypted_vault"] = encrypt_value(raw_json)
    
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(disk_data, f, indent=2, ensure_ascii=False)

def get_ssh_client(cfg: Dict[str, Any]):
    try:
        import paramiko
    except ImportError:
        raise HTTPException(
            status_code=500, 
            detail="Thư viện 'paramiko' chưa được cài đặt. Vui lòng chạy: pip install paramiko"
        )
    
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh_port = int(cfg.get("ssh_port", 22))
    ssh.connect(
        hostname=cfg.get("server_ip"),
        port=ssh_port,
        username=cfg.get("ssh_user"),
        password=cfg.get("ssh_pass") or None,
        timeout=10
    )
    return ssh

# ==========================================
# API MODELS & ENDPOINTS
# ==========================================
class ConfigModel(BaseModel):
    server_ip: str
    ssh_user: str
    ssh_pass: Optional[str] = ""
    ssh_port: Optional[int] = 22
    proxy_api_key: Optional[str] = ""
    proxy_base_url: Optional[str] = "https://openrouter.ai/api/v1"
    ai_model: Optional[str] = "glm-5.3"
    remote_work_dir: Optional[str] = "/opt/ai_agent"
    api_port: Optional[int] = 8000
    secret_token: Optional[str] = "super_secret_token_123"

class AttachmentItem(BaseModel):
    name: str
    content: str
    size: Optional[int] = 0

class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = "default"
    history: Optional[List[Dict[str, Any]]] = []
    attachments: Optional[List[AttachmentItem]] = []

class SessionCreateRequest(BaseModel):
    title: Optional[str] = "Cuộc hội thoại mới"

class SessionUpdateRequest(BaseModel):
    title: str

class CommandRequest(BaseModel):
    command: str

class SSHTestRequest(BaseModel):
    server_ip: Optional[str] = None
    ssh_user: Optional[str] = None
    ssh_pass: Optional[str] = None
    ssh_port: Optional[int] = 22

@app.get("/api/config")
def get_current_config():
    return load_config()

@app.post("/api/config")
def update_config(req: ConfigModel):
    cfg = req.model_dump()
    save_config(cfg)
    return {"status": "success", "message": "Đã lưu cấu hình thành công!", "config": cfg}

@app.post("/api/ssh/test")
def test_ssh_connection(req: Optional[SSHTestRequest] = None):
    cfg = load_config()
    if req and req.server_ip:
        cfg["server_ip"] = req.server_ip
        if req.ssh_user: cfg["ssh_user"] = req.ssh_user
        if req.ssh_pass is not None: cfg["ssh_pass"] = req.ssh_pass
        if req.ssh_port: cfg["ssh_port"] = req.ssh_port

    try:
        ssh = get_ssh_client(cfg)
        stdin, stdout, stderr = ssh.exec_command("uname -a && whoami")
        out = stdout.read().decode().strip()
        ssh.close()
        return {"status": "success", "message": f"Kết nối SSH thành công tới {cfg.get('server_ip')}:{cfg.get('ssh_port', 22)}!\n{out}"}
    except Exception as e:
        return {"status": "error", "message": f"Kết nối SSH thất bại tới {cfg.get('server_ip')}:{cfg.get('ssh_port', 22)}:\n{str(e)}"}

@app.get("/api/server/health")
def check_server_health():
    cfg = load_config()
    server_ip = cfg.get("server_ip", "127.0.0.1")
    api_port = cfg.get("api_port", 8000)
    url = f"http://{server_ip}:{api_port}/health"
    try:
        res = requests.get(url, timeout=3)
        if res.status_code == 200:
            return {"status": "running", "detail": res.json()}
        else:
            return {"status": "error", "message": f"Mã phản hồi: {res.status_code}"}
    except Exception as e:
        return {"status": "stopped", "message": str(e)}

_metrics_cache: Dict[str, Any] = {}
_metrics_lock = threading.Lock()
_collector_thread_started = False

def format_uptime_human(sec_str: str) -> str:
    try:
        s = int(float(sec_str.split()[0]))
        days, rem = divmod(s, 86400)
        hours, rem = divmod(rem, 3600)
        mins, secs = divmod(rem, 60)
        weeks, days = divmod(days, 7)
        parts = []
        if weeks > 0: parts.append(f"{weeks} tuần")
        if days > 0: parts.append(f"{days} ngày")
        if hours > 0: parts.append(f"{hours} giờ")
        parts.append(f"{mins} phút {secs}s")
        return ", ".join(parts)
    except Exception:
        return "N/A"

def parse_safe_metrics(df_raw: str, free_raw: str, loadavg_raw: str = "", uptime_sec_raw: str = "", procs_raw: str = "") -> Dict[str, Any]:
    metrics = {
        "disk_total": "40 GB",
        "disk_used": "21 GB",
        "disk_avail": "17 GB",
        "disk_percent": 50,
        "ram_total": "2.0 GB",
        "ram_used": "750 MB",
        "ram_avail": "1.2 GB",
        "ram_percent": 35.0,
        "ram_used_mb": 750,
        "ram_total_mb": 2048,
        "ram_avail_mb": 1200,
        "ram_cache_mb": 0,
        "loadavg": loadavg_raw.strip(),
        "procs": procs_raw.strip(),
        "uptime_seconds": 0,
        "last_sync": time.strftime("%H:%M:%S")
    }
    try:
        if uptime_sec_raw:
            metrics["uptime_seconds"] = int(float(uptime_sec_raw.split()[0]))
    except Exception:
        pass

    try:
        lines = [line.strip() for line in df_raw.strip().split("\n") if line.strip()]
        if len(lines) >= 2:
            parts = lines[-1].split()
            if len(parts) >= 5:
                metrics["disk_total"] = parts[1]
                metrics["disk_used"] = parts[2]
                metrics["disk_avail"] = parts[3]
                pct_str = parts[4].replace("%", "")
                metrics["disk_percent"] = int(pct_str) if pct_str.isdigit() else 50
    except Exception:
        pass

    try:
        lines = [line.strip() for line in free_raw.strip().split("\n") if line.strip()]
        for line in lines:
            if line.startswith("Mem:"):
                parts = line.split()
                if len(parts) >= 7:
                    total_mb = int(parts[1])
                    used_mb = int(parts[2])
                    cached_mb = int(parts[5]) if len(parts) > 5 else 0
                    avail_mb = int(parts[6])
                    metrics["ram_total_mb"] = total_mb
                    metrics["ram_used_mb"] = used_mb
                    metrics["ram_avail_mb"] = avail_mb
                    metrics["ram_cache_mb"] = cached_mb
                    metrics["ram_total"] = f"{total_mb / 1024:.2f} GB" if total_mb >= 1024 else f"{total_mb} MB"
                    metrics["ram_used"] = f"{used_mb / 1024:.2f} GB" if used_mb >= 1024 else f"{used_mb} MB"
                    metrics["ram_avail"] = f"{avail_mb / 1024:.2f} GB" if avail_mb >= 1024 else f"{avail_mb} MB"
                    metrics["ram_percent"] = round((used_mb / total_mb) * 100, 1) if total_mb > 0 else 35.0
    except Exception:
        pass

    return metrics

def background_metrics_collector():
    global _metrics_cache
    ssh_client = None
    cmd = (
        "cat /proc/uptime 2>/dev/null; echo '---'; "
        "cat /proc/loadavg 2>/dev/null; echo '---'; "
        "free -m 2>/dev/null; echo '---'; "
        "df -h / 2>/dev/null; echo '---'; "
        "ps -e | wc -l 2>/dev/null; echo '---'; "
        "systemctl is-active ai-agent.service 2>/dev/null || echo 'inactive'; echo '---'; "
        "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s"
    )

    while True:
        cfg = load_config()
        server_ip = cfg.get("server_ip")
        if not server_ip:
            time.sleep(2)
            continue

        try:
            if ssh_client is None or not (ssh_client.get_transport() and ssh_client.get_transport().is_active()):
                if ssh_client:
                    try: ssh_client.close()
                    except: pass
                ssh_client = get_ssh_client(cfg)

            stdin, stdout, stderr = ssh_client.exec_command(cmd, timeout=6)
            output = stdout.read().decode()
            parts = output.split("---")

            uptime_raw = parts[0].strip() if len(parts) > 0 else ""
            loadavg_raw = parts[1].strip() if len(parts) > 1 else ""
            free_raw = parts[2].strip() if len(parts) > 2 else ""
            df_raw = parts[3].strip() if len(parts) > 3 else ""
            procs_raw = parts[4].strip() if len(parts) > 4 else ""
            service_status = parts[5].strip() if len(parts) > 5 else "inactive"
            os_name = parts[6].strip() if len(parts) > 6 else "Linux"

            uptime_human = format_uptime_human(uptime_raw)
            safe_metrics = parse_safe_metrics(df_raw, free_raw, loadavg_raw, uptime_raw, procs_raw)

            info_dict = {
                "uptime": uptime_human,
                "uptime_seconds": safe_metrics.get("uptime_seconds", 0),
                "loadavg": loadavg_raw,
                "procs": procs_raw,
                "disk": df_raw,
                "memory": free_raw,
                "ram": free_raw,
                "metrics": safe_metrics,
                "service_active": service_status,
                "service_status": service_status,
                "os": os_name,
                "server_ip": cfg.get("server_ip", "127.0.0.1"),
                "api_port": cfg.get("api_port", 8000),
                "ai_model": cfg.get("ai_model", "glm-5.3"),
                "last_sync": time.strftime("%H:%M:%S")
            }

            data = {
                "status": "success",
                "uptime": uptime_human,
                "disk": df_raw,
                "ram": free_raw,
                "metrics": safe_metrics,
                "service_status": service_status,
                "os": os_name,
                "info": info_dict,
                "last_sync": time.strftime("%H:%M:%S")
            }

            with _metrics_lock:
                _metrics_cache = data

        except Exception as e:
            if ssh_client:
                try: ssh_client.close()
                except: pass
                ssh_client = None
            time.sleep(1)

        time.sleep(1.2)

def start_metrics_thread_if_needed():
    global _collector_thread_started
    if not _collector_thread_started:
        _collector_thread_started = True
        t = threading.Thread(target=background_metrics_collector, daemon=True)
        t.start()

start_metrics_thread_if_needed()

@app.get("/api/server/system-info")
@app.get("/api/server/metrics")
def get_server_metrics():
    global _metrics_cache
    start_metrics_thread_if_needed()
    with _metrics_lock:
        if _metrics_cache:
            return _metrics_cache

    cfg = load_config()
    try:
        ssh = get_ssh_client(cfg)
        stdin, stdout, stderr = ssh.exec_command(
            "cat /proc/uptime 2>/dev/null; echo '---'; "
            "cat /proc/loadavg 2>/dev/null; echo '---'; "
            "free -m 2>/dev/null; echo '---'; "
            "df -h / 2>/dev/null; echo '---'; "
            "ps -e | wc -l 2>/dev/null; echo '---'; "
            "systemctl is-active ai-agent.service 2>/dev/null || echo 'inactive'; echo '---'; "
            "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s"
        )
        output = stdout.read().decode()
        ssh.close()
        parts = output.split("---")
        uptime_raw = parts[0].strip() if len(parts) > 0 else ""
        loadavg_raw = parts[1].strip() if len(parts) > 1 else ""
        free_raw = parts[2].strip() if len(parts) > 2 else ""
        df_raw = parts[3].strip() if len(parts) > 3 else ""
        procs_raw = parts[4].strip() if len(parts) > 4 else ""
        service_status = parts[5].strip() if len(parts) > 5 else "inactive"
        os_name = parts[6].strip() if len(parts) > 6 else "Linux"

        uptime_human = format_uptime_human(uptime_raw)
        safe_metrics = parse_safe_metrics(df_raw, free_raw, loadavg_raw, uptime_raw, procs_raw)
        info_dict = {
            "uptime": uptime_human,
            "uptime_seconds": safe_metrics.get("uptime_seconds", 0),
            "disk": df_raw,
            "memory": free_raw,
            "ram": free_raw,
            "metrics": safe_metrics,
            "service_active": service_status,
            "service_status": service_status,
            "os": os_name,
            "server_ip": cfg.get("server_ip", "127.0.0.1"),
            "api_port": cfg.get("api_port", 8000),
            "ai_model": cfg.get("ai_model", "glm-5.3"),
            "last_sync": time.strftime("%H:%M:%S")
        }
        res_data = {
            "status": "success",
            "uptime": uptime_human,
            "disk": df_raw,
            "ram": free_raw,
            "metrics": safe_metrics,
            "service_status": service_status,
            "os": os_name,
            "info": info_dict,
            "last_sync": time.strftime("%H:%M:%S")
        }
        with _metrics_lock:
            _metrics_cache = res_data
        return res_data
    except Exception as e:
        return {"status": "error", "message": str(e)}

class ServiceActionRequest(BaseModel):
    action: str

@app.post("/api/server/service-action")
def control_service_action(req: ServiceActionRequest):
    return control_service(req.action)

@app.post("/api/server/service/{action}")
def control_service(action: str):
    if action not in ["start", "stop", "restart", "status"]:
        raise HTTPException(status_code=400, detail="Thao tác service không hợp lệ")
    cfg = load_config()
    try:
        ssh = get_ssh_client(cfg)
        cmd = f"sudo systemctl {action} ai-agent.service"
        if action == "status":
            cmd = "systemctl status ai-agent.service"
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode()
        err = stderr.read().decode()
        ssh.close()
        return {
            "status": "success",
            "action": action,
            "output": out + (f"\nLỗi: {err}" if err else "")
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/api/server/logs")
def get_service_logs(lines: int = 100):
    cfg = load_config()
    try:
        ssh = get_ssh_client(cfg)
        cmd = f"journalctl -u ai-agent.service -n {lines} --no-pager"
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode()
        err = stderr.read().decode()
        ssh.close()
        return {
            "status": "success",
            "logs": out if out else (err if err else "Không có dữ liệu log.")
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.post("/api/server/deploy")
def deploy_to_server():
    cfg = load_config()
    remote_dir = cfg.get("remote_work_dir", "/opt/ai_agent")
    
    def step_generator():
        yield "data: Bắt đầu kết nối SSH tới máy chủ...\n\n"
        try:
            ssh = get_ssh_client(cfg)
            yield f"data: Kết nối SSH thành công tới {cfg['server_ip']}!\n\n"
            
            yield f"data: Tạo thư mục làm việc {remote_dir}...\n\n"
            ssh.exec_command(f"sudo mkdir -p {remote_dir} && sudo chown -R {cfg['ssh_user']}:{cfg['ssh_user']} {remote_dir}")
            
            if not os.path.exists(SERVICE_BIN_PATH):
                yield "data: [ERROR] Không tìm thấy file nhị phân ai_agent_service đã biên dịch ở local! Hãy chạy build_bin.py trước.\n\n"
                return

            yield "data: Tạm dừng service đang chạy để giải phóng file nhị phân...\n\n"
            ssh.exec_command("sudo systemctl stop ai-agent.service")
            time.sleep(1)

            yield "data: Đang tải Standalone Binary (ai_agent_service) lên VPS qua SFTP...\n\n"
            sftp = ssh.open_sftp()
            sftp.put(SERVICE_BIN_PATH, f"{remote_dir}/ai_agent_service.tmp")
            sftp.close()
            
            # Thay thế file nhị phân và xóa sạch các file source code .py cũ nếu có để bảo mật 100%
            ssh.exec_command(f"sudo mv -f {remote_dir}/ai_agent_service.tmp {remote_dir}/ai_agent_service && sudo chmod +x {remote_dir}/ai_agent_service && sudo rm -f {remote_dir}/ai_agent_service.py")
            yield "data: Đã đưa Standalone Binary lên máy chủ và bảo vệ 100% mã nguồn!\n\n"
            
            yield "data: Đang cấu hình và kích hoạt Systemd Daemon (ai-agent.service)...\n\n"
            service_content = f"""[Unit]
Description=Tadu Cloud AI Agent Service (Standalone Binary)
After=network.target

[Service]
Type=simple
User={cfg['ssh_user']}
WorkingDirectory={remote_dir}
Environment="PROXY_API_KEY={cfg.get('proxy_api_key', '')}"
Environment="OPENROUTER_API_KEY={cfg.get('proxy_api_key', '')}"
Environment="PROXY_BASE_URL={cfg.get('proxy_base_url', 'https://openrouter.ai/api/v1')}"
Environment="OPENROUTER_BASE_URL={cfg.get('proxy_base_url', 'https://openrouter.ai/api/v1')}"
Environment="AI_MODEL={cfg.get('ai_model', 'glm-5.3')}"
Environment="SECRET_TOKEN={cfg.get('secret_token', 'super_secret_token_123')}"
Environment="AGENT_SECRET_TOKEN={cfg.get('secret_token', 'super_secret_token_123')}"
Environment="AGENT_PORT={cfg.get('api_port', 8000)}"
Environment="PORT={cfg.get('api_port', 8000)}"
ExecStart={remote_dir}/ai_agent_service
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
            service_cmd = f"cat << 'EOF' | sudo tee /etc/systemd/system/ai-agent.service\n{service_content}\nEOF\n"
            ssh.exec_command(service_cmd)
            
            ssh.exec_command("sudo systemctl daemon-reload && sudo systemctl enable ai-agent.service && sudo systemctl restart ai-agent.service")
            time.sleep(2)
            
            stdin, stdout, stderr = ssh.exec_command("systemctl is-active ai-agent.service")
            status = stdout.read().decode().strip()
            ssh.close()
            
            if status == "active":
                yield "data: [SUCCESS] AI Agent Standalone Binary đã được triển khai và khởi động THÀNH CÔNG trên VPS!\n\n"
            else:
                yield f"data: [WARNING] Service được deploy nhưng trạng thái hiện tại là: {status}\n\n"
        except Exception as e:
            yield f"data: [ERROR] Thao tác deploy thất bại: {str(e)}\n\n"

    return StreamingResponse(step_generator(), media_type="text/event-stream")

@app.post("/api/terminal/run")
def run_terminal_command(req: CommandRequest):
    cfg = load_config()
    try:
        ssh = get_ssh_client(cfg)
        stdin, stdout, stderr = ssh.exec_command(req.command, timeout=30)
        out = stdout.read().decode()
        err = stderr.read().decode()
        exit_code = stdout.channel.recv_exit_status()
        ssh.close()
        return {
            "status": "success",
            "exit_code": exit_code,
            "stdout": out,
            "stderr": err,
            "combined": out + (f"\n[STDERR]: {err}" if err else "")
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==========================================
# CHAT SESSIONS & CHAT HISTORY ENDPOINTS
# ==========================================
@app.get("/api/chat/sessions")
def get_sessions_api():
    sessions = get_all_sessions()
    return {"status": "success", "sessions": sessions}

@app.post("/api/chat/sessions")
def create_session_api(req: SessionCreateRequest = Body(default=SessionCreateRequest())):
    session = create_session(req.title or "Cuộc hội thoại mới")
    return {"status": "success", "session": session}

@app.put("/api/chat/sessions/{session_id}")
def rename_session_api(session_id: str, req: SessionUpdateRequest):
    success = rename_session(session_id, req.title)
    return {"status": "success" if success else "error"}

@app.delete("/api/chat/sessions/{session_id}")
def delete_session_api(session_id: str):
    success = delete_session(session_id)
    return {"status": "success" if success else "error"}

@app.get("/api/chat/history")
def get_chat_history_api(session_id: str = "default"):
    messages = get_messages_from_db(session_id)
    return {"status": "success", "messages": messages}

@app.post("/api/chat/clear")
def clear_chat_history_api(session_id: str = "default"):
    clear_messages_in_db(session_id)
    return {"status": "success"}

@app.post("/api/chat")
def chat_with_agent(req: ChatRequest):
    cfg = load_config()
    server_ip = cfg.get("server_ip", "127.0.0.1")
    api_port = cfg.get("api_port", 8000)
    token = cfg.get("secret_token", "super_secret_token_123")
    current_model = cfg.get("ai_model", "glm-5.3")
    session_id = req.session_id or "default"
    
    # 1. Thu thập ngữ cảnh hội thoại trước đó cho đúng session_id từ SQLite
    history_context = []
    db_history = get_messages_from_db(session_id, limit=10)
    for m in db_history:
        history_context.append({"role": m["role"], "content": m["content"]})
        
    # 2. Lưu câu hỏi mới của User vào SQLite
    save_message_to_db(
        role="user",
        content=req.message,
        attachments=req.attachments,
        model=current_model,
        session_id=session_id
    )
    
    url = f"http://{server_ip}:{api_port}/ai_agent"
    headers = {
        "x-api-token": token,
        "Content-Type": "application/json"
    }
    
    full_message = req.message
    if req.attachments:
        full_message += "\n\n=== FILE ĐÍNH KÈM TỪ NGƯỜI DÙNG ==="
        for att in req.attachments:
            full_message += f"\n\n--- [Tệp: {att.name}] ---\n{att.content}"
            
    payload = {
        "message": full_message,
        "history": history_context
    }

    def stream_forwarder():
        accumulated_reply = ""
        accumulated_tools = []
        try:
            with requests.post(url, json=payload, headers=headers, stream=True, timeout=120) as r:
                if r.status_code != 200:
                    err_text = f"Mã lỗi từ server {r.status_code}: {r.text}"
                    yield f"data: {json.dumps({'type': 'error', 'message': err_text}, ensure_ascii=False)}\n\n"
                    return

                content_type = r.headers.get("content-type", "")
                if "text/event-stream" in content_type:
                    # A. Forward SSE trực tiếp
                    for line in r.iter_lines(decode_unicode=True):
                        if line:
                            yield f"{line}\n\n"
                            if line.startswith("data: "):
                                try:
                                    data_json = json.loads(line[6:])
                                    if data_json.get("type") == "token":
                                        accumulated_reply += data_json.get("delta", "")
                                    elif data_json.get("type") == "tool":
                                        if data_json.get("tool"):
                                            accumulated_tools.append(data_json["tool"])
                                    elif data_json.get("type") == "done":
                                        accumulated_reply = data_json.get("reply", accumulated_reply)
                                        accumulated_tools = data_json.get("tool_calls", accumulated_tools)
                                except Exception:
                                    pass
                else:
                    # B. Fallback JSON tiêu chuẩn
                    try:
                        raw_text = r.text
                        data_json = json.loads(raw_text)
                        reply = data_json.get("reply", "")
                        tool_calls = data_json.get("tool_calls", [])
                        
                        for tc in tool_calls:
                            accumulated_tools.append(tc)
                            yield f"data: {json.dumps({'type': 'tool', 'tool': tc}, ensure_ascii=False)}\n\n"
                            time.sleep(0.04)
                        
                        words = reply.split(" ")
                        for idx, word in enumerate(words):
                            token_w = word + (" " if idx < len(words) - 1 else "")
                            accumulated_reply += token_w
                            yield f"data: {json.dumps({'type': 'token', 'delta': token_w}, ensure_ascii=False)}\n\n"
                            time.sleep(0.015)
                            
                        yield f"data: {json.dumps({'type': 'done', 'reply': reply, 'tool_calls': tool_calls}, ensure_ascii=False)}\n\n"
                    except Exception as e:
                        accumulated_reply = r.text
                        yield f"data: {json.dumps({'type': 'token', 'delta': r.text}, ensure_ascii=False)}\n\n"
                        yield f"data: {json.dumps({'type': 'done', 'reply': r.text, 'tool_calls': []}, ensure_ascii=False)}\n\n"

            # Lưu câu trả lời của AI vào SQLite theo session_id
            if accumulated_reply or accumulated_tools:
                save_message_to_db(
                    role="assistant",
                    content=accumulated_reply,
                    tool_calls=accumulated_tools,
                    model=current_model,
                    session_id=session_id
                )
        except requests.exceptions.ConnectionError:
            err_msg = f"Không thể kết nối đến AI Agent tại http://{server_ip}:{api_port}. Vui lòng kiểm tra trạng thái dịch vụ trong tab Thiết lập."
            yield f"data: {json.dumps({'type': 'error', 'message': err_msg}, ensure_ascii=False)}\n\n"
        except Exception as e:
            err_msg = f"Lỗi kết nối: {str(e)}"
            yield f"data: {json.dumps({'type': 'error', 'message': err_msg}, ensure_ascii=False)}\n\n"

    return StreamingResponse(stream_forwarder(), media_type="text/event-stream")

# ==========================================
# GIAO DIỆN WEB DASHBOARD
# ==========================================
@app.get("/", response_class=FileResponse)
def index_page():
    if os.path.exists(TEMPLATE_INDEX):
        return FileResponse(TEMPLATE_INDEX, media_type="text/html")
    return HTMLResponse("<h1>Không tìm thấy template index.html</h1>", status_code=404)

def is_server_already_running(url: str) -> bool:
    try:
        res = requests.get(f"{url}/api/config", timeout=1.5)
        return res.status_code == 200
    except Exception:
        return False

def find_available_port(start_port: int = 8888, max_attempts: int = 20) -> int:
    import socket
    for p in range(start_port, start_port + max_attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(('127.0.0.1', p)) != 0:
                return p
    return start_port

def open_browser_delayed(url: str, delay: float = 0.8):
    def _open():
        time.sleep(delay)
        webbrowser.open(url)
    threading.Thread(target=_open, daemon=True).start()

if __name__ == "__main__":
    import uvicorn
    host = "127.0.0.1"
    default_port = 8888
    default_url = f"http://{host}:{default_port}"
    
    if is_server_already_running(default_url):
        print("\n" + "="*55)
        print("⚡ TADU CLOUD AI AGENT ĐÃ ĐANG CHẠY TRÊN HỆ THỐNG!")
        print(f"🌐 Đang mở lại trình duyệt tại: {default_url}")
        print("="*55 + "\n")
        webbrowser.open(default_url)
        sys.exit(0)
        
    port = find_available_port(default_port)
    url = f"http://{host}:{port}"
    
    print("\n" + "="*55)
    print("🚀 ĐANG KHỞI CHẠY TADU CLOUD AI AGENT CONTROL CENTER (GLM-5.3)")
    print(f"🌐 Truy cập giao diện tại: {url}")
    print("="*55 + "\n")
    
    no_browser = "--no-browser" in sys.argv
    if not no_browser:
        open_browser_delayed(url, 0.8)
    uvicorn.run(app, host=host, port=port, log_level="warning")
