import sys
import os
import json
import pickle
from pathlib import Path
from typing import Dict, Any
from collections import OrderedDict

import faiss
from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
from google import genai
from google.genai import types

# =========================
# Cấu hình
# =========================
EMBED_MODEL_NAME = "AITeamVN/Vietnamese_Embedding"
CHUNK_SIZE = 3000
CHUNK_OVERLAP = 300
MAX_DOMAINS_IN_RAM = int(os.getenv("MAX_DOMAINS_IN_RAM", 5))

# E5/BGE-M3 encoder
encoder = SentenceTransformer(EMBED_MODEL_NAME)
app = FastAPI(title="Website RAG Service (Hot Reload)")

# --------- Models ---------
class ChatRequest(BaseModel):
    question: str
    domain: str
    llm_model: str
    google_api_key: str
    top_k: int = 3

class ReloadRequest(BaseModel):
    domain: str

# Global Store: domain -> {"index", "metadata", "chunk_meta", "dir"}
# Sử dụng OrderedDict để làm LRU Cache
domain_data = OrderedDict()

# =========================
# Core Logic: Load Index
# =========================

def load_single_domain(domain_name: str, data_dir: str = "data") -> bool:
    """
    Nạp (hoặc nạp lại) dữ liệu Index của 1 domain cụ thể từ ổ cứng vào RAM.
    Có cơ chế LRU Cache chống tràn RAM.
    """
    print(f"🔄 Đang nạp dữ liệu cho domain: {domain_name}...")
    root = Path(data_dir)
    domain_dir = root / domain_name

    if not domain_dir.exists() or not domain_dir.is_dir():
        print(f"⚠️ Không tìm thấy thư mục data cho: {domain_name}")
        return False

    try:
        index_path = domain_dir / "index.faiss"
        meta_path = domain_dir / "metadata.pkl"
        chunk_meta_path = domain_dir / "chunk_meta.pkl"

        if index_path.exists() and meta_path.exists() and chunk_meta_path.exists():
            # 1. Load FAISS Index
            index = faiss.read_index(str(index_path))
            
            # 2. Load Metadata
            with open(meta_path, "rb") as f:
                metadata = pickle.load(f)
            
            # 3. Load Chunk Map
            with open(chunk_meta_path, "rb") as f:
                chunk_meta = pickle.load(f)

            # 4. Cập nhật vào RAM (Cơ chế LRU Cache)
            if domain_name not in domain_data and len(domain_data) >= MAX_DOMAINS_IN_RAM:
                evicted_domain, _ = domain_data.popitem(last=False)
                print(f"🧹 LRU Cache: Đã giải phóng RAM của domain {evicted_domain}")

            domain_data[domain_name] = {
                "index": index,
                "metadata": metadata,
                "chunk_meta": chunk_meta,
                "dir": domain_dir,
            }
            # Kéo domain này xuống cuối (nghĩa là vừa được dùng gần nhất)
            domain_data.move_to_end(domain_name)

            print(f"✅ Đã nạp thành công {domain_name} ({index.ntotal} vectors)")
            return True
        else:
            print(f"⚠️ Dữ liệu index chưa đầy đủ cho {domain_name} (cần chạy trigger-index trước).")
            return False
    except Exception as e:
        print(f"❌ Lỗi khi nạp {domain_name}: {e}")
        return False

def load_all_domains(data_dir: str = "data", selected_domains=None):
    """Quét và nạp tất cả domain khi khởi động."""
    print("🔍 Scanning all domains in:", data_dir)
    root = Path(data_dir)
    if not root.exists(): return

    for domain_dir in root.iterdir():
        if not domain_dir.is_dir(): continue
        if selected_domains and domain_dir.name not in selected_domains: continue
        
        load_single_domain(domain_dir.name, data_dir)

# --- Khởi động ---
if len(sys.argv) > 1:
    try:
        selected = json.loads(sys.argv[1])
    except: selected = None
else:
    selected = None

# Đã comment để app khởi động tức thì, chỉ nạp vào RAM khi có request (Lazy Load)
# load_all_domains(selected_domains=selected)

# =========================
# API Endpoints
# =========================

@app.on_event("startup")
def _warmup():
    try:
        encoder.encode(["warmup"], normalize_embeddings=True)
        print("🔥 Model warmed up")
    except: pass

@app.get("/health")
def health():
    return {
        "ok": True, 
        "loaded_domains": list(domain_data.keys()),
        "stats": {d: int(i["index"].ntotal) for d, i in domain_data.items()}
    }

