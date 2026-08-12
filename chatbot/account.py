# account.py
from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional, Dict, Any
from datetime import datetime, timedelta, timezone
from passlib.context import CryptContext
from pymongo import MongoClient, errors
from bson import ObjectId
import os
import jwt
import certifi  # <-- NEW: use certifi CA bundle for TLS on Windows

# ---- Google ID token verify ----
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

# ---------- CONFIG ----------
MONGO_URI = "mongodb+srv://bienso629:hdsRNZEEdqYSvdsf@cluster0.slyekmh.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
DB_NAME = "myapp"
USERS_COLLECTION = "users"

# IP whitelist
ALLOWED_IPS = {"103.74.118.85"}

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# JWT config
JWT_SECRET = os.getenv("JWT_SECRET", "CHANGE_ME_IN_PRODUCTION")
JWT_ALG = "HS256"
JWT_EXPIRES_MIN = int(os.getenv("JWT_EXPIRES_MIN", "10080"))  # 7 days

# Google OAuth config
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")  # recommended to set

# ---------- DB SETUP ----------
# Use certifi CA bundle to avoid Windows trust store hiccups with Atlas
client = MongoClient(
    MONGO_URI,
    serverSelectionTimeoutMS=5000,
    tls=True,
    tlsCAFile=certifi.where(),
)
db = client[DB_NAME]
users_col = db[USERS_COLLECTION]

def ensure_indexes():
    try:
        users_col.create_index("email", unique=True, sparse=True)
        users_col.create_index("phone", unique=True, sparse=True)
        users_col.create_index("oauth.sub", unique=True, sparse=True)
    except errors.PyMongoError as e:
        print("Warning: could not create indexes:", e)

ensure_indexes()

# ---------- APP ----------
app = FastAPI(title="Account API")

# ---------- UTIL ----------
def now_utc() -> datetime:
    return datetime.now(timezone.utc)

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def get_client_ip(request: Request) -> str:
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    client = request.client
    return client.host if client else "unknown"

async def ip_whitelist_dependency(request: Request):
    ip = get_client_ip(request)
    if ip not in ALLOWED_IPS:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=f"IP {ip} not allowed")
    return ip

def issue_jwt(user: Dict[str, Any]) -> str:
    uid = str(user["_id"])
    payload = {
        "sub": uid,
        "email": user.get("email"),
        "provider": user.get("provider", "local"),
        "scope": "user",
        "iat": int(now_utc().timestamp()),
        "exp": int((now_utc() + timedelta(minutes=JWT_EXPIRES_MIN)).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)

def verify_google_id_token(id_token_str: str) -> Dict[str, Any]:
    if not id_token_str:
        raise HTTPException(status_code=400, detail="Thiếu oauth_token (Google ID token)")
    request_adapter = google_requests.Request()
    try:
        if GOOGLE_CLIENT_ID:
            claims = google_id_token.verify_oauth2_token(
                id_token_str, request_adapter, GOOGLE_CLIENT_ID
            )
        else:
            claims = google_id_token.verify_oauth2_token(id_token_str, request_adapter)
            iss = claims.get("iss")
            if iss not in ("accounts.google.com", "https://accounts.google.com"):
                raise ValueError("Issuer không hợp lệ")
        return claims
    except ValueError as e:
        raise HTTPException(status_code=401, detail=f"Google ID token không hợp lệ: {e}")

# ---------- MODELS ----------
class RegisterBase(BaseModel):
    full_name: Optional[str] = Field(None, min_length=2, max_length=200)
    phone: Optional[str] = Field(None, min_length=6, max_length=30)
    email: Optional[EmailStr] = None
    password: Optional[str] = Field(None, min_length=6, max_length=200)

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v):
        return v.strip() if v else v

class RegisterRequest(RegisterBase):
    # Pydantic v2: use "pattern" instead of "regex"
    provider: Optional[str] = Field("local", pattern="^(local|gmail)$")
    oauth_token: Optional[str] = Field(None, description="Google ID token (JWT)")
    oauth_id: Optional[str] = Field(None, description="Google user id (sub) – optional")

    @field_validator("password")
    @classmethod
    def password_required_for_local(cls, v, info):
        provider = info.data.get("provider", "local")
        if provider == "local" and not v:
            raise ValueError("password is required for local registration")
        return v

class RegisterResponse(BaseModel):
    success: bool
    id: Optional[str] = None
    token: Optional[str] = None
    message: Optional[str] = None

