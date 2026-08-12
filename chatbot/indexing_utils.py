# indexing_utils.py — Layout-aware PDF extraction + robust line-wrap normalization
# & Doc-aware retrieval to avoid cross-document mixups
# LangChain 0.3 compatible. Incremental FAISS per-username under:
#   INDEX_BASE_DIR[/doc_type]/<username>

import os
import re
import json
import hashlib
import unicodedata
from io import BytesIO
from typing import List, Dict, Optional, Tuple

# --- THÊM DÒNG NÀY ĐỂ CHỐNG DEADLOCK TRÊN WINDOWS ---
os.environ["TOKENIZERS_PARALLELISM"] = "false"

# ---------- Config ----------
PDF_BASE_DIR = os.getenv("PDF_DIR", "pdfs")
INDEX_BASE_DIR = os.getenv("INDEX_DIR", "faiss_pdf_index")
EMBED_MODEL_NAME = os.getenv("EMBED_MODEL", "AITeamVN/Vietnamese_Embedding")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "3000")) 
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "300"))

# Mặc định global (dự phòng), nhưng sẽ ưu tiên tham số từ hàm truyền vào
DEFAULT_ENABLE_OCR = os.getenv("ENABLE_OCR", "false").lower() == "true"
OCR_DPI = int(os.getenv("OCR_DPI", "200"))

# ---------- LangChain imports ----------
from langchain_community.vectorstores import FAISS
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter

# OCR (optional)
try:
    import pytesseract  # type: ignore
except Exception:
    pytesseract = None


# ---------- Helpers ----------

def _save_progress(index_dir: str, current: int, total: int, status: str):
    """Lưu tiến độ ra file progress.json để Frontend gọi API lấy về"""
    import os, json
    # THÊM DÒNG NÀY: Ép tạo thư mục nếu chưa có
    os.makedirs(index_dir, exist_ok=True) 
    
    prog_path = os.path.join(index_dir, "progress.json")
    try:
        percent = int((current / total) * 100) if total > 0 else 0
        with open(prog_path, "w", encoding="utf-8") as f:
            json.dump({"current": current, "total": total, "percent": percent, "status": status}, f, ensure_ascii=False)
    except: pass

def _clear_progress(index_dir: str):
    """Xóa file tiến độ khi đã chạy xong"""
    prog_path = os.path.join(index_dir, "progress.json")
    if os.path.exists(prog_path):
        try: os.remove(prog_path)
        except: pass

# Thêm một biến toàn cục ở ngay trên hàm
_GLOBAL_EMBEDDINGS = None

def _get_embeddings():
    global _GLOBAL_EMBEDDINGS
    # Nếu chưa nạp thì mới nạp, nạp rồi thì dùng luôn đồ cũ
    if _GLOBAL_EMBEDDINGS is None:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"   ⚙️ Đang nạp mô hình lên {device.upper()} (Chỉ nạp 1 lần duy nhất)...")
        
        from langchain_huggingface import HuggingFaceEmbeddings
        _GLOBAL_EMBEDDINGS = HuggingFaceEmbeddings(
            model_name=EMBED_MODEL_NAME,
            model_kwargs={'device': device},
            encode_kwargs={'batch_size': 32} # Chống tràn VRAM
        )
        print("   ✅ Nạp mô hình vào Card màn hình hoàn tất!")
        
    return _GLOBAL_EMBEDDINGS

def _ensure_dirs_for_type(username: str, doc_type: Optional[str] = None) -> Tuple[str, str]:
    """
    Ensure PDF & index folders exist for a given username and optional doc_type.
    """
    if doc_type:
        pdf_dir = os.path.abspath(os.path.join(PDF_BASE_DIR, doc_type, username))
        index_dir = os.path.abspath(os.path.join(INDEX_BASE_DIR, doc_type, username))
    else:
        pdf_dir = os.path.abspath(os.path.join(PDF_BASE_DIR, username))
        index_dir = os.path.abspath(os.path.join(INDEX_BASE_DIR, username))
    os.makedirs(pdf_dir, exist_ok=True)
    os.makedirs(index_dir, exist_ok=True)
    return pdf_dir, index_dir


def _ensure_dirs(username: str) -> Tuple[str, str]:
    return _ensure_dirs_for_type(username, None)


