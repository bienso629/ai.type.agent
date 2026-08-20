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

TEMPLATE_INDEX = os.path.join(BUNDLE_DIR, "templates", "index.html")
LOGO_PATH = os.path.join(APP_DIR, "logo.jpg")
if not os.path.exists(LOGO_PATH):
    LOGO_PATH = os.path.join(BUNDLE_DIR, "logo.jpg")
ICON_PATH = os.path.join(BUNDLE_DIR, "templates", "icon.png")

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
        # Tự động gom các message cũ vào chat_sessions nếu chưa có
        cursor.execute("SELECT DISTINCT session_id FROM chat_messages")
        msg_sessions = [r[0] for r in cursor.fetchall() if r[0]]
        if not msg_sessions:
            msg_sessions = ['default']
            
        for sid in msg_sessions:
            cursor.execute("SELECT title FROM chat_sessions WHERE id = ?", (sid,))
            row = cursor.fetchone()
            if not row:
                cursor.execute("INSERT INTO chat_sessions (id, title) VALUES (?, 'Cuộc hội thoại mới')", (sid,))
                
            # Lấy câu hỏi cuối cùng của user để đặt tên cho session nếu chưa có tên cụ thể
            if not row or row[0] in ['Cuộc hội thoại mới', 'Hội thoại mặc định', 'Default Chat']:
                cursor.execute("SELECT content, created_at FROM chat_messages WHERE session_id = ? AND role = 'user' ORDER BY id DESC LIMIT 1", (sid,))
                last_user_msg = cursor.fetchone()
                if last_user_msg and last_user_msg[0]:
                    smart_title = make_smart_title(last_user_msg[0])
                    cursor.execute("UPDATE chat_sessions SET title = ?, updated_at = ? WHERE id = ?", (smart_title, last_user_msg[1], sid))
        
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
            cursor.execute("INSERT OR IGNORE INTO chat_sessions (id, title) VALUES ('default', 'Cuộc hội thoại mới')")
            conn.commit()
            cursor.execute("SELECT id, title, created_at, updated_at FROM chat_sessions ORDER BY updated_at DESC")
            rows = cursor.fetchall()
        conn.close()
        return [{"id": r[0], "title": r[1], "created_at": str(r[2]), "updated_at": str(r[3])} for r in rows]
    except Exception as e:
        print(f"Lỗi đọc sessions: {e}")
        return [{"id": "default", "title": "Cuộc hội thoại mới", "created_at": "", "updated_at": ""}]

