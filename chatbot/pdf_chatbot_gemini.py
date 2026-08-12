# pdf_chatbot_gemini.py

import os
import re
from typing import Optional, List, Dict, Any

import torch
from google import genai
from google.genai import types
from langchain_community.vectorstores import FAISS
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyMuPDFLoader
from langchain_core.documents import Document

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

EMBEDDING_MODEL = "AITeamVN/Vietnamese_Embedding"
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "3000")) 
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "300"))

def _faiss_files_exist(index_dir: str, index_name: str = "index") -> bool:
    """Kiểm tra đủ 2 file FAISS: index.faiss + index.pkl"""
    return (
        os.path.exists(os.path.join(index_dir, f"{index_name}.faiss"))
        and os.path.exists(os.path.join(index_dir, f"{index_name}.pkl"))
    )

# ---------- PDF text normalization ----------
def _is_lowerish_start(s: str) -> bool:
    if not s:
        return False
    c0 = s[0]
    return c0.islower() or c0.isdigit() or c0 in "-–—([“\"'"

def _normalize_wrapped_text(text: str) -> str:
    if not text:
        return ""
    s = text.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"(\w)-\n(\w)", r"\1\2", s, flags=re.UNICODE)
    s = re.sub(r"\n{2,}", " <PARA_BREAK> ", s)

    lines = [ln.strip() for ln in s.split("\n")]
    merged: List[str] = []
    for i, ln in enumerate(lines):
        if not ln:
            continue
        nxt = lines[i + 1] if i < len(lines) - 1 else ""
        end_punct = bool(re.search(r"[\.!?…:;»”\)\]]$", ln))
        starts_bullet = bool(re.match(r"^(\-|\u2022|•|\d+[\.\)]\s+)", nxt))
        if "<PARA_BREAK>" in ln:
            merged.append(ln)
            continue
        if not end_punct and not starts_bullet and _is_lowerish_start(nxt):
            merged.append(ln + " ")
        else:
            merged.append(ln + " <LINE_BREAK> ")
    s = "".join(merged)
    s = s.replace("<PARA_BREAK>", "\n\n")
    s = s.replace("<LINE_BREAK>", " ")
    s = re.sub(r"[ \t]{2,}", " ", s).strip()
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s

# ---------- Smart routing by filename ----------
def _strip_accents_lower(s: str) -> str:
    import unicodedata
    if not s:
        return ""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s.lower()

def _select_candidate_files_from_docs(question: str, docs: List[Document]) -> List[str]:
    q = _strip_accents_lower(question)
    q_tokens = set(re.findall(r"[a-z0-9]+", q))
    scored = []
    files = {}
    for d in docs:
        fp = d.metadata.get("file_path") or ""
        fn = d.metadata.get("file_name") or os.path.basename(d.metadata.get("source", ""))
        if not fp:
            continue
        files[fp] = fn

    for fp, fn in files.items():
        n = _strip_accents_lower(fn)
        n_tokens = set(re.findall(r"[a-z0-9]+", n))
        if not n_tokens:
            continue
        overlap = len(q_tokens & n_tokens)
        jaccard = overlap / (len(n_tokens) + 1)
        substr_boost = 0.0
        for t in sorted(n_tokens, key=len, reverse=True)[:3]:
            if len(t) >= 8 and t in q:
                substr_boost = 0.5
                break
        score = jaccard + 0.1 * overlap + substr_boost
        scored.append((score, fp))
    scored.sort(reverse=True, key=lambda x: x[0])
    if not scored or scored[0][0] <= 0:
        return []
    if len(scored) == 1 or (len(scored) >= 2 and scored[0][0] >= scored[1][0] + 0.3):
        return [scored[0][1]]
    return [scored[0][1], scored[1][1]]

# ============================================================================
# MAIN CLASS
# ============================================================================