# ---------- ROUTES ----------
@app.post("/register", response_model=RegisterResponse)
async def register_user(payload: RegisterRequest, client_ip: str = Depends(ip_whitelist_dependency)):
    provider = payload.provider or "local"

    if provider == "local":
        if not payload.full_name:
            raise HTTPException(status_code=400, detail="Thiếu full_name")
        doc = {
            "full_name": payload.full_name.strip(),
            "phone": payload.phone,
            "email": payload.email.lower() if payload.email else None,
            "provider": "local",
            "password_hash": hash_password(payload.password),
            "oauth": None,
            "created_at": now_utc(),
            "last_login": None,
        }

        if doc.get("email") and users_col.find_one({"email": doc["email"]}):
            return JSONResponse(status_code=400, content={"success": False, "message": "Email đã được sử dụng"})
        if doc.get("phone") and users_col.find_one({"phone": doc["phone"]}):
            return JSONResponse(status_code=400, content={"success": False, "message": "Số điện thoại đã được sử dụng"})

        try:
            result = users_col.insert_one(doc)
            user = users_col.find_one({"_id": result.inserted_id})
            token = issue_jwt(user)
            return {"success": True, "id": str(user["_id"]), "token": token, "message": "Đăng ký thành công"}
        except errors.DuplicateKeyError:
            return JSONResponse(status_code=400, content={"success": False, "message": "Email hoặc Số điện thoại đã tồn tại"})
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Lỗi server: {e}")

    # provider == gmail
    claims = verify_google_id_token(payload.oauth_token)
    sub = claims.get("sub")
    email = claims.get("email")
    email_verified = claims.get("email_verified", False)
    name = claims.get("name") or payload.full_name
    picture = claims.get("picture")

    if not sub:
        raise HTTPException(status_code=401, detail="Google ID token thiếu 'sub'")
    if not email or not email_verified:
        raise HTTPException(status_code=401, detail="Email Google chưa xác minh hoặc thiếu email")

    existing_by_sub = users_col.find_one({"oauth.provider": "gmail", "oauth.sub": sub})
    if existing_by_sub:
        token = issue_jwt(existing_by_sub)
        return {"success": True, "id": str(existing_by_sub["_id"]), "token": token, "message": "Đăng nhập thành công (gmail)"}

    existing_by_email = users_col.find_one({"email": email.lower()})
    if existing_by_email:
        if existing_by_email.get("provider") == "gmail":
            token = issue_jwt(existing_by_email)
            return {"success": True, "id": str(existing_by_email["_id"]), "token": token, "message": "Đăng nhập thành công (gmail)"}
        try:
            users_col.update_one(
                {"_id": existing_by_email["_id"]},
                {
                    "$set": {
                        "provider": "gmail",
                        "oauth": {
                            "provider": "gmail",
                            "sub": sub,
                            "picture": picture,
                            "last_idtoken_at": now_utc(),
                        },
                        "last_login": now_utc(),
                    }
                }
            )
            merged = users_col.find_one({"_id": existing_by_email["_id"]})
            token = issue_jwt(merged)
            return {"success": True, "id": str(merged["_id"]), "token": token, "message": "Liên kết Gmail & đăng nhập thành công"}
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Lỗi hợp nhất tài khoản: {e}")

    doc = {
        "full_name": (name or "").strip() or (payload.full_name or "").strip() or email.split("@")[0],
        "phone": payload.phone,
        "email": email.lower(),
        "provider": "gmail",
        "password_hash": None,
        "oauth": {
            "provider": "gmail",
            "sub": sub,
            "picture": picture,
            "last_idtoken_at": now_utc(),
        },
        "created_at": now_utc(),
        "last_login": None,
    }

    if doc.get("phone") and users_col.find_one({"phone": doc["phone"]}):
        return JSONResponse(status_code=400, content={"success": False, "message": "Số điện thoại đã được sử dụng"})

    try:
        result = users_col.insert_one(doc)
        user = users_col.find_one({"_id": result.inserted_id})
        token = issue_jwt(user)
        return {"success": True, "id": str(user["_id"]), "token": token, "message": "Đăng ký (gmail) thành công"}
    except errors.DuplicateKeyError:
        user = users_col.find_one({"email": email.lower()})
        if user:
            token = issue_jwt(user)
            return {"success": True, "id": str(user["_id"]), "token": token, "message": "Đăng nhập thành công (gmail)"}
        return JSONResponse(status_code=400, content={"success": False, "message": "Email/SĐT đã tồn tại"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi server: {e}")

@app.get("/health")
async def health(client_ip: str = Depends(ip_whitelist_dependency)):
    try:
        client.admin.command("ping")
        return {"ok": True, "db": True}
    except Exception as e:
        return JSONResponse(status_code=500, content={"ok": False, "db": False, "error": str(e)})

class LoginRequest(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    password: Optional[str] = None

@app.post("/login")
async def login(req: LoginRequest, client_ip: str = Depends(ip_whitelist_dependency)):
    if not req.email and not req.phone:
        raise HTTPException(status_code=400, detail="Cần email hoặc phone để đăng nhập")
    query = {"email": req.email.lower()} if req.email else {"phone": (req.phone or "").strip()}
    user = users_col.find_one(query)
    if not user:
        raise HTTPException(status_code=401, detail="Người dùng không tồn tại")
    if not user.get("password_hash"):
        return JSONResponse(status_code=400, content={"success": False, "message": "Tài khoản này đăng ký qua OAuth (gmail). Vui lòng đăng nhập bằng Google."})
    if not req.password or not verify_password(req.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Mật khẩu không đúng")
    try:
        users_col.update_one({"_id": user["_id"]}, {"$set": {"last_login": now_utc()}})
    except Exception:
        pass
    token = issue_jwt(user)
    return {"success": True, "id": str(user["_id"]), "token": token, "message": "Đăng nhập thành công"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("account:app", host="0.0.0.0", port=8001, reload=True)