def create_session(title: str = "Cuộc hội thoại mới") -> Dict[str, Any]:
    session_id = f"s_{uuid.uuid4().hex[:8]}"
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO chat_sessions (id, title) VALUES (?, ?)", (session_id, title))
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
        cursor.execute("UPDATE chat_sessions SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (title, session_id))
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
        cursor.execute("INSERT OR IGNORE INTO chat_sessions (id, title) VALUES (?, 'Cuộc hội thoại mới')", (session_id,))
        
        # Tự động đặt tên thông minh cho hộp hội thoại theo câu hỏi mới nhất nếu chưa đổi tên tùy biến
        if role == "user":
            cursor.execute("SELECT title FROM chat_sessions WHERE id = ?", (session_id,))
            row = cursor.fetchone()
            if not row or (row and (row[0] in ["Cuộc hội thoại mới", "Hội thoại mặc định", "Default Chat"] or not row[0])):
                smart_title = make_smart_title(content)
                if smart_title:
                    cursor.execute("UPDATE chat_sessions SET title = ? WHERE id = ?", (smart_title, session_id))
        
        # Cập nhật thời gian updated_at cho session
        cursor.execute("UPDATE chat_sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", (session_id,))

        att_str = json.dumps([a.dict() if hasattr(a, 'dict') else (a.model_dump() if hasattr(a, 'model_dump') else a) for a in attachments], ensure_ascii=False) if attachments else None
        tc_str = json.dumps(tool_calls, ensure_ascii=False) if tool_calls else None
        cursor.execute("""
            INSERT INTO chat_messages (session_id, role, content, attachments_json, tool_calls_json, model)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (session_id, role, content, att_str, tc_str, model))
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
            results.append({
                "id": r[0],
                "session_id": r[1],
                "role": r[2],
                "content": r[3],
                "attachments": json.loads(r[4]) if r[4] else [],
                "tool_calls": json.loads(r[5]) if r[5] else [],
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
# ==========================================
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
            for k, v in DEFAULT_CONFIG.items():
                if k not in data:
                    data[k] = v
            return data
    except Exception as e:
        print(f"Lỗi đọc file config: {e}")
        return DEFAULT_CONFIG

def save_config(cfg: Dict[str, Any]):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

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

@app.get("/api/server/metrics")
def get_server_metrics():
    cfg = load_config()
    try:
        ssh = get_ssh_client(cfg)
        stdin, stdout, stderr = ssh.exec_command(
            "uptime -p 2>/dev/null || uptime; "
            "echo '---'; "
            "df -h /; "
            "echo '---'; "
            "free -m; "
            "echo '---'; "
            "systemctl is-active ai-agent.service 2>/dev/null || echo 'inactive'; "
            "echo '---'; "
            "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s"
        )
        output = stdout.read().decode()
        ssh.close()
        
        parts = output.split("---")
        uptime = parts[0].strip() if len(parts) > 0 else "N/A"
        df = parts[1].strip() if len(parts) > 1 else "N/A"
        free = parts[2].strip() if len(parts) > 2 else "N/A"
        service_status = parts[3].strip() if len(parts) > 3 else "unknown"
        os_name = parts[4].strip() if len(parts) > 4 else "Linux"

        return {
            "status": "success",
            "uptime": uptime,
            "disk": df,
            "ram": free,
            "service_status": service_status,
            "os": os_name
        }
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
            
            yield "data: Đang cài đặt thư viện Python (FastAPI, Uvicorn, OpenAI, Paramiko, Psutil)...\n\n"
            stdin, stdout, stderr = ssh.exec_command("sudo apt-get update -y && sudo apt-get install -y python3 python3-pip python3-venv")
            stdout.channel.recv_exit_status()
            
            stdin, stdout, stderr = ssh.exec_command("pip3 install --break-system-packages fastapi uvicorn openai requests paramiko psutil || pip3 install fastapi uvicorn openai requests paramiko psutil")
            stdout.channel.recv_exit_status()
            yield "data: Cài đặt thư viện Python hoàn tất!\n\n"
            
            yield "data: Đang tải mã nguồn ai_agent_service.py lên Server...\n\n"
            if not os.path.exists(SERVICE_FILE_PATH):
                yield "data: LỖI: Không tìm thấy file ai_agent_service.py để upload!\n\n"
                return
                
            sftp = ssh.open_sftp()
            sftp.put(SERVICE_FILE_PATH, f"{remote_dir}/ai_agent_service.py")
            sftp.close()
            yield "data: Upload file service lên máy chủ thành công!\n\n"
            
            yield "data: Đang cấu hình và kích hoạt Systemd Service (ai-agent.service)...\n\n"
            service_content = f"""[Unit]
Description=Tadu Cloud AI Agent Service (GLM-5.3)
After=network.target

[Service]
Type=simple
User={cfg['ssh_user']}
WorkingDirectory={remote_dir}
Environment="OPENROUTER_API_KEY={cfg.get('proxy_api_key', '')}"
Environment="OPENROUTER_BASE_URL={cfg.get('proxy_base_url', 'https://openrouter.ai/api/v1')}"
Environment="AI_MODEL={cfg.get('ai_model', 'glm-5.3')}"
Environment="AGENT_SECRET_TOKEN={cfg.get('secret_token', 'super_secret_token_123')}"
Environment="AGENT_PORT={cfg.get('api_port', 8000)}"
ExecStart=/usr/bin/python3 {remote_dir}/ai_agent_service.py
Restart=always
RestartSec=5

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
                yield "data: [SUCCESS] AI Agent đã được triển khai và khởi động THÀNH CÔNG trên VPS!\n\n"
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
