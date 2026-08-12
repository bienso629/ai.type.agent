import asyncio
import os
import re
import subprocess
import sqlite3
from typing import List
from pydantic import BaseModel
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI(title="Zalo Auto Reply Plugin for Mì Tôm AI", version="1.0")

# Cấu hình CORS để Electron webview/renderer có thể gọi được
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---- CẤU HÌNH DATABASE SQLITE ----
DB_DIR = os.path.expanduser("~/Documents/ai.type/data/zalo")
os.makedirs(DB_DIR, exist_ok=True)
DB_PATH = os.path.join(DB_DIR, "zalo_data.db")

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    # Lưu danh sách bạn bè / nhóm chat
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS contacts (
            name TEXT PRIMARY KEY,
            preview TEXT,
            time TEXT,
            avatar TEXT,
            unread INTEGER
        )
    """)
    # Lưu toàn bộ lịch sử tin nhắn
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            contact_name TEXT,
            sender TEXT,
            text TEXT,
            is_mine INTEGER,
            time TEXT,
            UNIQUE(contact_name, sender, text, time)
        )
    """)
    conn.commit()
    conn.close()

init_db()

# ---- PYDANTIC SCHEMAS ----
class ReplyRequest(BaseModel):
    prompt: str
    system_instructions: str = (
        "Bạn là trợ lý AI tự động trả lời tin nhắn Zalo thân thiện, ngắn gọn và hữu ích. "
        "Hãy trả lời bằng tiếng Việt lịch sự, tự nhiên như người thật."
    )

class ReplyResponse(BaseModel):
    success: bool
    reply: str = ""
    error: str = None

class ContactItem(BaseModel):
    name: str
    preview: str = ""
    time: str = ""
    avatar: str = ""
    unread: int = 0

class SyncContactsRequest(BaseModel):
    contacts: List[ContactItem]

class MessageItem(BaseModel):
    sender: str
    text: str
    is_mine: bool
    time: str

class SyncMessagesRequest(BaseModel):
    contact_name: str
    messages: List[MessageItem]

class SendRequest(BaseModel):
    contact_name: str
    text: str

# ---- HÀNG ĐỢI TIN NHẮN CHỜ GỬI ----
pending_sends = []

# ---- ENDPOINTS ----
@app.post("/api/zalo/reply", response_model=ReplyResponse)
async def zalo_reply_endpoint(req: ReplyRequest):
    try:
        full_prompt = f"[{req.system_instructions}]\n\nTin nhắn đối phương gửi đến: {req.prompt}"
        command = [
            "agy", "--print", full_prompt,
            "--dangerously-skip-permissions"
        ]
        
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            error_msg = stderr.decode().strip() or "Lỗi chưa xác định từ agy CLI"
            return ReplyResponse(success=False, error=f"agy error: {error_msg}")
            
        reply_text = stdout.decode().strip()
        prefixes_to_filter = ('I will ', 'I am ', 'I\'ll ', 'I need ', 'I have ')
        lines = reply_text.split('\n')
        filtered_lines = [line for line in lines if not any(line.strip().startswith(p) for p in prefixes_to_filter)]
        reply_text = '\n'.join(filtered_lines).strip()
        
        return ReplyResponse(success=True, reply=reply_text)
        
    except Exception as e:
        return ReplyResponse(success=False, error=str(e))

@app.post("/api/zalo/sync-contacts")
async def sync_contacts_endpoint(req: SyncContactsRequest):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        for contact in req.contacts:
            cursor.execute("""
                INSERT INTO contacts (name, preview, time, avatar, unread)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET
                    preview=excluded.preview,
                    time=excluded.time,
                    avatar=excluded.avatar,
                    unread=excluded.unread
            """, (contact.name, contact.preview, contact.time, contact.avatar, contact.unread))
        conn.commit()
        conn.close()
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/zalo/sync-messages")
async def sync_messages_endpoint(req: SyncMessagesRequest):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        for msg in req.messages:
            cursor.execute("""
                INSERT OR IGNORE INTO messages (contact_name, sender, text, is_mine, time)
                VALUES (?, ?, ?, ?, ?)
            """, (req.contact_name, msg.sender, msg.text, 1 if msg.is_mine else 0, msg.time))
        conn.commit()
        conn.close()
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/zalo/contacts")
async def get_contacts_endpoint():
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM contacts ORDER BY time DESC")
        rows = cursor.fetchall()
        contacts = [dict(row) for row in rows]
        conn.close()
        return {"success": True, "contacts": contacts}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/zalo/messages")
async def get_messages_endpoint(contact_name: str):
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM messages 
            WHERE contact_name = ? 
            ORDER BY id ASC
        """, (contact_name,))
        rows = cursor.fetchall()
        messages = [dict(row) for row in rows]
        conn.close()
        return {"success": True, "messages": messages}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/zalo/send")
async def send_message_endpoint(req: SendRequest):
    from datetime import datetime
    try:
        new_time_str = datetime.utcnow().isoformat() + "Z"
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        # Thêm tin nhắn của mình vào db cục bộ
        cursor.execute("""
            INSERT INTO messages (contact_name, sender, text, is_mine, time)
            VALUES (?, ?, ?, ?, ?)
        """, (req.contact_name, "Me", req.text, 1, new_time_str))
        
        # Cập nhật xem trước trong danh sách bạn bè
        cursor.execute("""
            UPDATE contacts 
            SET preview = ?, time = 'Vừa xong'
            WHERE name = ?
        """, (req.text, req.contact_name))
        
        conn.commit()
        conn.close()
        
        # Thêm vào danh sách tin nhắn chờ gửi để preload.js quét được
        pending_sends.append({
            "contact_name": req.contact_name,
            "text": req.text
        })
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/zalo/pending-sends")
async def get_pending_sends_endpoint():
    try:
        sends = list(pending_sends)
        pending_sends.clear()
        return {"success": True, "sends": sends}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class LogRequest(BaseModel):
    message: str

LOG_FILE_PATH = os.path.join(DB_DIR, "zalo_sync.log")

@app.post("/api/zalo/log")
async def write_log_endpoint(req: LogRequest):
    try:
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_FILE_PATH, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] {req.message}\n")
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=54322)
