#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Crawler Core Logic (Better Text Cleaning)
1. get_urls_from_sitemaps: Tải sitemap (Requests + Gzip) -> Regex lấy link.
2. save_content_only: Lưu nội dung JSON xuống đĩa (Text đã được làm sạch kỹ).
3. build_index_for_domain: Tạo index FAISS.
"""

import json
import os
import re
import shutil
import hashlib
import gzip
import pickle
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed

# --- THƯ VIỆN BẮT BUỘC ---
try:
    import requests
    from requests.packages.urllib3.exceptions import InsecureRequestWarning
    # Tắt cảnh báo SSL
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
except ImportError:
    print("❌ Lỗi: Thiếu thư viện 'requests'. Hãy chạy: pip install requests")

try:
    from langchain_text_splitters import RecursiveCharacterTextSplitter
    HAS_LANGCHAIN = True
except ImportError:
    HAS_LANGCHAIN = False
    print("⚠️  Chưa cài 'langchain-text-splitters'.")

# ----------------------------
# Cấu hình
# ----------------------------

ROOT = Path(__file__).resolve().parent
DATA_ROOT = ROOT / "data"
EMBED_MODEL_NAME = "AITeamVN/Vietnamese_Embedding"
CHUNK_SIZE = 3000  
CHUNK_OVERLAP = 300

_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# ----------------------------
# Helpers
# ----------------------------

def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    tmp.replace(path)

def sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", errors="ignore")).hexdigest()

def ensure_domain_dir(domain: str) -> Path:
    d = DATA_ROOT / domain
    (d / "html").mkdir(parents=True, exist_ok=True)
    (d / "text").mkdir(parents=True, exist_ok=True)
    (d / "meta").mkdir(parents=True, exist_ok=True)
    return d

def clean_text_content(text: str) -> str:
    """
    Hàm làm sạch văn bản nâng cao:
    - Fix lỗi dính câu (VD: "hết.Câu mới" -> "hết. Câu mới")
    - Xử lý dòng trống và khoảng trắng thừa.
    """
    if not text: return ""

    # 1. Thay thế khoảng trắng không ngắt dòng (non-breaking space)
    text = text.replace('\xa0', ' ')

    # 2. Fix lỗi dính câu: Thêm khoảng trắng sau dấu câu nếu theo sau là chữ cái/số
    # Regex: Tìm [.!?] theo sau là ký tự chữ/số mà KHÔNG có khoảng trắng ở giữa
    # \1 là dấu câu tìm được, thêm ' ' vào sau nó.
    text = re.sub(r'([.!?])(?=[A-Z0-9\u00C0-\u1EF9])', r'\1 ', text)

    # 3. Tách dòng để xử lý từng dòng một
    lines = text.split('\n')
    
    cleaned_lines = []
    for line in lines:
        # Xóa khoảng trắng thừa đầu cuối mỗi dòng
        stripped = line.strip()
        # Chỉ giữ lại dòng có nội dung
        if stripped:
            cleaned_lines.append(stripped)
    
    # 4. Nối lại các dòng. 
    # Dùng '\n' để LangChain nhận biết đâu là ngắt dòng tự nhiên.
    # Nếu muốn tách đoạn rõ hơn có thể dùng '\n\n' nhưng '\n' là đủ chuẩn.
    return '\n'.join(cleaned_lines)

# ----------------------------
# 1. Sitemap Parsing (Requests + Regex)
# ----------------------------

def fetch_url_content(url: str, timeout: int = 30) -> Optional[bytes]:
    print(f"📥 Đang tải sitemap: {url}")
    try:
        headers = {
            "User-Agent": _UA,
            "Accept": "application/xml,text/xml,*/*",
            "Accept-Encoding": "gzip, deflate"
        }
        resp = requests.get(url, headers=headers, timeout=timeout, verify=False)
        
        if resp.status_code != 200:
            print(f"❌ HTTP {resp.status_code} tại {url}")
            return None
            
        return resp.content
    except Exception as e:
        print(f"❌ Lỗi kết nối {url}: {e}")
        return None

def extract_urls_from_xml(xml_content: bytes) -> Tuple[List[str], List[str]]:
    urls = []
    sitemaps = []
    
    try:
        xml_str = xml_content.decode("utf-8", errors="ignore")
    except:
        return [], []

    # Regex tìm thẻ <loc>...</loc>
    matches = re.findall(r"<loc>\s*(https?://[^<]+?)\s*</loc>", xml_str, re.IGNORECASE)
    
    for link in matches:
        link = link.strip()
        if link.endswith(".xml") or link.endswith(".xml.gz") or "sitemap" in link:
            sitemaps.append(link)
        else:
            if not any(link.endswith(ext) for ext in ['.jpg', '.png', '.jpeg', '.pdf', '.css', '.js', '.gif', '.webp']):
                urls.append(link)

    return list(set(urls)), list(set(sitemaps))

def get_urls_from_sitemaps(sitemap_urls: List[str]) -> List[str]:
    all_articles = set()
    visited_sitemaps = set()
    queue = set(sitemap_urls) # Dùng set để tránh trùng lặp ngay từ đầu

    print(f"🚀 Bắt đầu quét sitemaps (Chế độ Đa luồng)...")

    # Mở 10 luồng chạy song song (bạn có thể tăng lên 20 nếu mạng khỏe)
    with ThreadPoolExecutor(max_workers=10) as executor:
        while queue:
            # Lấy ra tất cả sitemap chưa quét trong hàng đợi
            current_batch = [url for url in queue if url not in visited_sitemaps]
            queue.clear() # Dọn hàng đợi cũ
            
            if not current_batch:
                break
                
            visited_sitemaps.update(current_batch)
            
            # Giao việc cho các luồng tải sitemap cùng lúc
            futures = {executor.submit(fetch_url_content, url): url for url in current_batch}
            
            for future in as_completed(futures):
                content = future.result()
                if content:
                    articles, children = extract_urls_from_xml(content)
                    if articles:
                        all_articles.update(articles)
                    if children:
                        # Bơm thêm sitemap con vào hàng đợi cho vòng lặp sau
                        queue.update([c for c in children if c not in visited_sitemaps])

    final_list = list(all_articles)
    print(f"✅ HOÀN TẤT. Tổng cộng: {len(final_list)} URL duy nhất.")
    return final_list

# ----------------------------
# 2. Storage Logic (Updated Clean Text)
# ----------------------------

def save_content_only(domain: str, url: str, data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Lưu JSON content xuống đĩa với text đã được làm sạch kỹ.
    """
    domain_dir = ensure_domain_dir(domain)
    
    title = data.get("title") or ""
    html_content = data.get("content") or ""     
    text_content = data.get("textContent") or "" 
    
    if not text_content: text_content = data.get("excerpt") or ""
    if not text_content: return {"ok": False, "error": "No text content"}

    h = sha1(url)
    
    # --- SỬ DỤNG HÀM CLEAN MỚI ---
    clean_text = clean_text_content(text_content)
    # -----------------------------
    
    (domain_dir / "text" / f"{h}.txt").write_text(clean_text, encoding="utf-8", errors="ignore")
    (domain_dir / "html" / f"{h}.html").write_text(html_content, encoding="utf-8", errors="ignore")
    
    meta = {
        "url": url,
        "title": title,
        "hash": h,
        "saved_at": datetime.now(timezone.utc).isoformat(),
        "text_path": f"text/{h}.txt",
        "html_path": f"html/{h}.html",
    }
    (domain_dir / "meta" / f"{h}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    
    return {"ok": True, "hash": h, "status": "saved"}

# ----------------------------
# 3. Indexing Logic (Batch)
# ----------------------------

def build_index_for_domain(domain: str) -> Dict[str, Any]:
    """Tạo Index FAISS từ toàn bộ file trong thư mục text."""
    domain_dir = DATA_ROOT / domain
    if not domain_dir.exists(): return {"ok": False, "error": "Domain dir not found"}

    text_dir = domain_dir / "text"
    meta_dir = domain_dir / "meta"
    
    text_files = sorted(text_dir.glob("*.txt"))
    valid_files = [f for f in text_files if f.stat().st_size > 0]
    
    if not valid_files: return {"ok": False, "error": "No files to index"}

    print(f"📦 Indexing {len(valid_files)} files for {domain}...")

    metadata = []
    content_hash = {}
    for txt in valid_files:
        h = txt.stem
        txt_str = txt.read_text(encoding="utf-8", errors="ignore")
        content_hash[h] = sha1(txt_str)
        
        url, title = "", ""
        meta_file = meta_dir / f"{h}.json"
        if meta_file.exists():
            try:
                m = json.loads(meta_file.read_text(encoding="utf-8"))
                url = m.get("url", "")
                title = m.get("title", "")
            except: pass
        metadata.append({"hash": h, "url": url, "title": title})

    index_path = domain_dir / "index.faiss"
    meta_path = domain_dir / "metadata.pkl"
    chunk_meta_path = domain_dir / "chunk_meta.pkl"
    
    with meta_path.open("wb") as f: pickle.dump(metadata, f)
    write_json(domain_dir / "content_hash.json", content_hash)

    # Chunking
    def smart_chunk(text: str) -> List[str]:
        if HAS_LANGCHAIN:
            # RecursiveCharacterTextSplitter sẽ ưu tiên cắt theo \n\n, sau đó đến \n, rồi đến dấu chấm
            splitter = RecursiveCharacterTextSplitter(
                chunk_size=CHUNK_SIZE, 
                chunk_overlap=CHUNK_OVERLAP, 
                separators=["\n\n", "\n", ".", " ", ""]
            )
            return splitter.split_text(text)
        else:
            pieces = []
            i = 0
            while i < len(text):
                pieces.append(text[i:i+2000])
                i += 1800
            return pieces

    corpus = []
    chunk_meta = []
    
    for item in metadata:
        h = item["hash"]
        tpath = text_dir / f"{h}.txt"
        t = tpath.read_text(encoding="utf-8", errors="ignore").strip()
        if len(t) < 50:
            corpus.append(f"passage: {t}")
            # Thêm "text": t
            chunk_meta.append({"hash": h, "chunk_id": 0, "url": item["url"], "title": item["title"], "text": t})
            continue
        
        for idx, piece in enumerate(smart_chunk(t)):
            corpus.append(f"passage: {piece}")
            # Thêm "text": piece
            chunk_meta.append({"hash": h, "chunk_id": idx, "url": item["url"], "title": item["title"], "text": piece})

    if not corpus: return {"ok": False, "error": "Empty corpus"}

    try:
        import faiss 
        from sentence_transformers import SentenceTransformer
        print("🧠 Creating Embeddings...")
        model = SentenceTransformer(EMBED_MODEL_NAME)
        embeddings = model.encode(corpus, batch_size=32, show_progress_bar=False, convert_to_numpy=True, normalize_embeddings=True)
        
        index = faiss.IndexFlatL2(embeddings.shape[1])
        index.add(embeddings)
        
        faiss.write_index(index, str(index_path))
        with chunk_meta_path.open("wb") as f: pickle.dump(chunk_meta, f)
        
        print(f"✅ Index Done: {len(corpus)} vectors.")
        return {"ok": True, "total_vectors": len(corpus)}
    except Exception as e:
        print(f"❌ Index Error: {e}")
        return {"ok": False, "error": str(e)}

def safe_force_delete_for_domain(domain: Optional[str]) -> None:
    if not domain: return
    domain_dir = DATA_ROOT / domain
    if domain_dir.exists(): shutil.rmtree(domain_dir, ignore_errors=True)