def _file_sha256(path: str, buf_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(buf_size)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def _load_meta(index_dir: str) -> Dict:
    fp = os.path.join(index_dir, "index_meta.json")
    if os.path.exists(fp):
        try:
            with open(fp, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _save_meta(index_dir: str, meta: Dict) -> None:
    fp = os.path.join(index_dir, "index_meta.json")
    with open(fp, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)


def _save_faiss(store: FAISS, index_dir: str, index_name: str = "index") -> None:
    os.makedirs(index_dir, exist_ok=True)
    store.save_local(index_dir, index_name=index_name)


def _load_faiss(index_dir: str, index_name: str = "index") -> Optional[FAISS]:
    faiss_file = os.path.join(index_dir, f"{index_name}.faiss")
    pkl_file = os.path.join(index_dir, f"{index_name}.pkl")
    if not (os.path.exists(faiss_file) and os.path.exists(pkl_file)):
        return None
    try:
        return FAISS.load_local(
            index_dir,
            embeddings=_get_embeddings(),
            index_name=index_name,
            allow_dangerous_deserialization=True,
        )
    except Exception:
        return None


def _strip_accents_lower(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s.lower()


def _is_lowerish_start(s: str) -> bool:
    if not s:
        return False
    c0 = s[0]
    return c0.islower() or c0.isdigit() or c0 in "-–—([“\"'"


def _normalize_wrapped_text(text: str) -> str:
    """
    - Unify CRLF -> LF
    - Heal hyphenated wraps: 'vi-\nệt' -> 'việt'
    - Convert soft line breaks to spaces when likely mid-sentence
    - Preserve real paragraph breaks (blank line) as \\n\\n
    """
    if not text:
        return ""
    s = text.replace("\r\n", "\n").replace("\r", "\n")

    # heal hyphens
    s = re.sub(r"(\w)-\n(\w)", r"\1\2", s)

    # paragraph splitting
    lines = s.split("\n")
    out_lines: List[str] = []
    buf = ""

    for line in lines:
        stripped = line.strip()
        if not stripped:
            if buf:
                out_lines.append(buf.strip())
                buf = ""
            continue

        if buf:
            if (
                not buf.endswith((".", "?", "!", "…", ":", ";"))
                and not stripped[0].isupper()
                and _is_lowerish_start(stripped)
            ):
                buf += " " + stripped
            else:
                out_lines.append(buf.strip())
                buf = stripped
        else:
            buf = stripped

    if buf:
        out_lines.append(buf.strip())

    s = "\n\n".join(out_lines)
    s = s.replace("<LINE_BREAK>", " ")
    s = re.sub(r"[ \t]{2,}", " ", s).strip()
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s


def _split_docs(raw_docs: List[Document]) -> List[Document]:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        separators=["\n\n", ". ", "? ", "! ", "\n", "; ", ": ", " "],
    )
    return splitter.split_documents(raw_docs)


# ---------- Extractors ----------

# [FIX] Robust version to prevent "list index out of range"
def _extract_pdf_with_pymupdf_blocks(path: str, file_label: str) -> List[Document]:
    try:
        import fitz  # PyMuPDF
    except Exception:
        return []
    docs: List[Document] = []
    abspath = os.path.abspath(path)
    
    try:
        doc = fitz.open(path)
    except Exception:
        return []

    try:
        for pno in range(doc.page_count):
            try:
                page = doc.load_page(pno)
                blocks = page.get_text("blocks") or []
                
                # --- FIX QUAN TRỌNG: Filter valid blocks trước khi sort ---
                # Chỉ lấy block có ít nhất 5 phần tử (x0, y0, x1, y1, text)
                valid_blocks = [b for b in blocks if isinstance(b, (list, tuple)) and len(b) >= 5]
                
                # Sau khi filter mới sort
                valid_blocks.sort(key=lambda b: (round(b[1]), round(b[0])))
                
                for b in valid_blocks:
                    txt = b[4] # Safe access
                    para = _normalize_wrapped_text(txt)
                    if para:
                        docs.append(
                            Document(
                                page_content=para,
                                metadata={
                                    "source": file_label,
                                    "file_path": abspath,
                                    "file_name": os.path.basename(path),
                                    "page": pno + 1,
                                },
                            )
                        )
            except Exception as e:
                # Log lỗi trang nhưng không dừng cả process
                print(f"[Warn] Page {pno} error in {file_label}: {e}")
                continue
    finally:
        if 'doc' in locals():
            doc.close()
    return _split_docs(docs)


def _extract_pdf_with_pypdf(path: str, file_label: str) -> List[Document]:
    try:
        from PyPDF2 import PdfReader  # type: ignore
    except Exception:
        return []

    reader = PdfReader(path)
    docs: List[Document] = []
    abspath = os.path.abspath(path)
    for i, page in enumerate(reader.pages):
        try:
            txt = page.extract_text() or ""
        except Exception:
            txt = ""
        para = _normalize_wrapped_text(txt)
        if not para:
            continue
        docs.append(
            Document(
                page_content=para,
                metadata={
                    "source": file_label,
                    "file_path": abspath,
                    "file_name": os.path.basename(path),
                    "page": i + 1,
                },
            )
        )
    return _split_docs(docs)


def _ocr_pdf_with_pymupdf(path: str, file_label: str) -> List[Document]:
    if pytesseract is None:
        return []
    try:
        import fitz
        from PIL import Image
    except Exception:
        return []
    docs: List[Document] = []
    abspath = os.path.abspath(path)
    doc = fitz.open(path)
    try:
        zoom = OCR_DPI / 72.0
        mat = fitz.Matrix(zoom, zoom)
        for pno in range(doc.page_count):
            try:
                page = doc.load_page(pno)
                pix = page.get_pixmap(matrix=mat, alpha=False)
                img_bytes = pix.tobytes("png")
                pil = Image.open(BytesIO(img_bytes))
                try:
                    text = pytesseract.image_to_string(pil, lang="vie+eng")
                except Exception:
                    text = pytesseract.image_to_string(pil)
                para = _normalize_wrapped_text(text or "")
                if para:
                    docs.append(
                        Document(
                            page_content=para,
                            metadata={
                                "source": file_label,
                                "file_path": abspath,
                                "file_name": os.path.basename(path),
                                "page": pno + 1,
                            },
                        )
                    )
            except Exception: 
                continue
    finally:
        doc.close()
    return _split_docs(docs)


# [UPDATE] Nhận tham số enable_ocr
# Sửa lại hàm này trong indexing_utils.py
def extract_single_pdf(path: str, enable_ocr: bool = False) -> List[Document]:
    """
    Dùng PyPDFLoader (Thuần Python, cam kết 100% không dính lỗi DLL)
    """
    print(f"\n📄 Đang đọc file: {os.path.basename(path)}")
    label = os.path.basename(path)
    abspath = os.path.abspath(path)
    docs: List[Document] = []
    
    try:
        # Đổi sang PyPDFLoader thay vì PyMuPDFLoader
        from langchain_community.document_loaders import PyPDFLoader
        loader = PyPDFLoader(path)
        pages = loader.load()
        
        for d in pages:
            cleaned = _normalize_wrapped_text(d.page_content)
            if cleaned:
                d.page_content = cleaned
                d.metadata["file_name"] = label
                d.metadata["file_path"] = abspath
                d.metadata["source"] = label
                docs.append(d)
                
        if docs:
            print(f"   ✅ Lấy thành công chữ từ {len(docs)} trang.")
            return _split_docs(docs)
        else:
            print("   ⚠️ File PDF không chứa chữ (Có thể là file scan/ảnh).")
    except Exception as e:
        print(f"   ❌ Lỗi thư viện khi đọc PDF: {e}")
        
    # Fallback sang OCR nếu file scan
    if enable_ocr or DEFAULT_ENABLE_OCR:
        print("   🔍 Đang thử dùng AI OCR để nhận diện chữ từ ảnh...")
        docs_ocr = _ocr_pdf_with_pymupdf(path, label)
        if docs_ocr:
            print(f"   ✅ OCR đọc thành công {len(docs_ocr)} trang.")
            return docs_ocr
        
    print(f"❌ THẤT BẠI: Không lấy được chữ từ file {label}.")
    return []

def extract_mineru_json(path: str) -> List[Document]:
    """Đọc file .mineru.json và chunk theo Title thông minh"""
    print(f"\n🧠 Đang xử lý cục dữ liệu thông minh từ MinerU: {os.path.basename(path)}")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data_string = f.read()
            # Có thể MinerU trả về JSON array hoặc string chứa dict string. Xử lý an toàn:
            try:
                mineru_data = json.loads(data_string)
            except:
                # Nếu chuỗi trả về không phải JSON array nguyên chuẩn (do ast.literal_eval hoặc gì đó), thử dùng ast
                import ast
                mineru_data = ast.literal_eval(data_string)
                
        if not isinstance(mineru_data, list):
            print("⚠️ Dữ liệu MinerU không phải là một danh sách (List). Bỏ qua.")
            return []
            
        label = os.path.basename(path).replace(".mineru.json", ".pdf")
        abspath = os.path.abspath(path)
        docs: List[Document] = []
        current_title = ""
        current_chunk = ""
        
        for item in mineru_data:
            # Hỗ trợ mảng string đơn giản (kết quả từ OpenAI / Mì tôm AI)
            if isinstance(item, str):
                if item.strip():
                    docs.append(Document(
                        page_content=item.strip(),
                        metadata={"source": label, "file_name": label, "file_path": abspath}
                    ))
                continue

            if not isinstance(item, dict): continue
            t = item.get("type")
            content = item.get("content")
            if not content: continue
            
            if t == "title":
                if current_chunk.strip():
                    docs.append(Document(
                        page_content=f"[{current_title}]\n{current_chunk.strip()}" if current_title else current_chunk.strip(),
                        metadata={"source": label, "file_name": label, "file_path": abspath}
                    ))
                    current_chunk = ""
                current_title = content
            elif t in ["text", "list", "equation"]:
                current_chunk += f"{content}\n"
                
        if current_chunk.strip():
            docs.append(Document(
                page_content=f"[{current_title}]\n{current_chunk.strip()}" if current_title else current_chunk.strip(),
                metadata={"source": label, "file_name": label, "file_path": abspath}
            ))
            
        print(f"   ✅ MinerU đã băm thành công {len(docs)} khối dữ liệu siêu chuẩn (Context-Aware).")
        # Vẫn chẻ nhỏ lại bằng RecursiveCharacterTextSplitter đề phòng khối nào quá lớn vượt 3000 kí tự
        return _split_docs(docs)
    except Exception as e:
        print(f"   ❌ LỖI KHI XỬ LÝ MINERU JSON: {e}")
        return []

# [UPDATE] Nhận tham số enable_ocr và truyền xuống extract_single_pdf
def index_documents(username: str, doc_type: Optional[str] = None, enable_ocr: bool = False) -> Dict:
    """
    Build or update FAISS index cho user (và optional doc_type).
    """
    pdf_dir, index_dir = _ensure_dirs_for_type(username, doc_type)
    
    # collect PDFs and JSONs
    pdf_paths = []
    if os.path.isdir(pdf_dir):
        for root, _, files in os.walk(pdf_dir):
            for f in files:
                if f.lower().endswith(".pdf") or f.lower().endswith(".mineru.json"):
                    pdf_paths.append(os.path.join(root, f))
    pdf_paths = [p for p in pdf_paths if os.path.isfile(p)]

    # compute hashes
    meta = _load_meta(index_dir)
    meta.setdefault("files", {})
    prev_map: Dict[str, str] = meta["files"]
    cur_map: Dict[str, str] = {}

    for p in pdf_paths:
        try:
            cur_map[p] = _file_sha256(p)
        except Exception:
            continue

    removed = [p for p in prev_map.keys() if p not in cur_map]
    added_or_changed = [p for p, h in cur_map.items() if prev_map.get(p) != h]

    embeddings = _get_embeddings()
    store = _load_faiss(index_dir)
    need_full_rebuild = (store is None) or bool(removed)
    
    # Nếu trong meta có đánh dấu FORCE_REINDEX (từ chatbot.py) thì coi như file đó đã thay đổi
    # Logic này tự động được xử lý vì hash trong meta bị lệch so với hash thực tế

    summary = {
        "username": username,
        "pdf_dir": pdf_dir,
        "index_dir": index_dir,
        "total_files": len(pdf_paths),
        "added_or_changed": added_or_changed,
        "removed": removed,
        "chunks_added": 0,
        "rebuild": (store is None), # Không còn full rebuild khi xóa file nữa
    }

    if summary["rebuild"]:
        # Báo cáo ngay lập tức để Frontend không bị "lừa"
        _save_progress(index_dir, 0, len(pdf_paths), "Đang khởi tạo quá trình đọc file...")
        
        store = None
        total_chunks = 0
        embeddings = _get_embeddings()
        files_map = meta.setdefault("files", {})
        
        for idx, p in enumerate(pdf_paths):
            _save_progress(index_dir, idx, len(pdf_paths), f"Đang xử lý: {os.path.basename(p)}")
            
            new_docs: List[Document] = []
            if p.lower().endswith(".mineru.json"):
                new_docs = extract_mineru_json(p)
            else:
                # Nếu có file .mineru.json tương ứng thì bỏ qua file PDF gốc để tránh trùng lặp nội dung
                json_counterpart = p[:-4] + ".mineru.json"
                if os.path.exists(json_counterpart):
                    print(f"   ⏩ Bỏ qua {os.path.basename(p)} vì đã có kết quả MinerU xịn hơn.")
                    continue
                new_docs = extract_single_pdf(p, enable_ocr=enable_ocr)
                
            if new_docs:
                total_chunks += len(new_docs)
                try:
                    if store is None:
                        store = FAISS.from_documents(new_docs, embeddings)
                    else:
                        store.add_documents(new_docs)
                except Exception as e:
                    print(f"   ❌ LỖI NGHIÊM TRỌNG KHI TẠO FAISS: {e}")
                    _save_progress(index_dir, 0, len(pdf_paths), f"Lỗi: {e}")
                    _clear_progress(index_dir)
                    return summary
            
            # Lưu ngay FAISS
            if store is not None:
                _save_faiss(store, index_dir)
            
            # Cập nhật ngay meta để UI hiển thị trạng thái đã hoàn thành
            files_map[p] = cur_map[p]
            _save_meta(index_dir, meta)
            
        summary["chunks_added"] = total_chunks
        
        # Nếu thư mục rỗng hoặc PDF không có text (store vẫn None)
        if store is None:
            # Xóa file index cũ (nếu có) để dọn dẹp sạch sẽ
            for ext in ["faiss", "pkl"]:
                old_file = os.path.join(index_dir, f"index.{ext}")
                if os.path.exists(old_file):
                    try: os.remove(old_file)
                    except: pass
        
        _clear_progress(index_dir)
        print("   ✅ Đã xử lý xong toàn bộ danh sách và lưu index.faiss!")
        return summary

    # Xử lý xóa file (Incremental Deletion)
    if removed and store is not None:
        try:
            ids_to_delete = []
            for doc_id, document in store.docstore._dict.items():
                fp = document.metadata.get("file_path")
                if fp in removed:
                    ids_to_delete.append(doc_id)
            if ids_to_delete:
                print(f"   🗑️ Đang xóa {len(ids_to_delete)} Vector của các file đã bị gỡ bỏ...")
                store.delete(ids_to_delete)
        except Exception as e:
            print(f"   ⚠️ Lỗi khi xóa lẻ Vector (FAISS không hỗ trợ?): {e}. Sẽ rebuild toàn bộ ở lần kế tiếp.")

    # incremental thêm mới theo từng file để Frontend cập nhật ngay lập tức
    files_map = meta.setdefault("files", {})
    
    # Xóa các file đã bị remove khỏi meta map trước
    if removed:
        for p in removed:
            files_map.pop(p, None)
        _save_meta(index_dir, meta)
        
    total_added = 0
    if added_or_changed:
        _save_progress(index_dir, 0, len(added_or_changed), "Đang chuẩn bị cập nhật file mới...")
        
    for idx, p in enumerate(added_or_changed):
        _save_progress(index_dir, idx, len(added_or_changed), f"Đang xử lý: {os.path.basename(p)}")
        new_docs: List[Document] = []
        if p.lower().endswith(".mineru.json"):
            new_docs = extract_mineru_json(p)
        else:
            json_counterpart = p[:-4] + ".mineru.json"
            if os.path.exists(json_counterpart):
                # Cập nhật hash gốc cho file pdf nếu bị bỏ qua để tránh index lại
                files_map[p] = cur_map[p]
                _save_meta(index_dir, meta)
                continue
            new_docs = extract_single_pdf(p, enable_ocr=enable_ocr)
        
        if new_docs and store is not None:
            store.add_documents(new_docs)
            _save_faiss(store, index_dir)
            total_added += len(new_docs)
            
        # Cập nhật ngay lập tức vào index_meta.json để UI hiển thị "Đã index"
        files_map[p] = cur_map[p]
        _save_meta(index_dir, meta)
        
    if added_or_changed:
        _clear_progress(index_dir)
        
    summary["chunks_added"] = total_added
    return summary


def verify_index(username: str, doc_type: Optional[str] = None) -> Dict:
    _, index_dir = _ensure_dirs_for_type(username, doc_type)
    store = _load_faiss(index_dir)
    ok = store is not None
    meta = _load_meta(index_dir)
    return {"username": username, "index_dir": index_dir, "ok": ok, "known_files": list(meta.get("files", {}).keys())}


# ---------- NEW: doc-aware retrieval over persisted FAISS ----------
def _select_candidate_files(question: str, file_paths: List[str]) -> List[str]:
    """Pick likely target files from the question by fuzzy overlap on filename (accent-insensitive)."""
    q = _strip_accents_lower(question)
    q_tokens = set(re.findall(r"[a-z0-9]+", q))
    scored = []
    for p in file_paths:
        name = os.path.basename(p)
        n = _strip_accents_lower(name)
        n_tokens = set(re.findall(r"[a-z0-9]+", n))
        if not n_tokens:
            continue
        inter = q_tokens & n_tokens
        union = q_tokens | n_tokens
        jaccard = len(inter) / len(union) if union else 0
        overlap = len(inter)
        substr_boost = 0.0
        for t in n_tokens:
            if len(t) >= 8 and t in q:
                substr_boost = 0.5
                break
        score = jaccard + 0.1 * overlap + substr_boost
        scored.append((score, p, name))
    scored.sort(reverse=True, key=lambda x: x[0])
    # choose top-1 if score clear enough, else top-2
    top = [s for s in scored if s[0] > 0]
    if not top:
        return []
    if len(top) == 1 or (len(top) >= 2 and top[0][0] >= top[1][0] + 0.3):
        return [top[0][1]]
    return [top[0][1], top[1][1]]


def query_index_smart(
    username: str,
    question: str,
    top_k: int = 5,
    probe_k: int = 60,
    doc_type: Optional[str] = None,
) -> Dict:
    """
    Search FAISS index, nhưng cố gắng route đúng file nếu câu hỏi nhắc tới tên file/tác giả.
    Returns dict: {"docs": [Document...], "chosen_files": [paths]}
    """
    _, index_dir = _ensure_dirs_for_type(username, doc_type)
    store = _load_faiss(index_dir)
    if store is None:
        return {"docs": [], "chosen_files": []}
    meta = _load_meta(index_dir)
    file_paths = list(meta.get("files", {}).keys())

    chosen_files = _select_candidate_files(question, file_paths)

    # probe a larger pool, rồi lọc lại theo chosen_files (nếu có)
    results = store.similarity_search_with_score(question, k=max(probe_k, top_k))
    docs = [d for (d, score) in results]

    def _doc_file_match(d: Document) -> Optional[str]:
        # prefer explicit metadata; fallback parse từ 'source'
        fn = d.metadata.get("file_name")
        fp = d.metadata.get("file_path")
        if fp:
            return fp
        if fn:
            # map lại theo basename
            for p in file_paths:
                if os.path.basename(p) == fn:
                    return p
        src = d.metadata.get("source", "")
        if src:
            for p in file_paths:
                if os.path.basename(p) in src:
                    return p
        return None

    if chosen_files:
        filtered: List[Document] = []
        chosen_set = set(chosen_files)
        for d in docs:
            fp = _doc_file_match(d)
            if fp and fp in chosen_set:
                filtered.append(d)
            if len(filtered) >= top_k:
                break
        if filtered:
            return {"docs": filtered[:top_k], "chosen_files": chosen_files}

    # fallback: just take top_k
    return {"docs": docs[:top_k], "chosen_files": chosen_files}