class PDFChatbot:
    def __init__(
        self,
        index_dir: str = "faiss_pdf_index",
        k: int = 10,
        embedding_model_name: str = EMBEDDING_MODEL,
        llm_model: str = "gemini-2.0-flash",
        temperature: float = 0.0,
        google_api_key: Optional[str] = None,
        custom_prompt: Optional[str] = None,
        user_instruction: Optional[str] = None,
        mode: str = "default",
        streaming: bool = False,
        index_name: str = "index",
    ):
        self.index_dir = index_dir
        self.index_name = index_name
        self.k = k
        self.mode = mode
        self.temperature = temperature
        self.llm_model = llm_model
        self.streaming = streaming
        self.user_instruction = (user_instruction or "").strip() 
        self.custom_prompt = custom_prompt

        if google_api_key:
            os.environ["GOOGLE_API_KEY"] = google_api_key
            # Đây là cách viết mới cho thư viện google-genai
            self.client = genai.Client(api_key=google_api_key)
        else:
            # Nếu không có key truyền vào, có thể khởi tạo client mặc định 
            # (nó sẽ tự tìm trong biến môi trường GOOGLE_API_KEY)
            self.client = genai.Client()

        # Khởi tạo Embeddings (dùng cho FAISS)
        self.embeddings = HuggingFaceEmbeddings(
            model_name=embedding_model_name,
            model_kwargs={"device": "cuda" if torch.cuda.is_available() else "cpu"},
        )

        self.vector_store: Optional[FAISS] = None
        self.retriever = None

        # Load Index nếu đã có
        if _faiss_files_exist(self.index_dir, self.index_name):
            self._load_faiss()

    # -------------- Public API -----------------
    def get_persona_by_mode(self, mode: str) -> str:
        """Trả về System Instruction (Persona) dựa trên mode"""
        default = "Bạn là trợ lý AI thông minh, chuyên trả lời câu hỏi dựa trên tài liệu được cung cấp. Hãy trả lời bằng tiếng Việt rõ ràng, chính xác."
        
        templates = {
            "default": default,
            "qa_detailed": "Bạn là chuyên gia phân tích. Hãy trả lời chi tiết, sâu sắc dựa trên tài liệu.",
            "summary": "Bạn là chuyên gia tóm tắt. Nhiệm vụ của bạn là tóm tắt nội dung ngắn gọn, súc tích.",
            "legal": "Bạn là trợ lý pháp lý. Hãy trả lời dựa trên các điều khoản, quy định trong văn bản pháp luật được cung cấp.",
            "analysis": "Bạn là chuyên gia phân tích dữ liệu. Hãy đưa ra nhận xét, so sánh và kết luận dựa trên số liệu trong bài.",
            "technical": "Bạn là kỹ sư kỹ thuật. Hãy giải thích các khái niệm, quy trình kỹ thuật một cách chính xác.",
            "textbook": "Bạn là giáo viên. Hãy giải thích kiến thức trong sách giáo khoa một cách dễ hiểu cho học sinh.",
            "thesis": "Bạn là người hướng dẫn nghiên cứu. Hãy sử dụng văn phong học thuật, trang trọng.",
            "contract": "Bạn là chuyên viên pháp chế rà soát hợp đồng. Hãy chú ý đến quyền và nghĩa vụ các bên.",
            "slides": "Bạn là diễn giả. Hãy diễn giải các ý chính trong slide thành bài nói chuyện mạch lạc.",
            "academic_article": "Bạn là nhà nghiên cứu. Hãy tập trung vào phương pháp, kết quả và ý nghĩa của bài báo."
        }
        return templates.get(mode, default)

    def load_index(self):
        """Nạp FAISS index từ ổ cứng vào RAM"""
        if self.vector_store is not None:
            return # Đã nạp rồi thì thôi

        from langchain_huggingface import HuggingFaceEmbeddings
        from langchain_community.vectorstores import FAISS
        
        # Phải dùng đúng model embeddings đã dùng khi tạo index
        embeddings = HuggingFaceEmbeddings(
            model_name=EMBEDDING_MODEL,
            model_kwargs={"device": "cuda" if torch.cuda.is_available() else "cpu"},
        )
        
        if _faiss_files_exist(self.index_dir):
            try:
                self.vector_store = FAISS.load_local(
                    self.index_dir, 
                    embeddings, 
                    allow_dangerous_deserialization=True
                )
                print(f"✅ Loaded index: {self.index_dir}")
            except Exception as e:
                print(f"❌ Error loading index: {e}")
        else:
            print(f"⚠️ Index path not found: {self.index_dir}")

    def get_relevant_documents(self, query: str, k: int = 4) -> List[Document]:
        """Hàm lấy tài liệu thô"""
        # TỰ ĐỘNG LOAD NẾU CHƯA CÓ
        if self.vector_store is None:
            self.load_index()
            
        if self.vector_store:
            return self.vector_store.similarity_search(query, k=k)
        return []

    def index(self, files: List[str]) -> dict:
        """
        Hàm index giữ nguyên logic cũ dùng LangChain PyPDFLoader + FAISS
        """
        if not files:
            return {"ok": False, "error": "No files provided"}
        os.makedirs(self.index_dir, exist_ok=True)

        docs: List[Document] = []
        for path in files:
            if not path or not os.path.exists(path):
                continue
            if os.path.splitext(path)[1].lower() != ".pdf":
                continue
            try:
                pages = PyMuPDFLoader(path).load()
                abs_path = os.path.abspath(path)
                file_name = os.path.basename(path)
                for d in pages:
                    d.page_content = _normalize_wrapped_text(d.page_content or "")
                    d.metadata["file_name"] = file_name
                    d.metadata["file_path"] = abs_path
                    if "page" in d.metadata and "page_number" not in d.metadata:
                        try:
                            d.metadata["page_number"] = int(d.metadata["page"]) + 1
                        except Exception:
                            pass
                    docs.append(d)
            except Exception as e:
                print(f"Error loading {path}: {e}")
                continue

        if not docs:
            return {"ok": False, "error": "No PDF pages loaded"}

        splitter = RecursiveCharacterTextSplitter(chunk_size=CHUNK_SIZE, chunk_overlap=CHUNK_OVERLAP,
                                                  separators=["\n\n", ". ", "? ", "! ", "\n", "; ", ": ", " "])
        chunks = splitter.split_documents(docs)
        if not chunks:
            return {"ok": False, "error": "No chunks created"}

        vs = FAISS.from_documents(chunks, self.embeddings)
        vs.save_local(self.index_dir, index_name=self.index_name)

        self._load_faiss()
        
        return {
            "ok": True,
            "index_dir": self.index_dir,
            "index_name": self.index_name,
            "chunks": len(chunks),
            "docs": len(docs),
        }

    def query(self, question: str, history: list = None) -> dict:
        """
        Hàm query mới hỗ trợ Multi-turn Chat History.
        Sử dụng google.generativeai (SDK gốc) thay vì LangChain chain.
        """
        # 1. Kiểm tra Index
        if not self.vector_store:
            raise RuntimeError(
                f"FAISS index chưa tồn tại ở '{self.index_dir}'. "
                f"Hãy gọi API /index-files/{{username}} trước khi hỏi."
            )

        # 2. Tìm kiếm ngữ cảnh (RAG) - Logic cũ
        probe_k = max(60, self.k)
        results = self.vector_store.similarity_search_with_score(question, k=probe_k)
        pool_docs: List[Document] = [d for (d, _) in results]

        chosen_files = _select_candidate_files_from_docs(question, pool_docs)

        def _doc_fp(d: Document) -> str:
            fp = d.metadata.get("file_path")
            if fp: return os.path.abspath(fp)
            src = d.metadata.get("source", "")
            return os.path.abspath(src) if src else ""

        docs: List[Document] = []
        if chosen_files:
            chosen_set = set(os.path.abspath(p) for p in chosen_files)
            for d in pool_docs:
                if _doc_fp(d) in chosen_set:
                    docs.append(d)
                if len(docs) >= self.k:
                    break
        if not docs:
            docs = pool_docs[: self.k]

        # Xử lý trường hợp không tìm thấy docs
        if not docs:
            # Nếu không tìm thấy docs, vẫn cho phép chat tiếp (chitchat) nhưng cảnh báo
            # Hoặc trả về luôn tùy logic. Ở đây mình cho trả về message báo không tìm thấy.
            msg = "Không tìm thấy nội dung phù hợp trong tài liệu để trả lời câu hỏi này."
            return {
                "result": msg,
                "source_documents": [],
                "content": msg,
                "answer": msg,
                "text": msg,
                "sources": [],
            }

        # 3. Chuẩn bị Context String
        context_text = self._format_docs(docs)

        # 4. Xây dựng System Instruction (Chứa Persona + Context RAG)
        # Lấy template cơ bản
        base_instruction = self.custom_prompt or self._get_system_instruction_template(self.mode)
        
        # Thêm User Instruction (nếu có)
        extra_note = ""
        if self.user_instruction:
            extra_note = f"\n\n[LƯU Ý BỔ SUNG TỪ NGƯỜI DÙNG]: {self.user_instruction}"

        # Ghép thành System Instruction hoàn chỉnh cho Gemini
        full_system_instruction = f"""{base_instruction}

{extra_note}

================ THÔNG TIN TÀI LIỆU THAM KHẢO (CONTEXT) ================
Dưới đây là thông tin trích xuất từ tài liệu PDF. Hãy dùng thông tin này để trả lời câu hỏi.
Nếu thông tin không có trong đoạn văn bản này, hãy nói rõ là tài liệu không đề cập.

{context_text}
========================================================================
"""

        # 5. Gọi Google Gemini SDK (Hỗ trợ History)
        try:
            # 2. Làm sạch tên model
            model_id = self.llm_model.replace("models/", "")

            # 3. Khởi tạo Chat Session
            # Trong SDK mới, system_instruction được đưa vào tham số config của start_chat
            chat_session = self.client.chats.create(
                model=model_id,
                config=types.GenerateContentConfig(
                    system_instruction=full_system_instruction,
                ),
                history=history or []
            )

            # 4. Gửi tin nhắn và lấy kết quả
            response = chat_session.send_message(question)
            text_result = response.text

        except Exception as e:
            text_result = f"Lỗi khi gọi Gemini: {str(e)}"
            # Fallback nếu lỗi: trả về context gốc
            if not text_result.strip():
                 text_result = (context_text[:800] + "…") if len(context_text) > 800 else context_text

        # 6. Chuẩn bị Sources để trả về
        sources = []
        for d in docs:
            sources.append({
                "source": d.metadata.get("file_name") or os.path.basename(d.metadata.get("source", "")),
                "page": d.metadata.get("page_number") or d.metadata.get("page")
            })

        return {
            "result": text_result,
            "source_documents": docs,
            "content": text_result,
            "answer": text_result,
            "text": text_result,
            "sources": sources,
        }

    def _load_faiss(self):
        self.vector_store = FAISS.load_local(
            self.index_dir,
            self.embeddings,
            allow_dangerous_deserialization=True,
            index_name=self.index_name,
        )
        # self.retriever không dùng trong hàm query mới, nhưng giữ lại nếu cần mở rộng
        self.retriever = self.vector_store.as_retriever(search_kwargs={"k": self.k})

    @staticmethod
    def _format_docs(docs: List[Document]) -> str:
        return "\n\n".join((d.page_content or "").strip() for d in docs if getattr(d, "page_content", ""))

    def _get_system_instruction_template(self, mode: str) -> str:
        """Trả về System Instruction (Persona) dựa trên mode"""
        default = "Bạn là trợ lý AI thông minh, chuyên trả lời câu hỏi dựa trên tài liệu được cung cấp. Hãy trả lời bằng tiếng Việt rõ ràng, chính xác."
        
        templates = {
            "default": default,
            "qa_detailed": "Bạn là chuyên gia phân tích. Hãy trả lời chi tiết, sâu sắc dựa trên tài liệu.",
            "summary": "Bạn là chuyên gia tóm tắt. Nhiệm vụ của bạn là tóm tắt nội dung ngắn gọn, súc tích.",
            "legal": "Bạn là trợ lý pháp lý. Hãy trả lời dựa trên các điều khoản, quy định trong văn bản pháp luật được cung cấp.",
            "analysis": "Bạn là chuyên gia phân tích dữ liệu. Hãy đưa ra nhận xét, so sánh và kết luận dựa trên số liệu trong bài.",
            "technical": "Bạn là kỹ sư kỹ thuật. Hãy giải thích các khái niệm, quy trình kỹ thuật một cách chính xác.",
            "textbook": "Bạn là giáo viên. Hãy giải thích kiến thức trong sách giáo khoa một cách dễ hiểu cho học sinh.",
            "thesis": "Bạn là người hướng dẫn nghiên cứu. Hãy sử dụng văn phong học thuật, trang trọng.",
            "contract": "Bạn là chuyên viên pháp chế rà soát hợp đồng. Hãy chú ý đến quyền và nghĩa vụ các bên.",
            "slides": "Bạn là diễn giả. Hãy diễn giải các ý chính trong slide thành bài nói chuyện mạch lạc.",
            "academic_article": "Bạn là nhà nghiên cứu. Hãy tập trung vào phương pháp, kết quả và ý nghĩa của bài báo."
        }
        return templates.get(mode, default)