# chatbot.py — FastAPI app: LCEL RAG + index-versioned cache + ACCOUNT routes merged
# (patched) unified IP helpers, CORS for localhost:7777, added /debug/ip
# (updated) /account/register: hỗ trợ Google OAuth qua id_token (credential) hoặc authorization code
# (new) load .env early + getenv_str() to trim envs + /debug/env
# (updated) Multi-domain support for Website RAG + Custom Prompt + Clean Domain Fix
# (updated) /crawl-domains: Receives Sitemaps -> Returns URLs via Requests
# (new) /save-content-url: Receives JSON content -> Saves ONLY
# (new) /trigger-index-domain: Builds index AND calls website.py to reload
# (FIXED) Added missing Auth dependencies (get_optional_user_email, etc.) & MongoDB config
# (UPGRADE) Multi-turn Chat: Added History Context for Gemini
# (UPGRADE) Smart Indexing: Incremental updates via indexing_utils & Force Rebuild option
# (NEW) /reindex-file: Re-index single file & Fix Account Router NameError & Fix JSON Body Structure

import os
import time
import json
import sqlite3
import aiofiles
import httpx
import logging
import asyncio
import hashlib
from typing import Union, Optional, List, Dict, Any
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from urllib.parse import unquote, urlparse
from google import genai
from google.genai import types
import aiosqlite
import time # Nhớ import thư viện này ở đầu file chatbot.py

# --- 1. Load .env ---
try:
    from dotenv import load_dotenv
    DOTENV_PATH = os.getenv("ENV_FILE") or str(Path(__file__).with_name(".env"))
    load_dotenv(DOTENV_PATH)
except Exception:
    pass

# --- 2. Imports FastAPI & Pydantic ---
from fastapi import (
    FastAPI, Header, HTTPException, UploadFile, File, Form, Query, Depends, status, BackgroundTasks
)
from fastapi import APIRouter
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from pydantic import BaseModel, EmailStr, Field
try:
    from pydantic import field_validator
except Exception:
    def field_validator(*args, **kwargs):
        def deco(fn): return fn
        return deco

# --- 3. External deps ---
from passlib.context import CryptContext
from pymongo import MongoClient, errors
from bson import ObjectId
import jwt
import certifi
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

# --- 4. Internal modules ---
from pdf_chatbot_gemini import PDFChatbot
import crawler as web_crawler 

try:
    import indexing_utils
    HAS_INDEXING_UTILS = True
except Exception:
    indexing_utils = None
    HAS_INDEXING_UTILS = False
    print("[WARN] Không tìm thấy indexing_utils.py. Tính năng Smart Indexing sẽ không hoạt động.")

# ============================================================================
ROOT_DIR = Path(__file__).resolve().parent
_pdf_env = os.getenv("PDF_DIR", "pdfs")
PDF_DIR = str(Path(_pdf_env) if os.path.isabs(_pdf_env) else (ROOT_DIR / _pdf_env).resolve())
USER_DBS_DIR = str((ROOT_DIR / "user_dbs").resolve())
WEBSITE_API_URL = os.getenv("WEBSITE_API_URL", "http://127.0.0.1:8003").strip().strip('"').strip("'")

# ============================================================================
# PYDANTIC MODELS
# ============================================================================

class IndexRequest(BaseModel):
    username: str

class MessageRequest(BaseModel):
    username: str
    thread_id: int
    message: str
    ip_address: str
    sender_info: str

class ThreadRequest(BaseModel):
    username: str
    title: Optional[str] = None
    name: str
    phone: Optional[str] = None 
    email: Optional[str] = None
    @field_validator("phone", mode="before")
    @classmethod
    def force_string_phone(cls, v: Any) -> Optional[str]:
        if v is None: return None 
        return str(v).strip()

class APIKeyRequest(BaseModel):
    google_api_key: str
    llm_model: str
    index_dir: str = "faiss_pdf_index"
    enable_ocr: bool = False
    force_rebuild: bool = False

class ReindexFileRequest(BaseModel):
    username: str
    filename: str
    doc_type: Optional[str] = None
    enable_ocr: bool = False

# [FIX] Class này dùng để gộp 2 model trên, giúp API nhận JSON phẳng
class ReindexFullRequest(ReindexFileRequest, APIKeyRequest):
    pass

class MessageFullRequest(MessageRequest, APIKeyRequest):
    simple_chatbot_data_source: str
    domain: Union[str, List[str], None] = None
    doc_type: Optional[str] = None

class MinerUResultRequest(BaseModel):
    username: str
    filename: str
    doc_type: Optional[str] = None
    content_json: str
    faiss_base64: Optional[str] = None
    pkl_base64: Optional[str] = None
    markdown: Optional[str] = None

class RecordSyncMessageRequest(BaseModel):
    username: str
    thread_id: int
    user_message: str
    bot_message: str
    sources: Optional[List[str]] = None
    ip_address: Optional[str] = "127.0.0.1"
    sender_info: Optional[str] = "App Sync"

class ContextQueryRequest(BaseModel):
    username: str
    query: str
    doc_types: Optional[List[str]] = None
    max_chunks: Optional[int] = 4

class ThreadTitleUpdate(BaseModel):
    title: str

class ChatbotSettingsRequest(BaseModel):
    username: str
    data_source: str = Field(..., description="documents | website | all")
    doc_types: List[str] = Field(default_factory=list)
    domains: List[str] = Field(default_factory=list)
    custom_prompt: Optional[str] = ""

class CrawlRequest(BaseModel):
    domains: List[str]
    sitemaps: Optional[List[str]] = None
    appId: Optional[str] = None
    appToken: Optional[str] = None
    year: Optional[int] = None

class ContentData(BaseModel):
    title: Optional[str] = ""
    byline: Optional[str] = None
    dir: Optional[str] = None
    lang: Optional[str] = "en-US"
    content: Optional[str] = ""        
    textContent: Optional[str] = ""    
    length: Optional[int] = 0
    excerpt: Optional[str] = ""
    siteName: Optional[str] = None
    publishedTime: Optional[str] = None

class SaveContentRequest(BaseModel):
    domain: str
    url: str
    data: ContentData

class TriggerIndexRequest(BaseModel):
    domain: str