# --- API MỚI: Reload Index ---
@app.post("/reload-index")
def reload_index(req: ReloadRequest):
    """
    API để Chatbot gọi sang khi vừa crawl/index xong.
    Giúp cập nhật dữ liệu mới ngay lập tức mà không cần restart.
    """
    success = load_single_domain(req.domain)
    if success:
        return {"ok": True, "message": f"Domain {req.domain} reloaded successfully"}
    else:
        return JSONResponse(status_code=400, content={"ok": False, "error": "Reload failed (check server logs)"})

@app.get("/search")
def search(q: str = Query(...), domain: str = Query(...), top_k: int = 3):
    if domain not in domain_data:
        # Thử nạp lại lần nữa (phòng trường hợp mới tạo nhưng chưa reload)
        load_single_domain(domain)
        if domain not in domain_data:
            return JSONResponse(content={"error": "Domain not loaded"}, status_code=404)
    else:
        # Đánh dấu là vừa được sử dụng
        domain_data.move_to_end(domain)

    data = domain_data[domain]
    
    # Encode query (Bỏ prefix query: cho bge-m3)
    q_emb = encoder.encode([q], normalize_embeddings=True)[0].reshape(1, -1)
    
    # Search FAISS
    D, I = data["index"].search(q_emb, top_k)

    results = []
    for i in I[0]:
        if 0 <= i < len(data["chunk_meta"]):
            cm = data["chunk_meta"][i]
            # Đọc text gốc từ file để lấy snippet chính xác
            try:
                full_text = (data["dir"] / "text" / f"{cm['hash']}.txt").read_text(encoding="utf-8", errors="ignore")
                snippet = full_text[:500] + "..." 
            except:
                snippet = ""
                
            results.append({
                "url": cm.get("url"),
                "title": cm.get("title"),
                "snippet": snippet,
                "score": float(D[0][list(I[0]).index(i)])
            })
    return results

@app.post("/chat")
def chat(req: ChatRequest):
    if req.domain not in domain_data:
        load_single_domain(req.domain)
        if req.domain not in domain_data:
            return {"reply": f"Chưa có dữ liệu cho {req.domain}. Hãy crawl trước."}
    else:
        # Đánh dấu là vừa được sử dụng
        domain_data.move_to_end(req.domain)

    data = domain_data[req.domain]
    
    # 1. Search (Bỏ prefix query: cho bge-m3)
    q_emb = encoder.encode([req.question], normalize_embeddings=True)[0].reshape(1, -1)
    D, I = data["index"].search(q_emb, req.top_k)

    # 2. Get Context
    context_parts = []
    for idx in I[0]:
        if 0 <= idx < len(data["chunk_meta"]):
            cm = data["chunk_meta"][idx]
            try:
                # Lấy trực tiếp đoạn text của chunk đã lưu
                chunk_text = cm.get("text", "")
                
                # Fallback an toàn nếu bạn chưa kịp re-index dữ liệu cũ
                if not chunk_text: 
                    txt_path = data["dir"] / "text" / f"{cm['hash']}.txt"
                    full_text = txt_path.read_text(encoding="utf-8", errors="ignore")
                    chunk_text = full_text[:3000] 
                
                context_parts.append(f"Nguồn: {cm.get('url')}\nNội dung: {chunk_text}\n---")
            except: pass

    if not context_parts:
        return {"reply": "Không tìm thấy thông tin liên quan trong dữ liệu website."}

    final_context = "\n".join(context_parts)

    # 3. Generate with Gemini
    prompt = f"""Bạn là trợ lý AI. Dựa vào thông tin sau từ website {req.domain}, hãy trả lời câu hỏi.
Nếu thông tin không có trong ngữ cảnh, hãy nói không biết.

[NGỮ CẢNH WEBSITE]
{final_context}

[CÂU HỎI]
{req.question}

[TRẢ LỜI]
"""
    try:
        # Khởi tạo client mới (thay thế cho genai.configure)
        client = genai.Client(api_key=req.google_api_key)

        # Gọi model và tạo nội dung
        model_id = req.llm_model.replace("models/", "")
        resp = client.models.generate_content(
            model=model_id,
            contents=prompt
        )

        return {"reply": resp.text}
    except Exception as e:
        return {"reply": f"Không tìm thấy câu trả lời: {str(e)}\n\nNgữ cảnh tìm được:\n{final_context[:500]}..."}