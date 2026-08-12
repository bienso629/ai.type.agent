import os
import chromadb
from google import genai
from google.genai import types
from PyPDF2 import PdfReader
from chromadb.api.types import EmbeddingFunction
import warnings

warnings.filterwarnings("ignore")

# --- CẤU HÌNH ---
API_KEY = "AIzaSyCGRvcp7MFEdvZDPX_TAMS2CGFLRpuc144"
CHROMA_DATA_PATH = "./my_vectordb_final_v7" # Đổi tên folder để làm sạch hoàn toàn
COLLECTION_NAME = "thong_tu_152_fixed"

client_gemini = genai.Client(api_key=API_KEY)

class GeminiEmbeddingFunction(EmbeddingFunction):
    def __call__(self, input):
        try:
            # Thử với tên model cơ bản nhất
            response = client_gemini.models.embed_content(
                model="gemini-embedding-001", 
                contents=input,
                config=types.EmbedContentConfig(task_type="RETRIEVAL_DOCUMENT")
            )
            return [e.values for e in response.embeddings]
        except Exception as e:
            print(f"\n[LỖI EMBEDDING]: {e}")
            return None

gemini_ef = GeminiEmbeddingFunction()

client_chroma = chromadb.PersistentClient(path=CHROMA_DATA_PATH)
collection = client_chroma.get_or_create_collection(
    name=COLLECTION_NAME,
    embedding_function=gemini_ef
)

def add_pdf_to_db(file_path):
    if not os.path.exists(file_path):
        print(f"Không tìm thấy file: {file_path}")
        return

    print(f"Đang đọc file PDF: {file_path}...")
    reader = PdfReader(file_path)
    documents, ids, metadatas = [], [], []

    for i, page in enumerate(reader.pages):
        text = page.extract_text()
        if text and text.strip():
            documents.append(text)
            metadatas.append({"page": i + 1})
            ids.append(f"p{i+1}")
            print(f"-> Đã trích xuất trang {i+1}", end="\r")

    if documents:
        print(f"\nĐang nạp {len(documents)} trang vào Vector DB (Vui lòng chờ)...")
        try:
            collection.add(documents=documents, metadatas=metadatas, ids=ids)
            print(f"--- THÀNH CÔNG: Đã lưu {collection.count()} trang vào SQLite! ---")
        except Exception as e:
            print(f"--- THẤT BẠI: Lỗi khi lưu vào ChromaDB: {e} ---")
    else:
        print("\nLỗi: Không tìm thấy nội dung chữ trong file PDF.")

def ask_bot(question):
    # Kiểm tra DB trước khi hỏi
    if collection.count() == 0:
        return "Dữ liệu trống, không thể trả lời. Vui lòng kiểm tra lại quá trình Index."

    results = collection.query(query_texts=[question], n_results=3)
    if not results['documents'] or not results['documents'][0]:
        return "Không tìm thấy thông tin liên quan trong tài liệu."
        
    context = "\n".join(results['documents'][0])
    prompt = f"Dựa vào nội dung Thông tư 152: {context}\n\nCâu hỏi: {question}"
    
    response = client_gemini.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt
    )
    return response.text

if __name__ == "__main__":
    pdf_file = "Thong tu 152 ve HO KINH DOANH 123.pdf"
    
    # Ép buộc Index nếu DB đang trống
    if collection.count() == 0:
        add_pdf_to_db(pdf_file)
    
    print(f"\n[TRẠNG THÁI: Dữ liệu hiện có {collection.count()} trang]")
    
    if collection.count() > 0:
        while True:
            q = input("\nHỏi: ")
            if q.lower() in ['exit', 'thoát']: break
            try:
                print("Đang xử lý...", end="\r")
                print(f"Trả lời: {ask_bot(q)}")
            except Exception as e:
                print(f"\nLỗi: {e}")