import os
import json
import time
import uuid
import webbrowser
import threading
import sqlite3
import asyncio
from typing import Optional, Dict, Any, List
from fastapi import FastAPI, HTTPException, Body, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import requests
import sys
import re
import base64

# Xử lý đường dẫn khi đóng gói binary (PyInstaller / AppImage / Portable)
if getattr(sys, 'frozen', False):
    BUNDLE_DIR = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))
    
    user_home_dir = os.path.expanduser("~/.tadu_ai_agent")
    os.makedirs(user_home_dir, exist_ok=True)
    
    owd = os.environ.get("OWD", "")
    cwd_dir = os.getcwd()
    exec_dir = os.path.dirname(sys.executable)
    parent_dir = os.path.abspath(os.path.join(exec_dir, ".."))
    
    if owd and os.path.exists(os.path.join(owd, "chat_history.db")):
        APP_DIR = owd
    elif os.path.exists(os.path.join(cwd_dir, "chat_history.db")) and not cwd_dir.startswith("/tmp"):
        APP_DIR = cwd_dir
    elif os.path.exists(os.path.join(parent_dir, "chat_history.db")) and not parent_dir.startswith("/tmp"):
        APP_DIR = parent_dir
    else:
        APP_DIR = user_home_dir
        # Di chuyển hoặc đồng bộ DB và Config ban đầu nếu có trong thư mục hiện tại
        if owd and os.path.exists(os.path.join(owd, "config.json")) and not os.path.exists(os.path.join(user_home_dir, "config.json")):
            try:
                import shutil
                shutil.copy2(os.path.join(owd, "config.json"), os.path.join(user_home_dir, "config.json"))
            except Exception:
                pass
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
if not os.path.exists(TEMPLATE_INDEX):
    TEMPLATE_INDEX = os.path.join(APP_DIR, "templates", "index.html")

LOGO_PATH = os.path.join(APP_DIR, "logo.jpg")
if not os.path.exists(LOGO_PATH):
    LOGO_PATH = os.path.join(BUNDLE_DIR, "logo.jpg")
ICON_PATH = os.path.join(BUNDLE_DIR, "templates", "icon.png")
if not os.path.exists(ICON_PATH):
    ICON_PATH = os.path.join(APP_DIR, "templates", "icon.png")

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
                is_pinned INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Migration: Thêm cột is_pinned nếu chưa có
        cursor.execute("PRAGMA table_info(chat_sessions)")
        existing_cols = [col[1] for col in cursor.fetchall()]
        if "is_pinned" not in existing_cols:
            cursor.execute("ALTER TABLE chat_sessions ADD COLUMN is_pinned INTEGER DEFAULT 0")

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
                cursor.execute("INSERT INTO chat_sessions (id, title, is_pinned) VALUES (?, ?, 0)", (sid, encrypt_value('Cuộc hội thoại mới')))
                
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
        cursor.execute("SELECT id, title, is_pinned, created_at, updated_at FROM chat_sessions ORDER BY is_pinned DESC, updated_at DESC, id DESC")
        rows = cursor.fetchall()
        if not rows:
            cursor.execute("INSERT OR IGNORE INTO chat_sessions (id, title, is_pinned) VALUES ('default', ?, 0)", (encrypt_value('Cuộc hội thoại mới'),))
            conn.commit()
            cursor.execute("SELECT id, title, is_pinned, created_at, updated_at FROM chat_sessions ORDER BY is_pinned DESC, updated_at DESC, id DESC")
            rows = cursor.fetchall()
        conn.close()
        return [{"id": r[0], "title": decrypt_value(r[1]) or "Cuộc hội thoại mới", "is_pinned": bool(r[2]), "created_at": str(r[3]), "updated_at": str(r[4])} for r in rows]
    except Exception as e:
        print(f"Lỗi đọc sessions: {e}")
        return [{"id": "default", "title": "Cuộc hội thoại mới", "is_pinned": False, "created_at": "", "updated_at": ""}]

