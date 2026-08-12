from sentence_transformers import SentenceTransformer
import os
os.environ["TOKENIZERS_PARALLELISM"] = "false" # Chống kẹt (deadlock) trên Windows

print("⏳ Bắt đầu kết nối và tải mô hình AI. Vui lòng chờ...")
# Khởi tạo model, nó sẽ tự động tải và hiện % rõ ràng
model = SentenceTransformer("AITeamVN/Vietnamese_Embedding")
print("✅ Tải và nạp mô hình thành công 100%!")