class RegisterRequest(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    provider: str = "local"
    oauth_token: Optional[str] = None
    id_token: Optional[str] = None
    credential: Optional[str] = None
    code: Optional[str] = None
    redirect_uri: Optional[str] = None
    code_verifier: Optional[str] = None

class LoginRequest(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    password: Optional[str] = None

# ============================================================================
# HELPER FUNCTIONS (BASIC)
# ============================================================================

async def search_single_dt_shared(req, dt, prompt_instr):
    from pdf_chatbot_gemini import PDFChatbot
    idir = f"faiss_pdf_index/{dt}" if dt else req.index_dir
    rdir = resolve_index_dir(idir, req.username)
    
    try:
        # Lấy bot từ cache
        bot = get_chatbot_cached(
            req.username, req.google_api_key, req.llm_model, 
            rdir, get_index_version(rdir), dt or None, prompt_instr
        )
        
        # Thực hiện tìm kiếm
        loop = asyncio.get_event_loop()
        # Chạy get_relevant_documents trong executor
        docs = await loop.run_in_executor(None, bot.get_relevant_documents, req.message)
        
        txt = "\n".join([d.page_content for d in docs])
        srcs = [d.metadata.get("source") for d in docs if d.metadata.get("source")]
        return txt, srcs
    except Exception as e:
        # In lỗi chi tiết ra console để debug
        logging.error(f"CRITICAL ERROR in search_single_dt_shared ({dt}): {e}", exc_info=True)
        return "", []

# Giả sử các hàm bổ trợ này bạn đặt trong cùng file hoặc import từ file khác
async def get_pdf_context(req, doc_types):
    """Tìm kiếm song song trên tất cả các loại tài liệu PDF đã chọn"""
    from pdf_chatbot_gemini import PDFChatbot
    bot = PDFChatbot(google_api_key=req.google_api_key)
    
    # Nếu chọn 'all', bạn cần lấy danh sách tất cả doc_types có sẵn của user
    contexts = []
    for dt in doc_types:
        # Bọc hàm đồng bộ vào run_in_executor để không chặn async loop
        loop = asyncio.get_event_loop()
        # Giả sử hàm search của bạn tên là search_context trong class PDFChatbot
        text = await loop.run_in_executor(None, bot.search_context, dt, req.message)
        if text:
            contexts.append(f"[Tài liệu: {dt}]\n{text}")
    return "\n\n".join(contexts)

async def get_web_context(req, domains):
    """Gọi API website.py song song cho nhiều domain"""
    # Bạn có thể dùng hàm call_website_chat_api có sẵn trong chatbot.py của bạn
    # Nhưng hãy sửa để nó trả về Context thô thay vì câu trả lời đã qua Gemini
    tasks = [call_website_chat_api(req, d) for d in domains]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    valid_results = [r for r in results if isinstance(r, str) and "Error" not in r]
    return "\n\n".join(valid_results)

def getenv_str(key: str, default: str = "") -> str:
    v = os.getenv(key)
    if v is None: return default
    return v.strip().strip('"').strip("'")

def get_user_pdf_dir(username: str, doc_type: Optional[str] = None) -> str:
    if doc_type and doc_type != "None": return os.path.join(PDF_DIR, doc_type, username)
    return os.path.join(PDF_DIR, username)

def _strip_empty_phone(doc: dict) -> dict:
    try:
        val = doc.get('phone', None)
        if val is None:
            doc.pop('phone', None)
            return doc
        s = str(val).strip()
        if not s:
            doc.pop('phone', None)
        else:
            doc['phone'] = s
    except Exception: pass
    return doc

def _clean_domain_url(url: str) -> str:
    if not url: return ""
    s = url.strip().lower()
    if s.endswith("/"): s = s[:-1]
    if "://" in s:
        try:
            parsed = urlparse(s)
            return parsed.hostname or s
        except: return s
    return s

def load_valid_api_keys() -> List[str]:
    try:
        with open("api_keys.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return [str(k).strip() for k in data if str(k).strip()]
        return []
    except Exception: return []

try: VALID_API_KEYS = json.load(open("api_keys.json", "r", encoding="utf-8"))
except: VALID_API_KEYS = []

APIKEY_BYPASS = "__APIKEY_BYPASS__"
def is_api_bypass(v: str) -> bool: return v == APIKEY_BYPASS
def now_utc() -> datetime: return datetime.now(timezone.utc)

async def check_headers(x_api_key: Optional[str] = Header(None), ngrok_skip_browser_warning: Optional[str] = Header(None)):
    valid_api_keys = load_valid_api_keys()
    if valid_api_keys and x_api_key not in valid_api_keys:
        raise HTTPException(status_code=401, detail="Invalid API key")

# ============================================================================
# AUTH & DATABASE CONFIG
# ============================================================================

MONGO_URI = getenv_str("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = getenv_str("DB_NAME", "chatbot_db")

try:
    if "mongodb+srv" in MONGO_URI:
        client = MongoClient(MONGO_URI, tlsCAFile=certifi.where())
    else:
        client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    users_col = db["users"]
except Exception as e:
    logging.error(f"MongoDB Connect Error: {e}")
    users_col = None

SECRET_KEY = getenv_str("SECRET_KEY", "YOUR_SUPER_SECRET_KEY_HERE")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 30  # 30 days
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
GOOGLE_CLIENT_ID = getenv_str("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = getenv_str("GOOGLE_CLIENT_SECRET", "")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def hash_password(password):
    return pwd_context.hash(password)

def issue_jwt(user_doc: dict) -> str:
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode = {
        "sub": user_doc.get("email") or user_doc.get("phone") or str(user_doc["_id"]),
        "id": str(user_doc["_id"]),
        "exp": expire
    }
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_optional_user_email(authorization: Optional[str] = Header(None), x_api_key: Optional[str] = Header(None)) -> Optional[str]:
    valid_keys = load_valid_api_keys()
    if x_api_key and valid_keys and x_api_key in valid_keys: return APIKEY_BYPASS
    if not authorization: return None
    try:
        token = authorization.replace("Bearer ", "").strip()
        if not token: return None
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError: return None

async def get_current_user_email(optional_email: Optional[str] = Depends(get_optional_user_email)) -> str:
    if not optional_email: raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Could not validate credentials", headers={"WWW-Authenticate": "Bearer"})
    return optional_email

# ============================================================================
# APP SETUP
# ============================================================================

app = FastAPI(title="Chatbot API (with Account & Smart Indexing)")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_origin_regex=".*", allow_credentials=True, allow_methods=["*"], allow_headers=["*"], expose_headers=["*"], max_age=86400)

os.makedirs(PDF_DIR, exist_ok=True)
os.makedirs(USER_DBS_DIR, exist_ok=True)
app.mount("/pdfs", StaticFiles(directory=PDF_DIR), name="pdfs")

# --- THÊM MỚI TỪ ĐÂY ---
# Biến toàn cục chứa HTTPX Client dùng chung
http_client: httpx.AsyncClient = None

@app.on_event("startup")
async def startup_event():
    global http_client
    # Khởi tạo client 1 lần duy nhất, giữ kết nối (Connection Pool)
    http_client = httpx.AsyncClient(timeout=60.0)
    print("🚀 Đã khởi tạo Global HTTPX Client.")
    
    # --- BẮT ĐẦU ĐOẠN SỬA: ĐÁNH THỨC GPU Ở LUỒNG CHÍNH ---
    try:
        import torch
        if torch.cuda.is_available():
            torch.zeros(1).cuda() # Mẹo nhỏ ép GPU phải thức dậy ngay lập tức
            print("🔥 Đã đánh thức GPU (CUDA) thành công ở luồng chính!")
            
        if HAS_INDEXING_UTILS:
            print("🔥 Đang mồi sẵn mô hình AI vào VRAM Card đồ họa...")
            indexing_utils._get_embeddings()
    except Exception as e:
        print(f"⚠️ Lỗi khi hâm nóng GPU: {e}")
    # --- KẾT THÚC ĐOẠN SỬA ---

@app.on_event("shutdown")
async def shutdown_event():
    global http_client
    if http_client:
        await http_client.aclose()
        print("🛑 Đã đóng Global HTTPX Client.")
# --- KẾT THÚC THÊM MỚI ---

# ============================================================================
# ACCOUNT ROUTES (Moved up & Defined Router)
# ============================================================================

# [QUAN TRỌNG] Khai báo Router ở đây để tránh NameError
account_router = APIRouter(tags=["account"])

@account_router.post("/register")
async def register(p: RegisterRequest, _: Any = Depends(check_headers)):
    if p.provider == "local":
        if not p.full_name or (not p.email and not p.phone) or not p.password: raise HTTPException(400, "Missing fields")
        doc = {"full_name": p.full_name, "email": p.email, "phone": p.phone, "password_hash": hash_password(p.password), "provider": "local", "created_at": now_utc()}
        if p.email and users_col is not None and users_col.find_one({"email": p.email}): return JSONResponse(400, {"success": False, "message": "Email exists"})
        if users_col is None: raise HTTPException(500, "Database not connected")
        try:
            r = users_col.insert_one(_strip_empty_phone(doc))
            u = users_col.find_one({"_id": r.inserted_id})
            return {"success": True, "token": issue_jwt(u), "id": str(u["_id"]), "full_name": u["full_name"], "email": u.get("email"), "provider": "local"}
        except: raise HTTPException(500, "Register failed")
    
    idt = p.oauth_token or p.id_token or p.credential
    if not idt and p.code:
        async with httpx.AsyncClient() as c:
            r = await c.post("https://oauth2.googleapis.com/token", data={"client_id": GOOGLE_CLIENT_ID, "client_secret": GOOGLE_CLIENT_SECRET, "code": p.code, "grant_type": "authorization_code", "redirect_uri": p.redirect_uri})
            if r.status_code == 200: idt = r.json().get("id_token")
    if not idt: raise HTTPException(400, "Missing token")
    if users_col is None: raise HTTPException(500, "Database not connected")
    try:
        claims = google_id_token.verify_oauth2_token(idt, google_requests.Request(), GOOGLE_CLIENT_ID or None)
        sub, em = claims.get("sub"), claims.get("email")
        u = users_col.find_one({"oauth.sub": sub}) or users_col.find_one({"email": em})
        if u:
            users_col.update_one({"_id": u["_id"]}, {"$set": {"last_login": now_utc(), "avatar_url": claims.get("picture")}})
            return {"success": True, "token": issue_jwt(u), "id": str(u["_id"]), "email": em, "provider": "gmail"}
        doc = {"full_name": claims.get("name"), "email": em, "provider": "gmail", "oauth": {"sub": sub, "picture": claims.get("picture")}, "avatar_url": claims.get("picture"), "created_at": now_utc()}
        r = users_col.insert_one(_strip_empty_phone(doc))
        u = users_col.find_one({"_id": r.inserted_id})
        return {"success": True, "token": issue_jwt(u), "id": str(u["_id"]), "email": em, "provider": "gmail"}
    except Exception as e: raise HTTPException(401, f"Google Error: {e}")

@account_router.post("/login")
async def login_local(p: LoginRequest, _: Any = Depends(check_headers)):
    if users_col is None: raise HTTPException(500, "Database not connected")
    u = users_col.find_one({"email": p.email}) if p.email else users_col.find_one({"phone": p.phone})
    if not u or not verify_password(p.password, u.get("password_hash")): raise HTTPException(401, "Wrong credentials")
    return {"success": True, "token": issue_jwt(u), "id": str(u["_id"])}

@account_router.get("/health")
async def acc_health(): 
    try: client.admin.command("ping"); return {"ok": True, "db": True}
    except: return JSONResponse(500, {"ok": False})

app.include_router(account_router)

# ============================================================================
# LOGIC ROUTES (Crawler, Save, Trigger)
# ============================================================================

@app.post("/crawl-domains")
async def crawl_domains(req: CrawlRequest, _: Any = Depends(check_headers)):
    try:
        if not req.sitemaps: return {"success": True, "total_urls": 0, "data": {}, "message": "No sitemaps provided"}
        all_urls = web_crawler.get_urls_from_sitemaps(req.sitemaps)
        results = {}
        for url in all_urls:
            try:
                host = urlparse(url).hostname
                if host:
                    host = host.replace("www.", "")
                    if host not in results: results[host] = []
                    results[host].append(url)
            except: continue
        final_results = {}
        if req.domains:
            for d in req.domains:
                clean_d = _clean_domain_url(d)
                for k, v in results.items():
                    if clean_d in k or k in clean_d: final_results[clean_d] = v
        else: final_results = results
        return {"success": True, "total_urls": sum(len(v) for v in final_results.values()), "data": final_results}
    except Exception as e: raise HTTPException(500, f"Lỗi crawler: {str(e)}")

@app.post("/save-content-url")
async def save_content_url(req: SaveContentRequest, _: Any = Depends(check_headers)):
    try:
        host = _clean_domain_url(req.domain)
        if not host: raise HTTPException(400, "Invalid domain")
        result = web_crawler.save_content_only(host, req.url, req.data.dict())
        if not result.get("ok"): raise HTTPException(500, detail=result.get("error"))
        return {"success": True, "hash": result.get("hash")}
    except Exception as e: raise HTTPException(500, detail=str(e))

@app.post("/trigger-index-domain")
async def trigger_index_domain(req: TriggerIndexRequest, _: Any = Depends(check_headers)):
    try:
        host = _clean_domain_url(req.domain)
        if not host: raise HTTPException(400, "Invalid domain")
        result = await asyncio.to_thread(web_crawler.build_index_for_domain, host)
        if not result.get("ok"): raise HTTPException(500, detail=result.get("error"))
        
        reload_msg = "Reload skipped"
        try:
            # SỬ DỤNG GLOBAL CLIENT, THÊM TIMEOUT RIÊNG
            resp = await http_client.post(
                f"{WEBSITE_API_URL.rstrip('/')}/reload-index", 
                json={"domain": host}, 
                timeout=10.0
            )
            reload_msg = "Reload success" if resp.status_code == 200 else f"Reload failed: {resp.text}"
        except Exception as e: reload_msg = f"Reload error: {str(e)}"
        
        return {"success": True, "domain": host, "vectors": result.get("total_vectors"), "message": f"Index built. {reload_msg}"}
    except Exception as e: raise HTTPException(500, detail=str(e))

@app.get("/crawl-domains/status/{job_id}")
async def crawl_domains_status(job_id: str): return {"status": "not_found", "message": "Deprecated"}

# ============================================================================
# ROUTES: DATABASE & FILES (Files management)
# ============================================================================

USER_DBS_DIR = str((ROOT_DIR / "user_dbs").resolve())

def get_user_db(username: str):
    db_path = os.path.join(USER_DBS_DIR, f"chatbot_user_{username}.db")
    if not os.path.exists(db_path): raise HTTPException(404, "User database not found.")
    conn = sqlite3.connect(db_path, check_same_thread=False)
    return conn, conn.cursor()

def init_user_tables(conn):
    conn.execute("""CREATE TABLE IF NOT EXISTS threads (id INTEGER PRIMARY KEY, title TEXT, name TEXT, email TEXT, phone TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id INTEGER, role TEXT, content TEXT, sources TEXT, created TEXT, ip_address TEXT, sender_info TEXT)""")
    conn.commit()

SETTINGS_DB_PATH = os.path.join(USER_DBS_DIR, "chatbot_settings.db")
def _sha256(s: str) -> str: return hashlib.sha256((s or "").encode("utf-8")).hexdigest()

def init_settings_db():
    os.makedirs(USER_DBS_DIR, exist_ok=True)
    conn = sqlite3.connect(SETTINGS_DB_PATH, check_same_thread=False)
    conn.execute("""CREATE TABLE IF NOT EXISTS chatbot_settings (username TEXT PRIMARY KEY, api_key_hash TEXT, data_source TEXT, doc_types_json TEXT, domains_json TEXT, custom_prompt TEXT, updated_at TEXT)""")
    try: conn.execute("ALTER TABLE chatbot_settings ADD COLUMN domains_json TEXT")
    except: pass
    try: conn.execute("ALTER TABLE chatbot_settings ADD COLUMN custom_prompt TEXT")
    except: pass
    conn.commit(); conn.close()

def get_chatbot_settings_internal(username: str) -> Dict[str, Any]:
    init_settings_db()
    conn = sqlite3.connect(SETTINGS_DB_PATH, check_same_thread=False)
    cur = conn.cursor()
    cur.execute("SELECT username, api_key_hash, data_source, doc_types_json, updated_at, domains_json, custom_prompt FROM chatbot_settings WHERE username = ?", (username,))
    row = cur.fetchone(); conn.close()
    if not row: return {"username": username, "api_key_hash": "", "data_source": "", "doc_types": [], "domains": [], "custom_prompt": "", "updated_at": None, "has_settings": False}
    try: doc_types = json.loads(row[3] or "[]") if row[3] else []
    except: doc_types = []
    try: domains = json.loads(row[5] or "[]") if row[5] else []
    except: domains = []
    return {"username": row[0], "api_key_hash": (row[1] or "").strip(), "data_source": (row[2] or "").strip().lower(), "doc_types": doc_types, "domains": domains, "custom_prompt": (row[6] or "").strip(), "updated_at": row[4], "has_settings": True}

def upsert_chatbot_settings(username: str, x_api_key: str, data_source: str, doc_types: List[str], domains: List[str] = None, custom_prompt: str = "") -> Dict[str, Any]:
    init_settings_db()
    ds = (data_source or "").strip().lower()
    if ds not in ("documents", "website", "all"): raise HTTPException(400, "data_source phải là documents | website | all")
    clean_doc_types = list(set([str(t).strip().lower() for t in (doc_types or []) if str(t).strip()]))
    clean_domains = list(set([str(d).strip().lower() for d in (domains or []) if str(d).strip()]))
    clean_prompt = (custom_prompt or "").strip()
    now = datetime.utcnow().isoformat() + "Z"
    conn = sqlite3.connect(SETTINGS_DB_PATH, check_same_thread=False)
    conn.execute("""INSERT INTO chatbot_settings (username, api_key_hash, data_source, doc_types_json, domains_json, custom_prompt, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(username) DO UPDATE SET api_key_hash=excluded.api_key_hash, data_source=excluded.data_source, doc_types_json=excluded.doc_types_json, domains_json=excluded.domains_json, custom_prompt=excluded.custom_prompt, updated_at=excluded.updated_at""", (username, _sha256(x_api_key.strip()), ds, json.dumps(clean_doc_types, ensure_ascii=False), json.dumps(clean_domains, ensure_ascii=False), clean_prompt, now))
    conn.commit(); conn.close()
    return {"username": username, "data_source": ds, "doc_types": clean_doc_types, "domains": clean_domains, "custom_prompt": clean_prompt, "updated_at": now}

DEFAULT_CHATBOT_SETTINGS = {"data_source": "all", "doc_types": ["summary"], "domains": [], "custom_prompt": ""}

@app.get("/settings/chatbot/{username}")
async def api_get_settings_chatbot(username: str, x_api_key: Optional[str] = Header(None, alias="X-API-Key"), _: Any = Depends(check_headers)):
    if not x_api_key: raise HTTPException(401, "Thiếu X-API-Key")
    cfg = get_chatbot_settings_internal(username)
    if not cfg.get("has_settings"): return {"username": username, "exists": False, **DEFAULT_CHATBOT_SETTINGS}
    return {"username": username, "exists": True, "data_source": cfg.get("data_source"), "doc_types": cfg.get("doc_types"), "domains": cfg.get("domains"), "custom_prompt": cfg.get("custom_prompt"), "updated_at": cfg.get("updated_at")}

@app.post("/settings/chatbot")
async def api_save_settings_chatbot(payload: ChatbotSettingsRequest, x_api_key: Optional[str] = Header(None, alias="X-API-Key"), _: Any = Depends(check_headers)):
    if not x_api_key: raise HTTPException(401, "Thiếu X-API-Key")
    return {"success": True, **upsert_chatbot_settings(payload.username, x_api_key, payload.data_source, payload.doc_types, payload.domains, payload.custom_prompt)}

@app.get("/healthz")
async def healthz(): return {"ok": True}

@app.get("/debug/env")
async def debug_env(): return {"ok": True}

@app.post("/init-db/{username}")
async def init_user_db(username: str, current_email: str = Depends(lambda: "")): 
    os.makedirs(USER_DBS_DIR, exist_ok=True)
    db_path = os.path.join(USER_DBS_DIR, f"chatbot_user_{username}.db")
    if os.path.exists(db_path): return {"message": "Database already exists."}
    conn = sqlite3.connect(db_path)
    init_user_tables(conn); conn.close()
    return {"message": "Database created for user", "username": username}

def _invalidate_file_in_meta(username: str, doc_type: Optional[str], file_path: str):
    if not HAS_INDEXING_UTILS: return
    try:
        _, index_dir = indexing_utils._ensure_dirs_for_type(username, doc_type)
        meta_path = os.path.join(index_dir, "index_meta.json")
        if os.path.exists(meta_path):
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            files_map = meta.get("files", {})
            if file_path in files_map:
                files_map[file_path] = "FORCE_REINDEX_" + str(int(time.time()))
                with open(meta_path, "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"Lỗi invalidate meta: {e}")

@app.post("/upload-pdf")
async def upload_pdf(file: UploadFile = File(...), username: str = Form(...), doc_type: Optional[str] = Form(None)):
    allowed = [".pdf", ".doc", ".docx", ".xls", ".xlsx"]
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in allowed: raise HTTPException(400, "Unsupported file type.")
    save_dir = get_user_pdf_dir(username, doc_type)
    os.makedirs(save_dir, exist_ok=True)
    save_path = os.path.join(save_dir, file.filename)
    try:
        async with aiofiles.open(save_path, "wb") as out: await out.write(await file.read())
        _invalidate_file_in_meta(username, doc_type, os.path.abspath(save_path))
        return {"success": True, "username": username, "doc_type": doc_type}
    except Exception as e: raise HTTPException(500, detail=str(e))

class AnalyzePdfRequest(BaseModel):
    file_path: str

@app.post("/analyze_pdf")
async def handle_analyze_pdf(req: AnalyzePdfRequest):
    import base64
    import traceback
    
    # URL của Ngrok/Cloudflare
    remote_url = getenv_str("REMOTE_MINERU_URL", "https://advanced-eagerly-lioness.ngrok-free.app").rstrip('/')
    
    if not remote_url:
        raise HTTPException(status_code=500, detail="Chưa cấu hình REMOTE_MINERU_URL")
        
    try:
        pdf_abs_path = req.file_path
        if not os.path.exists(pdf_abs_path):
            raise HTTPException(status_code=404, detail="Không tìm thấy file trên ổ đĩa")
            
        with open(pdf_abs_path, "rb") as f:
            pdf_bytes = f.read()
            
        file_b64 = base64.b64encode(pdf_bytes).decode('utf-8')
        
        payload = {
            "file_path": os.path.basename(pdf_abs_path),
            "file_base64": file_b64
        }
        
        # Đảm bảo model đã được tải bằng cách gọi /load_model
        try:
            # Dùng httpx tạm thời không giới hạn timeout (chờ tới khi phân tích xong)
            async with httpx.AsyncClient(timeout=30.0) as client:
                await client.post(f"{remote_url}/load_model")
        except Exception as e:
            print(f"Warning: Không thể gọi /load_model: {e}")
            
        # Gọi phân tích
        async with httpx.AsyncClient(timeout=600.0) as client:
            resp = await client.post(
                f"{remote_url}/analyze",
                json=payload
            )
            
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Lỗi từ Remote AI: {resp.text}")
            
        res_data = resp.json()
        if res_data.get("status") != "success":
            raise HTTPException(status_code=500, detail=res_data.get("message", "Lỗi không xác định từ AI"))
            
        json_output = res_data.get("data")
        if isinstance(json_output, str):
            try:
                json_output = json.loads(json_output)
            except:
                json_output = []
                
        if isinstance(json_output, list):
            # Trích xuất hình ảnh từ base64
            img_dir = pdf_abs_path + "_images"
            if not os.path.exists(img_dir):
                os.makedirs(img_dir)
                
            for item in json_output:
                if 'image_base64' in item:
                    img_filename = f"page_{item.get('page_idx', 0)+1}_{item.get('type')}_{item.get('id', 'x')}.png"
                    img_path = os.path.join(img_dir, img_filename)
                    with open(img_path, "wb") as img_file:
                        img_file.write(base64.b64decode(item['image_base64']))
                    item['image_url'] = f"{os.path.basename(img_dir)}/{img_filename}"
                    del item['image_base64']
                    
            json_str = json.dumps(json_output, ensure_ascii=False)
        else:
            json_str = str(json_output)
            
        json_filename = f"{pdf_abs_path}.mineru.json"
        with open(json_filename, "w", encoding="utf-8") as f:
            f.write(json_str)
            
        return {"status": "success", "data": json_output}
        
    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/upload-mineru-result")
async def upload_mineru_result(req: MinerUResultRequest, background_tasks: BackgroundTasks):
    try:
        import base64
        # 1. Lưu file json xuống ổ đĩa để indexing_utils tự động pick up
        save_dir = get_user_pdf_dir(req.username, req.doc_type)
        os.makedirs(save_dir, exist_ok=True)
        # Lưu file với đuôi .mineru.json thay vì .pdf
        base_name = os.path.splitext(req.filename)[0]
        json_path = os.path.join(save_dir, f"{base_name}.mineru.json")
        
        async with aiofiles.open(json_path, "w", encoding="utf-8") as out:
            await out.write(req.content_json)

        # 2. Lưu file Markdown nếu có kèm theo
        if req.markdown:
            md_path = os.path.join(save_dir, f"{base_name}.md")
            async with aiofiles.open(md_path, "w", encoding="utf-8") as out:
                await out.write(req.markdown)

        # 3. Đồng bộ trực tiếp bản vector FAISS & PKL lên server nếu có gửi lên
        if HAS_INDEXING_UTILS and (req.faiss_base64 or req.pkl_base64):
            try:
                _, index_dir = indexing_utils._ensure_dirs_for_type(req.username, req.doc_type)
                os.makedirs(index_dir, exist_ok=True)
                
                if req.faiss_base64:
                    faiss_bytes = base64.b64decode(req.faiss_base64)
                    faiss_file = os.path.join(index_dir, "index.faiss")
                    async with aiofiles.open(faiss_file, "wb") as f_out:
                        await f_out.write(faiss_bytes)

                if req.pkl_base64:
                    pkl_bytes = base64.b64decode(req.pkl_base64)
                    pkl_file = os.path.join(index_dir, "index.pkl")
                    async with aiofiles.open(pkl_file, "wb") as p_out:
                        await p_out.write(pkl_bytes)

                # Cập nhật metadata index_meta.json
                meta = indexing_utils._load_meta(index_dir)
                files_map = meta.setdefault("files", {})
                files_map[os.path.abspath(json_path)] = str(int(time.time()))
                pdf_counterpart = os.path.join(save_dir, f"{base_name}.pdf")
                files_map[os.path.abspath(pdf_counterpart)] = str(int(time.time()))
                indexing_utils._save_meta(index_dir, meta)
                print(f"[UploadMinerU] Đã đồng bộ FAISS & metadata thành công cho: {req.filename}")
            except Exception as fe:
                print(f"[UploadMinerU] Cảnh báo lưu FAISS server: {fe}")
            
        _invalidate_file_in_meta(req.username, req.doc_type, os.path.abspath(json_path))
        return {"success": True, "message": "Đã lưu kết quả MinerU, FAISS và metadata lên máy chủ"}
    except Exception as e:
        raise HTTPException(500, detail=str(e))

# ============================================================================
# SYNC DỮ LIỆU FAISS TỪ LOCAL (ai.type Desktop) LÊN SERVER
# ============================================================================
class SyncLocalDocRequest(BaseModel):
    username: str
    doc_type: Optional[str] = None
    filename: str
    markdown: Optional[str] = None
    content_json: Optional[str] = None

class SyncLocalFaissRequest(BaseModel):
    username: str
    doc_type: Optional[str] = None
    faiss_base64: str
    pkl_base64: str
    filenames: List[str] = []

class SyncManifestFile(BaseModel):
    name: str          # ví dụ: "abc.md" hoặc "abc.mineru.json"
    sha256: str

class SyncLocalManifestRequest(BaseModel):
    username: str
    doc_type: Optional[str] = None
    files: List[SyncManifestFile] = []
    faiss_sha256: Optional[str] = None
    pkl_sha256: Optional[str] = None

@app.post("/sync-local-manifest")
async def sync_local_manifest(req: SyncLocalManifestRequest):
    """So sánh sha256 local với server, trả về danh sách file cần đẩy lên (thiếu hoặc khác nội dung)."""
    if not HAS_INDEXING_UTILS:
        raise HTTPException(500, detail="Missing indexing_utils")
    try:
        save_dir = get_user_pdf_dir(req.username, req.doc_type)
        need = []
        for f in req.files:
            safe_name = os.path.basename(f.name)
            p = os.path.join(save_dir, safe_name)
            if not os.path.exists(p) or indexing_utils._file_sha256(p) != f.sha256:
                need.append(f.name)

        index_dir = os.path.join(indexing_utils.INDEX_BASE_DIR, req.doc_type, req.username) if req.doc_type and req.doc_type != "None" \
            else os.path.join(indexing_utils.INDEX_BASE_DIR, req.username)
        need_faiss = False
        for local_hash, fname in ((req.faiss_sha256, "index.faiss"), (req.pkl_sha256, "index.pkl")):
            p = os.path.join(index_dir, fname)
            if not local_hash or not os.path.exists(p) or indexing_utils._file_sha256(p) != local_hash:
                need_faiss = True
        return {"need": need, "need_faiss": need_faiss, "total": len(req.files)}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, detail=str(e))

@app.post("/sync-local-doc")
async def sync_local_doc(req: SyncLocalDocRequest):
    """Nhận 1 tài liệu đã bóc tách từ local (Markdown + MinerU JSON) và lưu vào thư mục tài liệu của user."""
    try:
        save_dir = get_user_pdf_dir(req.username, req.doc_type)
        os.makedirs(save_dir, exist_ok=True)
        base_name = os.path.splitext(os.path.basename(req.filename))[0]
        written = []
        if req.content_json:
            json_path = os.path.join(save_dir, f"{base_name}.mineru.json")
            async with aiofiles.open(json_path, "w", encoding="utf-8") as out:
                await out.write(req.content_json)
            written.append(f"{base_name}.mineru.json")
        if req.markdown:
            md_path = os.path.join(save_dir, f"{base_name}.md")
            async with aiofiles.open(md_path, "w", encoding="utf-8") as out:
                await out.write(req.markdown)
            written.append(f"{base_name}.md")
        return {"success": True, "filename": req.filename, "written": written}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, detail=str(e))

@app.post("/sync-local-faiss")
async def sync_local_faiss(req: SyncLocalFaissRequest):
    """Ghi đè index.faiss + index.pkl bằng bản local và đánh dấu các tài liệu tương ứng là đã index."""
    if not HAS_INDEXING_UTILS:
        raise HTTPException(500, detail="Missing indexing_utils")
    try:
        import base64
        save_dir = get_user_pdf_dir(req.username, req.doc_type)
        _, index_dir = indexing_utils._ensure_dirs_for_type(req.username, req.doc_type)
        os.makedirs(index_dir, exist_ok=True)

        faiss_file = os.path.join(index_dir, "index.faiss")
        pkl_file = os.path.join(index_dir, "index.pkl")
        async with aiofiles.open(faiss_file, "wb") as f_out:
            await f_out.write(base64.b64decode(req.faiss_base64))
        async with aiofiles.open(pkl_file, "wb") as p_out:
            await p_out.write(base64.b64decode(req.pkl_base64))

        # Dùng sha256 thật của file để indexer coi như "không đổi" và không build lại đè bản vừa sync
        meta = indexing_utils._load_meta(index_dir)
        files_map = meta.setdefault("files", {})
        marked = 0
        for name in req.filenames:
            base_name = os.path.splitext(os.path.basename(name))[0]
            for candidate in (f"{base_name}.mineru.json", f"{base_name}.pdf"):
                p = os.path.abspath(os.path.join(save_dir, candidate))
                if os.path.exists(p):
                    files_map[p] = indexing_utils._file_sha256(p)
                    marked += 1
        indexing_utils._save_meta(index_dir, meta)

        print(f"[SyncLocalFaiss] {req.username}/{req.doc_type}: faiss={os.path.getsize(faiss_file)}B, pkl={os.path.getsize(pkl_file)}B, marked={marked}")
        return {
            "success": True,
            "faiss_size": os.path.getsize(faiss_file),
            "pkl_size": os.path.getsize(pkl_file),
            "marked_files": marked
        }
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, detail=str(e))

@app.get("/list-files/{username}")
async def list_user_files(username: str):
    if not HAS_INDEXING_UTILS:
        return {"files": [], "error": "Missing indexing_utils"}

    import os
    import json
    from datetime import datetime
    
    all_files = []
    
    # 1. Tìm tất cả các thư mục doc_type cần quét (bao gồm cả thư mục gốc None)
    doc_types_to_scan = [None]
    if os.path.isdir(PDF_DIR):
        for e in os.scandir(PDF_DIR):
            if e.is_dir() and e.name != username: # e.name chính là doc_type (analysis, slides...)
                user_sub = os.path.join(PDF_DIR, e.name, username)
                if os.path.isdir(user_sub):
                    doc_types_to_scan.append(e.name)

    doc_types_to_scan = list(set(doc_types_to_scan))

    # 2. Quét từng thư mục để lấy danh sách file và đối chiếu trạng thái
    for dt in doc_types_to_scan:
        if dt:
            pdf_dir = os.path.join(indexing_utils.PDF_BASE_DIR, dt, username)
            index_dir = os.path.join(indexing_utils.INDEX_BASE_DIR, dt, username)
        else:
            pdf_dir = os.path.join(indexing_utils.PDF_BASE_DIR, username)
            index_dir = os.path.join(indexing_utils.INDEX_BASE_DIR, username)
        
        # --- BƯỚC QUAN TRỌNG: Đọc danh sách các file ĐÃ INDEX ---
        indexed_paths = set()
        meta_path = os.path.join(index_dir, "index_meta.json")
        if os.path.exists(meta_path):
            try:
                with open(meta_path, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                    files_map = meta.get("files", {})
                    
                    # Duyệt qua các file trong meta
                    for path, hash_val in files_map.items():
                        # Nếu file có mã hash bình thường (không bị đánh dấu ép chạy lại)
                        if not str(hash_val).startswith("FORCE_REINDEX_"):
                            indexed_paths.add(path)
            except Exception as e:
                print(f"Lỗi đọc meta của {dt}: {e}")

        # --- BƯỚC LẤY FILE THỰC TẾ ---
        if os.path.isdir(pdf_dir):
            seen_bases = set()
            for f in os.scandir(pdf_dir):
                is_pdf = f.name.lower().endswith(".pdf")
                is_json = f.name.lower().endswith(".mineru.json")
                if f.is_file() and (is_pdf or is_json):
                    base_name = f.name[:-12] if is_json else f.name[:-4]
                    if base_name in seen_bases: continue
                    seen_bases.add(base_name)
                    
                    logical_name = f"{base_name}.pdf"
                    
                    abs_pdf = os.path.join(pdf_dir, logical_name)
                    abs_json = os.path.join(pdf_dir, f"{base_name}.mineru.json")
                    is_indexed = abs_pdf in indexed_paths or abs_json in indexed_paths
                    
                    file_stat = f.stat()
                    all_files.append({
                        "filename": logical_name,
                        "doc_type": dt if dt else "None",
                        "size_mb": round(file_stat.st_size / (1024 * 1024), 2),
                        "updated_at": datetime.fromtimestamp(file_stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                        "is_indexed": is_indexed
                    })

    # Sắp xếp file mới nhất lên đầu
    all_files.sort(key=lambda x: x["updated_at"], reverse=True)
    
    return {"files": all_files}

@app.delete("/delete-file/{username}")
async def delete_file(username: str, background_tasks: BackgroundTasks, filename: str = Query(...), doc_type: Optional[str] = Query(None)):
    base_name = filename[:-4] if filename.lower().endswith(".pdf") else filename
    pdf_path = os.path.join(get_user_pdf_dir(username, doc_type), f"{base_name}.pdf")
    json_path = os.path.join(get_user_pdf_dir(username, doc_type), f"{base_name}.mineru.json")
    
    deleted = False
    if os.path.exists(pdf_path):
        os.remove(pdf_path)
        deleted = True
    if os.path.exists(json_path):
        os.remove(json_path)
        deleted = True
        
    if not deleted: raise HTTPException(404, "File not found")
    
    # Tự động kích hoạt luồng Index để FAISS "Đập đi xây lại" khi phát hiện mất file
    if HAS_INDEXING_UTILS:
        background_tasks.add_task(run_indexing_task, username, "faiss_pdf_index", False, False, doc_type)
        
    return {"ok": True}

@app.get("/index-progress/{username}")
async def get_index_progress(username: str):
    """API để Frontend gọi liên tục mỗi 2 giây nhằm lấy % tiến độ"""
    if not HAS_INDEXING_UTILS: return {"is_running": False}
    
    # Tìm xem có thư mục nào đang chứa file progress.json không
    doc_types_to_scan = [None]
    if os.path.isdir(PDF_DIR):
        for e in os.scandir(PDF_DIR):
            if e.is_dir() and e.name != username:
                # SỬA LỖI: Chỉ thêm vào list nếu thư mục thực sự tồn tại (tránh tạo nhầm thư mục user khác thành doc_type)
                user_sub = os.path.join(PDF_DIR, e.name, username)
                if os.path.isdir(user_sub):
                    doc_types_to_scan.append(e.name)
                
    for dt in doc_types_to_scan:
        # get dirs without creating them just to read progress.json
        # Thay vì gọi _ensure_dirs_for_type (có side-effect tạo thư mục), ta tự build path:
        if dt:
            index_dir = os.path.abspath(os.path.join(indexing_utils.INDEX_BASE_DIR, dt, username))
        else:
            index_dir = os.path.abspath(os.path.join(indexing_utils.INDEX_BASE_DIR, username))
            
        prog_path = os.path.join(index_dir, "progress.json")
        
        if os.path.exists(prog_path):
            try:
                with open(prog_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    data["is_running"] = True
                    data["doc_type"] = str(dt)
                    return data
            except: pass
            
    # Nếu không tìm thấy file progress nào, nghĩa là đã xong (hoặc chưa chạy)
    return {"is_running": False, "percent": 100, "status": "Hoàn tất"}

# ============================================================================
# SMART INDEXING LOGIC
# ============================================================================

# Thêm tham số target_doc_type vào cuối
def run_indexing_task(username: str, index_dir: str, enable_ocr: bool, force_rebuild: bool, target_doc_type: Optional[str] = None):
    if not HAS_INDEXING_UTILS: return
    print(f"--> [Task] Bắt đầu Index Smart cho user: {username} (Force={force_rebuild}, OCR={enable_ocr})")
    
    dts_to_scan = []
    
    # Chỉ thêm thư mục gốc (None) nếu nó thực sự tồn tại (tránh tự động sinh thư mục rỗng)
    if os.path.isdir(os.path.join(PDF_DIR, username)):
        dts_to_scan.append(None)
    
    # --- THÊM MỚI TẠI ĐÂY: Ép buộc quét thư mục người dùng yêu cầu ---
    if target_doc_type and target_doc_type not in dts_to_scan:
        dts_to_scan.append(target_doc_type)
    # -----------------------------------------------------------------

    if os.path.isdir(PDF_DIR):
        for e in os.scandir(PDF_DIR):
            if e.is_dir() and e.name != username:
                user_sub = os.path.join(PDF_DIR, e.name, username)
                if os.path.isdir(user_sub): dts_to_scan.append(e.name)
    
    dts_to_scan = list(set(dts_to_scan))

    for dt in dts_to_scan:
        try:
            if force_rebuild:
                _, real_idx_dir = indexing_utils._ensure_dirs_for_type(username, dt)
                meta_file = os.path.join(real_idx_dir, "index_meta.json")
                if os.path.exists(meta_file): os.remove(meta_file)

            res = indexing_utils.index_documents(username, doc_type=dt, enable_ocr=enable_ocr)
            print(f"--> [Task] Kết quả index ({dt}): {res.get('chunks_added', 0)} chunks mới.")
        except Exception as e: print(f"--> [Task] Lỗi index doc_type={dt}: {e}")

    print(f"--> [Task] Hoàn tất index cho {username}.")

@app.post("/index-files/{username}")
async def index_user_pdfs(username: str, key_req: APIKeyRequest, background_tasks: BackgroundTasks):
    if not HAS_INDEXING_UTILS: raise HTTPException(500, "Server chưa có module indexing_utils.")
    
    # Thêm tham số None vào cuối
    background_tasks.add_task(run_indexing_task, username, key_req.index_dir, key_req.enable_ocr, key_req.force_rebuild, None)
    
    mode_msg = "Force Re-index" if key_req.force_rebuild else "Smart Update"
    return {"success": True, "message": f"Đã nhận lệnh {mode_msg}.", "ocr_enabled": key_req.enable_ocr}

@app.post("/reindex-file")
async def reindex_specific_file(
    full_req: ReindexFullRequest, 
    background_tasks: BackgroundTasks, 
    _: Any = Depends(check_headers)
):
    if not HAS_INDEXING_UTILS: raise HTTPException(500, "Server chưa có module indexing_utils.")
    
    # 1. Định vị file
    pdf_dir = get_user_pdf_dir(full_req.username, full_req.doc_type)
    
    base_name = full_req.filename[:-4] if full_req.filename.lower().endswith(".pdf") else full_req.filename
    target_pdf = os.path.abspath(os.path.join(pdf_dir, f"{base_name}.pdf"))
    target_json = os.path.abspath(os.path.join(pdf_dir, f"{base_name}.mineru.json"))
    
    if not (os.path.exists(target_pdf) or os.path.exists(target_json)): 
        raise HTTPException(404, f"Không tìm thấy file: {full_req.filename}")

    # 2. Định vị meta file
    _, index_dir = indexing_utils._ensure_dirs_for_type(full_req.username, full_req.doc_type)
    meta_path = os.path.join(index_dir, "index_meta.json")

    # 3. Hack: "Corrupt" hash trong meta file
    try:
        if os.path.exists(meta_path):
            with open(meta_path, "r", encoding="utf-8") as f: meta = json.load(f)
            files_map = meta.get("files", {})
            modified = False
            if target_pdf in files_map:
                files_map[target_pdf] = "FORCE_REINDEX_" + str(int(time.time()))
                modified = True
            if target_json in files_map:
                files_map[target_json] = "FORCE_REINDEX_" + str(int(time.time()))
                modified = True
                
            if modified:
                with open(meta_path, "w", encoding="utf-8") as f: json.dump(meta, f, ensure_ascii=False, indent=2)
                print(f"--> [Reindex-File] Đã đánh dấu 'dirty' cho: {full_req.filename}")
    except Exception as e: print(f"--> [Reindex-File] Lỗi sửa meta: {e}")

    # 4. Chạy task index
    background_tasks.add_task(
        run_indexing_task, 
        full_req.username, 
        full_req.index_dir, 
        full_req.enable_ocr, 
        False,
        full_req.doc_type  # <--- TRUYỀN THAM SỐ VÀO ĐÂY ĐỂ ÉP QUÉT
    )
    return {"success": True, "message": f"Đang re-index file '{full_req.filename}'.", "filename": full_req.filename}

# ============================================================================
# SEARCH / RETRIEVAL / HELPERS
# ============================================================================

def resolve_index_dir(index_dir: Optional[str], username: str) -> str:
    base = (index_dir or "faiss_pdf_index").strip()
    if os.path.exists(os.path.join(base, "index.faiss")) or os.path.exists(os.path.join(base, "index.pkl")): return base
    sub = os.path.join(base, username)
    if os.path.exists(os.path.join(sub, "index.faiss")) or os.path.exists(os.path.join(sub, "index.pkl")): return sub
    os.makedirs(sub, exist_ok=True); return sub

def get_index_version(index_dir: str) -> int:
    files = [os.path.join(index_dir, "index.faiss"), os.path.join(index_dir, "index.pkl"), os.path.join(index_dir, "index_meta.json")]
    mtimes = [os.path.getmtime(f) for f in files if os.path.exists(f)]
    return int(max(mtimes)) if mtimes else 0

def _infer_mode_from_index_dir(index_dir: Optional[str]) -> str:
    if not index_dir: return "default"
    p = index_dir.lower()
    if "textbook" in p or "sgk" in p: return "textbook"
    if "thesis" in p or "luanvan" in p: return "thesis"
    if "contract" in p or "hop_dong" in p: return "contract"
    if "slide" in p or "ppt" in p: return "slides"
    if "academic" in p: return "academic_article"
    return "default"

def _map_doc_type_to_mode(doc_type: Optional[str], index_dir: Optional[str]) -> str:
    if doc_type and doc_type != "None":
        t = doc_type.strip().lower()
        if t in ["textbook", "sgk"]: return "textbook"
        if t in ["thesis", "luanvan"]: return "thesis"
        if t in ["contract", "hop_dong"]: return "contract"
        if t in ["slides", "ppt"]: return "slides"
        if t in ["academic", "baibao"]: return "academic_article"
        if t in ["qa", "qa_detailed"]: return "qa_detailed"
        if t == "summary": return "summary"
        if t in ["analysis", "report"]: return "analysis"
        if t in ["technical", "spec"]: return "technical"
    return _infer_mode_from_index_dir(index_dir)

@lru_cache(maxsize=200)
def get_chatbot_cached(username: str, google_api_key: Optional[str], llm_model: Optional[str], index_dir: str, index_version: int, doc_type: Optional[str] = None, user_instruction: Optional[str] = None):
    mode = _map_doc_type_to_mode(doc_type, index_dir)
    return PDFChatbot(google_api_key=google_api_key, mode=mode, llm_model=llm_model or "gemini-2.0-flash", index_dir=index_dir, streaming=False, user_instruction=user_instruction)

async def call_website_chat_api(req: "MessageFullRequest", target_domain: Optional[str] = None, user_instruction: str = "") -> str:
    dom = _clean_domain_url(target_domain if target_domain else req.domain)
    if not dom: return "Chưa xác định website."
    q = f"{req.message}\n\n(Lưu ý: {user_instruction})" if user_instruction else req.message
    try:
        # SỬ DỤNG GLOBAL CLIENT Ở ĐÂY
        resp = await http_client.post(
            f"{WEBSITE_API_URL.rstrip('/')}/chat", 
            json={"question": q, "domain": dom, "llm_model": req.llm_model, "google_api_key": req.google_api_key, "top_k": 3}
        )
        if resp.status_code == 200: return resp.json().get("reply", "No reply")
        return f"Error {resp.status_code}: {resp.text}"
    except Exception as e: return f"Web Error: {e}"

# [UPDATED] Hỗ trợ History cho hàm Combine
def combine_answers_with_genai(api_key: str, model: str, question: str, ans_docs: str, ans_web: str, user_instruction: str = "", history: list = None) -> str:
    if not ans_docs and not ans_web: return "Không tìm thấy nội dung."
    if not ans_docs or "Không tìm thấy" in ans_docs: 
        if not ans_web or "Không tìm thấy" in ans_web: return "Không tìm thấy nội dung."
        pass
    try:
        combined_context = f"Dựa trên các nguồn sau:\n\nNguồn PDF:\n{ans_docs}\n\nNguồn Web:\n{ans_web}\n\n{user_instruction}"
        client = genai.Client(api_key=api_key)
        mod_name = (model or "gemini-2.0-flash").replace("models/", "")
        sys_inst = f"Tổng hợp câu trả lời ngắn gọn, chính xác. {combined_context}"
        chat = client.chats.create(model=mod_name, history=history or [], config=genai.types.GenerateContentConfig(system_instruction=sys_inst))
        resp = chat.send_message(question)
        return resp.text
    except Exception as e:
        print(f"GenAI combine error: {e}")
        return ans_docs + "\n\n" + ans_web

# ============================================================================
# MESSAGING ROUTES
# ============================================================================

@app.post("/threads")
def create_thread(req: ThreadRequest, c_email: Optional[str] = Depends(get_optional_user_email)):
    tid = int(time.time())
    conn, cur = get_user_db(req.username)
    em = c_email if c_email and not is_api_bypass(c_email) else req.email
    if not em and is_api_bypass(c_email): em = req.email
    if not em: conn.close(); raise HTTPException(400, "Missing email")
    try:
        cur.execute("INSERT INTO threads (id, title, name, email, phone) VALUES (?, ?, ?, ?, ?)", (tid, req.title or "", req.name, em, req.phone))
        conn.commit()
    except Exception as e: conn.close(); raise HTTPException(500, str(e))
    conn.close()
    return tid

@app.get("/threads/{username}")
def get_threads_list(username: str, c_email: str = Depends(get_current_user_email)):
    conn, cur = get_user_db(username)
    # Nếu truy cập qua API bypass hoặc ứng dụng type.vn, cho phép lấy tất cả thread của username
    if is_api_bypass(c_email): 
        cur.execute("SELECT * FROM threads ORDER BY id DESC")
    else: 
        cur.execute("SELECT * FROM threads WHERE email = ? OR email IS NULL OR email = '' OR email = ? ORDER BY id DESC", (c_email, f"{username}@type.vn"))
    res = cur.fetchall(); conn.close()
    return res

@app.put("/threads/{username}/{thread_id}/title")
def update_title(username: str, thread_id: int, p: ThreadTitleUpdate, c_email: str = Depends(get_current_user_email)):
    conn, cur = get_user_db(username)
    if is_api_bypass(c_email): cur.execute("UPDATE threads SET title = ? WHERE id = ?", (p.title, thread_id))
    else: cur.execute("UPDATE threads SET title = ? WHERE id = ? AND email = ?", (p.title, thread_id, c_email))
    conn.commit()
    if cur.rowcount == 0: conn.close(); raise HTTPException(403, "Fail")
    conn.close()
    return {"ok": True}

@app.get("/messages/{username}/{thread_id}")
def get_msg(username: str, thread_id: int, c_email: str = Depends(get_current_user_email)):
    conn, cur = get_user_db(username)
    cur.execute("SELECT email FROM threads WHERE id = ?", (thread_id,))
    row = cur.fetchone()
    if not row: conn.close(); raise HTTPException(404, "Thread missing")
    if not is_api_bypass(c_email) and (row[0] or "").lower() != c_email.lower(): conn.close(); raise HTTPException(403, "No access")
    cur.execute("SELECT * FROM messages WHERE thread_id = ? ORDER BY id ASC", (thread_id,))
    res = cur.fetchall(); conn.close()
    return res

@app.post("/sync-messages")
async def sync_messages(req: RecordSyncMessageRequest, c_email: Optional[str] = Depends(get_optional_user_email)):
    db_path = os.path.join(USER_DBS_DIR, f"chatbot_user_{req.username}.db")
    if not os.path.exists(db_path):
        os.makedirs(USER_DBS_DIR, exist_ok=True)
        sync_conn = sqlite3.connect(db_path)
        init_user_tables(sync_conn)
        sync_conn.close()

    time_now = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    async with aiosqlite.connect(db_path) as conn:
        async with conn.cursor() as cur:
            # Kiểm tra xem thread đã tồn tại chưa, nếu chưa có thì tự động tạo
            await cur.execute("SELECT id FROM threads WHERE id = ?", (req.thread_id,))
            thread_row = await cur.fetchone()
            if not thread_row:
                thread_title = (req.user_message or "Cuộc trò chuyện").strip()[:60]
                em = c_email if (c_email and not is_api_bypass(c_email)) else f"{req.username}@type.vn"
                await cur.execute(
                    "INSERT INTO threads (id, title, name, email, phone) VALUES (?, ?, ?, ?, ?)",
                    (req.thread_id, thread_title, req.username, em, None)
                )

            # Lưu câu hỏi của người dùng
            if req.user_message:
                await cur.execute("""
                    INSERT INTO messages (thread_id, role, content, created, ip_address, sender_info) 
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (req.thread_id, "user", req.user_message, time_now, req.ip_address, req.sender_info))

            # Lưu câu trả lời của trợ lý AI
            if req.bot_message:
                src_json = json.dumps(req.sources or [], ensure_ascii=False)
                await cur.execute("""
                    INSERT INTO messages (thread_id, role, content, sources, created) 
                    VALUES (?, ?, ?, ?, ?)
                """, (req.thread_id, "assistant", req.bot_message, src_json, time_now))

            # Cập nhật tiêu đề thread theo câu hỏi gần nhất nếu tiêu đề đang là mặc định
            if req.user_message:
                thread_title = req.user_message.strip()[:60]
                await cur.execute("UPDATE threads SET title = ? WHERE id = ? AND (title IS NULL OR title = '' OR title = 'Hội thoại mới' OR title = 'admin')", (thread_title, req.thread_id))

            await conn.commit()

    return {"success": True, "thread_id": req.thread_id, "message": "Đã đồng bộ tin nhắn lên server"}

@app.post("/query-faiss-context")
async def query_faiss_context(req: ContextQueryRequest):
    """Trích xuất ngữ cảnh trực tiếp từ bản chỉ mục FAISS trên server bot.type.vn phục vụ iPad, Web, Mobile"""
    if not HAS_INDEXING_UTILS:
        return {"success": False, "context": "", "chunks_count": 0, "error": "Chưa có indexing_utils trên server"}

    try:
        candidate_doc_types = req.doc_types if req.doc_types else [None, "qa_detailed", "qa", "summary", "analysis"]
        all_chunks = []
        sources = []

        for dt in candidate_doc_types:
            try:
                res = indexing_utils.query_index_smart(
                    username=req.username,
                    question=req.query,
                    top_k=req.max_chunks or 4,
                    probe_k=30,
                    doc_type=dt
                )
                docs = res.get("docs", [])
                for d in docs:
                    txt = getattr(d, 'page_content', '')
                    if txt and txt not in all_chunks:
                        all_chunks.append(txt)
                        src = d.metadata.get("source") or d.metadata.get("file_path") or d.metadata.get("file_name")
                        if src and src not in sources:
                            sources.append(str(src))
                if len(all_chunks) >= (req.max_chunks or 4):
                    break
            except Exception as dt_err:
                continue

        joined_context = "\n\n---\n\n".join(all_chunks[:(req.max_chunks or 4)])
        return {
            "success": True,
            "context": joined_context,
            "chunks_count": len(all_chunks[:(req.max_chunks or 4)]),
            "sources": sources
        }
    except Exception as e:
        return {"success": False, "context": "", "chunks_count": 0, "error": str(e)}

@app.post("/messages")
async def post_msg(req: MessageFullRequest, c_email: str = Depends(get_current_user_email)):
    
    # Hàm Generator để đẩy từng đoạn chữ (chunk) về Frontend
    async def stream_generator():
        total_start = time.perf_counter()
        print("\n" + "="*60)
        print(f"🚀 [PROFILER/STREAMING] Nhận tin nhắn từ: {req.username} | Thread: {req.thread_id}")
        print(f"📝 Câu hỏi: {req.message}")
        
        db_path = os.path.join(USER_DBS_DIR, f"chatbot_user_{req.username}.db")
        final_src = []
        
        try:
            # ==========================================
            # 1. LƯU DB USER VÀ TẢI LỊCH SỬ
            # ==========================================
            step_start = time.perf_counter()
            async with aiosqlite.connect(db_path) as conn:
                async with conn.cursor() as cur:
                    await cur.execute("SELECT email FROM threads WHERE id = ?", (req.thread_id,))
                    row = await cur.fetchone()
                    
                    # Trả về lỗi qua chuẩn SSE nếu không hợp lệ
                    if not row:
                        yield f"data: {json.dumps({'error': 'Thread missing'}, ensure_ascii=False)}\n\n"
                        return
                    if not is_api_bypass(c_email) and (row[0] or "").lower() != c_email.lower(): 
                        yield f"data: {json.dumps({'error': 'No access permission'}, ensure_ascii=False)}\n\n"
                        return
                    
                    # Lưu câu hỏi
                    await cur.execute("""
                        INSERT INTO messages (thread_id, role, content, created, ip_address, sender_info) 
                        VALUES (?, ?, ?, ?, ?, ?)
                    """, (req.thread_id, "user", req.message, datetime.now().strftime("%d/%m/%Y %H:%M:%S"), req.ip_address, req.sender_info))
                    await conn.commit()

                    # Load lịch sử
                    await cur.execute("SELECT role, content FROM messages WHERE thread_id = ? ORDER BY id DESC LIMIT 20", (req.thread_id,))
                    rows = await cur.fetchall()
            
            rows.reverse()
            chat_history = []
            for r in (rows[:-1] if rows else []):
                role = "model" if r[0] == "assistant" else "user"
                chat_history.append(types.Content(role=role, parts=[types.Part(text=r[1])]))
                
            db_user_time = time.perf_counter() - step_start
            print(f"   ⏱️ [1. LƯU & TẢI LỊCH SỬ] : {db_user_time:.3f} giây")

            # ==========================================
            # 2. TÌM KIẾM NGỮ CẢNH (FAISS / WEB)
            # ==========================================
            step_start = time.perf_counter()
            cfg = get_chatbot_settings_internal(req.username)
            current_mode = cfg.get("mode") or "default"
            src_mode = (cfg.get("data_source") or req.simple_chatbot_data_source or "documents").lower()
            dts = cfg.get("doc_types") or []
            doms = cfg.get("domains") or []
            prompt_instr = cfg.get("custom_prompt") or ""
            if not dts and req.doc_type: dts = [req.doc_type]

            async def get_raw_docs_context():
                from pdf_chatbot_gemini import _faiss_files_exist 
                use_dts = dts if dts else [""]
                active_tasks = []
                for dt in use_dts:
                    idir = f"faiss_pdf_index/{dt}" if dt else req.index_dir
                    rdir = resolve_index_dir(idir, req.username)
                    if _faiss_files_exist(rdir):
                        active_tasks.append(search_single_dt_shared(req, dt, prompt_instr))
                if not active_tasks:
                    return "Không tìm thấy tài liệu liên quan trong các thư mục đã chọn.", []
                results = await asyncio.gather(*active_tasks)
                all_txt = [r[0] for r in results if r[0]]
                all_src = []
                for r in results: all_src.extend(r[1])
                return "\n\n".join(all_txt), list(set(all_src))

            async def get_raw_web_context():
                use_doms = [req.domain] if req.domain else doms
                if not use_doms: return "", []
                tasks = [call_website_chat_api(req, d, prompt_instr) for d in use_doms]
                res = await asyncio.gather(*tasks, return_exceptions=True)
                valid_texts = [r for r in res if isinstance(r, str) and "Error" not in r]
                sources = [f"web::{d}" for d in use_doms]
                return "\n\n".join(valid_texts), sources

            doc_context, web_context = "", ""
            if src_mode == "documents":
                doc_context, final_src = await get_raw_docs_context()
            elif src_mode == "website":
                web_context, final_src = await get_raw_web_context()
            else:
                (doc_context, d_src), (web_context, w_src) = await asyncio.gather(
                    get_raw_docs_context(), get_raw_web_context()
                )
                final_src = d_src + w_src

            search_time = time.perf_counter() - step_start
            print(f"   ⏱️ [2. TÌM KIẾM DATA ({src_mode})] : {search_time:.3f} giây")

            # ==========================================
            # 3. GỌI GEMINI STREAMING (CÓ HIỆU ỨNG TYPEWRITER)
            # ==========================================
            step_start = time.perf_counter()
            client = genai.Client(api_key=req.google_api_key)
            model_id = req.llm_model.replace("models/", "")
            
            context_str = f"NGỮ CẢNH TÀI LIỆU:\n{doc_context}\n\nNGỮ CẢNH WEBSITE:\n{web_context}"[:120000]
            
            from pdf_chatbot_gemini import PDFChatbot
            bot_tool = PDFChatbot(google_api_key=req.google_api_key)
            base_persona = bot_tool.get_persona_by_mode(current_mode)
            full_system_instruction = f"{base_persona}\n\nLưu ý bổ sung: {prompt_instr}"

            chat = client.chats.create(
                model=model_id,
                config=types.GenerateContentConfig(
                    system_instruction=full_system_instruction, 
                    temperature=0.3
                ),
                history=chat_history
            )
            
            prompt_with_context = f"Dựa trên các dữ liệu sau để trả lời người dùng:\n{context_str}\n\nCâu hỏi: {req.message}"
            
            # Bắt đầu gọi API
            response_stream = chat.send_message_stream(prompt_with_context)
            final_ans = ""
            
            for chunk in response_stream:
                if chunk.text:
                    final_ans += chunk.text
                    
                    # --- THỦ THUẬT TYPEWRITER TRẢ VỀ FRONTEND ---
                    # Băm cục text khổng lồ thành từng mẩu 3 ký tự
                    chunk_text = chunk.text
                    step = 3 
                    for i in range(0, len(chunk_text), step):
                        small_piece = chunk_text[i:i+step]
                        
                        # Đẩy mảnh nhỏ về Frontend
                        yield f"data: {json.dumps({'chunk': small_piece}, ensure_ascii=False)}\n\n"
                        
                        # Nghỉ nhịp siêu ngắn để ép FastAPI nhả buffer
                        await asyncio.sleep(0.015)
                        
            llm_time = time.perf_counter() - step_start
            print(f"   ⏱️ [3. GỌI GEMINI STREAM] : {llm_time:.3f} giây")

            # ==========================================
            # 4. LƯU KẾT QUẢ VÀO DB BOTS
            # ==========================================
            step_start = time.perf_counter()
            async with aiosqlite.connect(db_path) as conn:
                async with conn.cursor() as cur:
                    await cur.execute("""
                        INSERT INTO messages (thread_id, role, content, sources, created) 
                        VALUES (?, ?, ?, ?, ?)
                    """, (req.thread_id, "assistant", final_ans, json.dumps(final_src, ensure_ascii=False), datetime.now().strftime("%d/%m/%Y %H:%M:%S")))
                    await conn.commit()
            db_bot_time = time.perf_counter() - step_start
            total_time = time.perf_counter() - total_start
            
            print(f"🏁 [TỔNG THỜI GIAN]         : {total_time:.3f} giây\n")

            # ==========================================
            # 5. ĐÁNH DẤU HOÀN TẤT & TRẢ VỀ METADATA
            # ==========================================
            profiler = {
                "db_user": round(db_user_time, 3), "search": round(search_time, 3),
                "llm": round(llm_time, 3), "db_bot": round(db_bot_time, 3), "total": round(total_time, 3)
            }
            yield f"data: {json.dumps({'done': True, 'sources': final_src, 'profiler_seconds': profiler}, ensure_ascii=False)}\n\n"

        except Exception as e:
            logging.error(f"Streaming Error: {str(e)}", exc_info=True)
            yield f"data: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"

    # Trả về đối tượng StreamingResponse kèm các Headers cấm Cache/Buffer tuyệt đối
    return StreamingResponse(
        stream_generator(), 
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no" # Vô hiệu hóa tính năng gom cục của Nginx/Proxy
        }
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("chatbot:app", host="0.0.0.0", port=int(getenv_str("PORT", "8002")), reload=True)