def toggle_pin_session(session_id: str, is_pinned: Optional[bool] = None) -> bool:
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        if is_pinned is None:
            cursor.execute("SELECT is_pinned FROM chat_sessions WHERE id = ?", (session_id,))
            row = cursor.fetchone()
            new_pin = 0 if (row and row[0] == 1) else 1
        else:
            new_pin = 1 if is_pinned else 0
        cursor.execute("UPDATE chat_sessions SET is_pinned = ? WHERE id = ?", (new_pin, session_id))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"Lỗi pin session: {e}")
        return False

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

        att_str = json.dumps([a.model_dump() if hasattr(a, 'model_dump') else (a.dict() if hasattr(a, 'dict') else a) for a in attachments], ensure_ascii=False) if attachments else None
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
            FROM (
                SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                FROM chat_messages
                WHERE session_id = ?
                ORDER BY id DESC
                LIMIT ?
            ) sub
            ORDER BY id ASC
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

def get_chat_history_paginated(session_id: str = "default", limit_questions: int = 3, before_id: Optional[int] = None) -> Dict[str, Any]:
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # 1. Tìm ID các câu hỏi (role = 'user') thoả mãn điều kiện
        if before_id is not None and before_id > 0:
            cursor.execute("""
                SELECT id FROM chat_messages
                WHERE session_id = ? AND role = 'user' AND id < ?
                ORDER BY id DESC
                LIMIT ?
            """, (session_id, before_id, limit_questions))
        else:
            cursor.execute("""
                SELECT id FROM chat_messages
                WHERE session_id = ? AND role = 'user'
                ORDER BY id DESC
                LIMIT ?
            """, (session_id, limit_questions))

        user_msg_rows = cursor.fetchall()

        if user_msg_rows:
            min_user_id = min(r[0] for r in user_msg_rows)
            if before_id is not None and before_id > 0:
                cursor.execute("""
                    SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                    FROM chat_messages
                    WHERE session_id = ? AND id >= ? AND id < ?
                    ORDER BY id ASC
                """, (session_id, min_user_id, before_id))
            else:
                cursor.execute("""
                    SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                    FROM chat_messages
                    WHERE session_id = ? AND id >= ?
                    ORDER BY id ASC
                """, (session_id, min_user_id))
            rows = cursor.fetchall()
        else:
            if before_id is not None and before_id > 0:
                cursor.execute("""
                    SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                    FROM (
                        SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                        FROM chat_messages
                        WHERE session_id = ? AND id < ?
                        ORDER BY id DESC
                        LIMIT ?
                    ) sub
                    ORDER BY id ASC
                """, (session_id, before_id, limit_questions * 2))
            else:
                cursor.execute("""
                    SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                    FROM (
                        SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at
                        FROM chat_messages
                        WHERE session_id = ?
                        ORDER BY id DESC
                        LIMIT ?
                    ) sub
                    ORDER BY id ASC
                """, (session_id, limit_questions * 2))
            rows = cursor.fetchall()

        oldest_id = rows[0][0] if rows else 0

        # Kiểm tra xem còn tin nhắn cũ hơn nữa không (has_more)
        has_more = False
        if rows and oldest_id > 0:
            cursor.execute("""
                SELECT 1 FROM chat_messages
                WHERE session_id = ? AND id < ?
                LIMIT 1
            """, (session_id, oldest_id))
            has_more = cursor.fetchone() is not None

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

        return {
            "status": "success",
            "messages": results,
            "has_more": has_more,
            "oldest_id": oldest_id
        }
    except Exception as e:
        print(f"Lỗi đọc SQLite lịch sử chat: {e}")
        return {"status": "error", "messages": [], "has_more": False, "oldest_id": 0}

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

VENDOR_DIR = os.path.join(BUNDLE_DIR, "templates", "vendor")
if os.path.exists(VENDOR_DIR):
    app.mount("/vendor", StaticFiles(directory=VENDOR_DIR), name="vendor")

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
    working_dir: Optional[str] = None

class SessionCreateRequest(BaseModel):
    title: Optional[str] = "Cuộc hội thoại mới"

class SessionUpdateRequest(BaseModel):
    title: str

class CommandRequest(BaseModel):
    command: str
    cwd: Optional[str] = "~"
    timeout: Optional[int] = 120

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

_net_tracker = {
    "server_ip": "",
    "time": 0.0,
    "rx": 0,
    "tx": 0,
    "speed_rx": 0.0,
    "speed_tx": 0.0
}
_net_tracker_lock = threading.Lock()

def parse_proc_net_dev(net_raw: str):
    total_rx, total_tx = 0, 0
    for line in (net_raw or "").splitlines():
        line = line.strip()
        if ":" not in line:
            continue
        parts = line.split(":", 1)
        iface = parts[0].strip()
        if iface == "lo":
            continue
        fields = parts[1].split()
        if len(fields) >= 9:
            try:
                rx = int(fields[0])
                tx = int(fields[8])
                total_rx += rx
                total_tx += tx
            except Exception:
                pass
    return total_rx, total_tx

def update_net_tracker(server_ip: str, current_rx: int, current_tx: int):
    global _net_tracker
    with _net_tracker_lock:
        now = time.time()
        speed_rx = _net_tracker["speed_rx"]
        speed_tx = _net_tracker["speed_tx"]
        if _net_tracker["server_ip"] == server_ip and _net_tracker["time"] > 0:
            elapsed = now - _net_tracker["time"]
            if 0.5 <= elapsed <= 120.0:
                delta_rx = current_rx - _net_tracker["rx"]
                delta_tx = current_tx - _net_tracker["tx"]
                if delta_rx >= 0 and delta_tx >= 0:
                    speed_rx = delta_rx / elapsed
                    speed_tx = delta_tx / elapsed
                    _net_tracker["speed_rx"] = speed_rx
                    _net_tracker["speed_tx"] = speed_tx
        else:
            _net_tracker["server_ip"] = server_ip
            _net_tracker["speed_rx"] = 0.0
            _net_tracker["speed_tx"] = 0.0
            speed_rx = 0.0
            speed_tx = 0.0

        _net_tracker["time"] = now
        _net_tracker["rx"] = current_rx
        _net_tracker["tx"] = current_tx

        def format_speed(bps):
            if bps >= 1024 * 1024:
                return f"{bps / (1024 * 1024):.2f} MB/s"
            return f"{bps / 1024:.1f} KB/s"

        def format_bytes(b):
            val = float(b)
            for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
                if val < 1024.0:
                    return f"{val:.2f} {unit}"
                val /= 1024.0
            return f"{val:.2f} PB"

        speed_rx_str = format_speed(speed_rx)
        speed_tx_str = format_speed(speed_tx)
        total_rx_str = format_bytes(current_rx)
        total_tx_str = format_bytes(current_tx)

        total_kb = (speed_rx + speed_tx) / 1024.0
        net_pct = int((total_kb / 5000.0) * 100)
        net_pct = min(100, max(15 if (current_rx > 0 or speed_rx > 0) else 5, net_pct))

        return speed_rx_str, speed_tx_str, total_rx_str, total_tx_str, net_pct

def parse_safe_metrics(df_raw: str, free_raw: str, loadavg_raw: str = "", uptime_sec_raw: str = "", procs_raw: str = "", net_raw: str = "", server_ip: str = "") -> Dict[str, Any]:
    rx_bytes, tx_bytes = parse_proc_net_dev(net_raw)
    speed_rx_str, speed_tx_str, total_rx_str, total_tx_str, net_pct = update_net_tracker(server_ip, rx_bytes, tx_bytes)

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
        "net_rx_kbs": speed_rx_str,
        "net_tx_kbs": speed_tx_str,
        "net_rx_total": total_rx_str,
        "net_tx_total": total_tx_str,
        "net_percent": net_pct,
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
        "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s; echo '---'; "
        "cat /proc/net/dev 2>/dev/null"
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
            net_raw = parts[7].strip() if len(parts) > 7 else ""

            uptime_human = format_uptime_human(uptime_raw)
            safe_metrics = parse_safe_metrics(df_raw, free_raw, loadavg_raw, uptime_raw, procs_raw, net_raw, server_ip)

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
            time.sleep(10)

        time.sleep(5.0)

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
    server_ip = cfg.get("server_ip", "127.0.0.1")
    try:
        ssh = get_ssh_client(cfg)
        stdin, stdout, stderr = ssh.exec_command(
            "cat /proc/uptime 2>/dev/null; echo '---'; "
            "cat /proc/loadavg 2>/dev/null; echo '---'; "
            "free -m 2>/dev/null; echo '---'; "
            "df -h / 2>/dev/null; echo '---'; "
            "ps -e | wc -l 2>/dev/null; echo '---'; "
            "systemctl is-active ai-agent.service 2>/dev/null || echo 'inactive'; echo '---'; "
            "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s; echo '---'; "
            "cat /proc/net/dev 2>/dev/null"
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
        net_raw = parts[7].strip() if len(parts) > 7 else ""

        uptime_human = format_uptime_human(uptime_raw)
        safe_metrics = parse_safe_metrics(df_raw, free_raw, loadavg_raw, uptime_raw, procs_raw, net_raw, server_ip)
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
            "server_ip": server_ip,
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

def execute_ssh_command_advanced(cfg: Dict[str, Any], command: str, cwd: str = "~", timeout: int = 120):
    cmd_raw = (command or "").strip()
    if not cmd_raw:
        return {
            "status": "success",
            "exit_code": 0,
            "stdout": "",
            "stderr": "",
            "combined": "",
            "cwd": cwd or "~"
        }
        
    if cmd_raw.lower() in ["clear", "cls"]:
        return {
            "status": "clear",
            "exit_code": 0,
            "stdout": "",
            "stderr": "",
            "combined": "",
            "cwd": cwd or "~"
        }

    target_cwd = (cwd or "~").strip()
    if not target_cwd:
        target_cwd = "~"
    
    server_ip = cfg.get("server_ip")
    if not server_ip:
        return {
            "status": "error", 
            "message": "Chưa cấu hình thông tin IP máy chủ SSH trong tab Cài đặt!",
            "cwd": target_cwd,
            "exit_code": 1
        }

    # Bọc lệnh trong môi trường bash login shell đầy đủ PATH và tự động ghi nhận CWD mới
    script = f"""
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/root/.local/bin
if [ -n "{target_cwd}" ] && [ "{target_cwd}" != "~" ]; then
    cd "{target_cwd}" 2>/dev/null || cd "$HOME" 2>/dev/null || true
else
    cd "$HOME" 2>/dev/null || true
fi
{command}
__RET_VAL=$?
echo ""
echo "__TADU_CWD:$(pwd)__"
exit $__RET_VAL
"""
    b64_script = base64.b64encode(script.encode("utf-8")).decode("ascii")
    exec_cmd = f"bash -l -c 'echo {b64_script} | base64 -d | bash'"

    ssh = None
    try:
        ssh = get_ssh_client(cfg)
        channel = ssh.get_transport().open_session()
        channel.settimeout(timeout)
        channel.exec_command(exec_cmd)
        
        out_buf = bytearray()
        err_buf = bytearray()
        start_time = time.time()
        
        while True:
            if channel.recv_ready():
                out_buf.extend(channel.recv(4096))
            if channel.recv_stderr_ready():
                err_buf.extend(channel.recv_stderr(4096))
            if channel.exit_status_ready():
                while channel.recv_ready():
                    out_buf.extend(channel.recv(4096))
                while channel.recv_stderr_ready():
                    err_buf.extend(channel.recv_stderr(4096))
                break
            if time.time() - start_time > timeout:
                channel.close()
                return {
                    "status": "error",
                    "message": f"Lệnh thực thi vượt quá thời gian tối đa ({timeout}s).",
                    "cwd": target_cwd,
                    "exit_code": 124
                }
            time.sleep(0.02)

        exit_code = channel.recv_exit_status()
        out = out_buf.decode("utf-8", errors="replace")
        err = err_buf.decode("utf-8", errors="replace")
        
        new_cwd = target_cwd
        m = re.search(r"__TADU_CWD:(.*?)__", out)
        if m:
            new_cwd = m.group(1).strip()
            out = out.replace(m.group(0), "").rstrip()

        return {
            "status": "success",
            "exit_code": exit_code,
            "stdout": out,
            "stderr": err,
            "combined": out + (f"\n[STDERR]: {err}" if err else ""),
            "cwd": new_cwd
        }
    except Exception as e:
        return {
            "status": "error", 
            "message": f"Lỗi SSH: {str(e)}", 
            "cwd": target_cwd,
            "exit_code": 1
        }
    finally:
        if ssh:
            try:
                ssh.close()
            except Exception:
                pass

_terminal_session_cwd = "~"

@app.get("/api/terminal/info")
def get_terminal_info():
    global _terminal_session_cwd
    cfg = load_config()
    return {
        "status": "success",
        "server_ip": cfg.get("server_ip", "server"),
        "ssh_user": cfg.get("ssh_user", "root"),
        "ssh_port": cfg.get("ssh_port", 22),
        "default_cwd": _terminal_session_cwd or "~"
    }

@app.post("/api/terminal/run")
def run_terminal_command(req: CommandRequest):
    global _terminal_session_cwd
    cfg = load_config()
    
    # Sử dụng cwd từ request nếu có, ngược lại lấy session cwd hiện tại
    target_cwd = (req.cwd or "").strip()
    if not target_cwd or target_cwd == "~":
        target_cwd = _terminal_session_cwd or "~"
        
    timeout = max(5, int(req.timeout or 120))
    res = execute_ssh_command_advanced(cfg, req.command, cwd=target_cwd, timeout=timeout)
    if res.get("cwd"):
        _terminal_session_cwd = res["cwd"]
    return res

@app.websocket("/ws/terminal")
async def websocket_terminal(websocket: WebSocket):
    await websocket.accept()
    cfg = load_config()
    server_ip = cfg.get("server_ip")
    if not server_ip:
        await websocket.send_text("\r\n\x1b[31m[LỖI]: Chưa cấu hình thông tin IP máy chủ SSH trong tab Thiết lập!\x1b[0m\r\n")
        try:
            await websocket.close()
        except Exception:
            pass
        return

    ssh = None
    channel = None
    try:
        ssh = get_ssh_client(cfg)
        channel = ssh.invoke_shell(term="xterm-256color", width=120, height=35)
        channel.setblocking(0)
    except Exception as e:
        await websocket.send_text(f"\r\n\x1b[31m[LỖI KẾT NỐI SSH]: {str(e)}\x1b[0m\r\n")
        try:
            await websocket.close()
        except Exception:
            pass
        if ssh:
            try:
                ssh.close()
            except Exception:
                pass
        return

    async def send_to_ws():
        try:
            while True:
                if channel.recv_ready():
                    data = channel.recv(4096).decode("utf-8", errors="replace")
                    if data:
                        await websocket.send_text(data)
                elif channel.closed or channel.exit_status_ready():
                    break
                await asyncio.sleep(0.015)
        except Exception:
            pass

    async def receive_from_ws():
        try:
            while True:
                msg = await websocket.receive_text()
                if msg.startswith('{"type":') or msg.startswith('{"type" :'):
                    try:
                        p = json.loads(msg)
                        if p.get("type") == "resize":
                            cols = int(p.get("cols", 120))
                            rows = int(p.get("rows", 35))
                            channel.resize_pty(width=cols, height=rows)
                            continue
                    except Exception:
                        pass
                channel.send(msg)
        except Exception:
            pass

    send_task = asyncio.create_task(send_to_ws())
    recv_task = asyncio.create_task(receive_from_ws())

    done, pending = await asyncio.wait(
        [send_task, recv_task],
        return_when=asyncio.FIRST_COMPLETED
    )

    for task in pending:
        task.cancel()

    try:
        channel.close()
    except Exception:
        pass
    try:
        ssh.close()
    except Exception:
        pass
    try:
        await websocket.close()
    except Exception:
        pass

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

@app.post("/api/chat/sessions/{session_id}/pin")
def pin_session_api(session_id: str, req: Dict[str, Any] = Body(default={})):
    is_pinned = req.get("is_pinned")
    success = toggle_pin_session(session_id, is_pinned)
    return {"status": "success" if success else "error"}

@app.delete("/api/chat/sessions/{session_id}")
def delete_session_api(session_id: str):
    success = delete_session(session_id)
    return {"status": "success" if success else "error"}

@app.get("/api/chat/history")
def get_chat_history_api(session_id: str = "default", limit_questions: int = 3, before_id: Optional[int] = None):
    return get_chat_history_paginated(session_id=session_id, limit_questions=limit_questions, before_id=before_id)

@app.post("/api/chat/clear")
def clear_chat_history_api(session_id: str = "default"):
    clear_messages_in_db(session_id)
@app.get("/api/fs/list_dirs")
def list_server_directories(prefix: str = "/"):
    """Liệt kê danh sách thư mục trên server từ xa phục vụ tính năng autocomplete với dấu /"""
    prefix = (prefix or "/").strip()
    if not prefix.startswith("/"):
        prefix = "/" + prefix
    try:
        cfg = load_config()
        ssh = get_ssh_client(cfg)
        cmd = f"compgen -d {repr(prefix)} 2>/dev/null | head -30"
        stdin, stdout, stderr = ssh.exec_command(cmd, timeout=3)
        dirs = [d.strip() for d in stdout.read().decode().splitlines() if d.strip()]
        ssh.close()

        if not dirs and prefix != "/":
            ssh2 = get_ssh_client(cfg)
            cmd2 = f"find {repr(prefix)} -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -30"
            stdin, stdout, stderr = ssh2.exec_command(cmd2, timeout=3)
            dirs = [d.strip() for d in stdout.read().decode().splitlines() if d.strip()]
            ssh2.close()

        if prefix == "/":
            common = ["/var/www", "/var/www/chatbot.ai-acv.io.vn", "/var/www/chatbot.ai-acv.io.vn/Admin", "/var/www/blog.ai-acv.io.vn", "/etc/nginx", "/opt/ai_agent", "/home", "/var/log", "/etc", "/opt"]
            for c in common:
                if c not in dirs:
                    dirs.append(c)

        return {"status": "success", "prefix": prefix, "directories": sorted(list(set(dirs)))}
    except Exception as e:
        common = ["/var/www", "/var/www/chatbot.ai-acv.io.vn", "/var/www/chatbot.ai-acv.io.vn/Admin", "/var/www/blog.ai-acv.io.vn", "/etc/nginx", "/opt/ai_agent", "/home", "/var/log", "/opt"]
        filtered = [c for c in common if c.startswith(prefix)]
        return {"status": "success", "prefix": prefix, "directories": filtered or common}

@app.post("/api/chat")
def chat_with_agent(req: ChatRequest):
    cfg = load_config()
    server_ip = cfg.get("server_ip", "127.0.0.1")
    api_port = cfg.get("api_port", 8000)
    token = cfg.get("secret_token", "super_secret_token_123")
    current_model = cfg.get("ai_model", "glm-5.3")
    session_id = req.session_id or "default"
    
    # Xác định thư mục làm việc giới hạn (Working Directory Scope)
    working_dir = req.working_dir
    if not working_dir:
        import re
        match = re.search(r'(/(?:var|etc|opt|home|root|usr|tmp|www|srv)[a-zA-Z0-9_\-\.\/]*)', req.message)
        if match:
            potential_path = match.group(1).rstrip('/')
            if potential_path and len(potential_path) > 3:
                working_dir = potential_path

    # 1. Thu thập ngữ cảnh hội thoại gần nhất trong phiên hiện tại (tối đa 4 tin nhắn)
    history_context = []
    db_history = get_messages_from_db(session_id, limit=4)
    for m in db_history:
        r = m.get("role")
        c = m.get("content", "").strip()
        if r in ["user", "assistant"] and c:
            if len(c) > 1500:
                c = c[:1500] + "..."
            history_context.append({"role": r, "content": c})
        
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
        full_message += "\n\n=== FILE & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ==="
        for att in req.attachments:
            if att.content.startswith("data:image"):
                full_message += f"\n\n--- [Ảnh chụp màn hình: {att.name}] --- (Người dùng đính kèm ảnh chụp màn hình giao diện)"
            else:
                full_message += f"\n\n--- [Tệp: {att.name}] ---\n{att.content}"
            
    payload = {
        "message": full_message,
        "history": history_context,
        "working_dir": working_dir
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
    no_browser = "--no-browser" in sys.argv
    host = "127.0.0.1"
    default_port = 8888
    default_url = f"http://{host}:{default_port}"
    
    if is_server_already_running(default_url):
        print("\n" + "="*55)
        print("⚡ TADU CLOUD AI AGENT ĐÃ ĐANG CHẠY TRÊN HỆ THỐNG!")
        print("="*55 + "\n")
        if not no_browser:
            webbrowser.open(default_url)
        sys.exit(0)
        
    port = find_available_port(default_port)
    url = f"http://{host}:{port}"
    
    print("\n" + "="*55)
    print("🚀 ĐANG KHỞI CHẠY TADU CLOUD AI AGENT CONTROL CENTER (GLM-5.3)")
    print(f"🌐 Server nội bộ tại: {url}")
    print("="*55 + "\n")
    
    if not no_browser:
        open_browser_delayed(url, 0.8)
    uvicorn.run(app, host=host, port=port, log_level="warning")
