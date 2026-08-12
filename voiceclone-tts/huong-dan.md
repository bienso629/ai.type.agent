Dưới đây là tài liệu Hướng dẫn sử dụng (API Documentation) chi tiết cho hệ thống OmniVoice TTS API của bạn. Bạn có thể lưu nội dung này thành file `README.md` hoặc `API_DOCS.md` để đính kèm vào dự án.

---

# Hướng Dẫn Sử Dụng OmniVoice TTS API

Tài liệu này cung cấp hướng dẫn chi tiết cách khởi động và tương tác với các API của hệ thống tạo giọng nói OmniVoice.

## 1. Khởi Động Server

Trước khi gọi API, hãy đảm bảo bạn đã chạy server FastAPI thành công.
Mở Terminal tại thư mục chứa file `api.py` và chạy lệnh:

```bash
uvicorn api:app --host 0.0.0.0 --port 8981
```

* **Base URL:** `http://localhost:8000`
* **Swagger UI (Giao diện test trực tiếp):** `http://localhost:8000/docs`

---

## 2. Chi Tiết Các Endpoints (API)

Hệ thống cung cấp 2 API chính hoạt động theo thứ tự: Nạp mô hình $\rightarrow$ Tạo âm thanh.

### API 1: Nạp Mô Hình (Load Model)
Sử dụng API này một lần duy nhất khi mới khởi động server để tải mô hình OmniVoice lên VRAM của GPU.

* **Endpoint:** `/load_model`
* **Method:** `POST`
* **Content-Type:** `application/json`
* **Tham số:** Không yêu cầu.
* **Kết quả trả về (JSON):**
  ```json
  {
    "status": "success",
    "message": "Nạp mô hình OmniVoice thành công!"
  }
  ```

### API 2: Tạo Âm Thanh (Generate Audio)
API này nhận văn bản, giọng mẫu và các tham số tùy chỉnh để tổng hợp ra file âm thanh `.wav`.
*Lưu ý: Yêu cầu gọi API 1 trước khi gọi API 2.*

* **Endpoint:** `/generate_audio`
* **Method:** `POST`
* **Content-Type:** `multipart/form-data`

**Danh sách Tham số (Form Data):**

| Tham số | Bắt buộc | Kiểu dữ liệu | Mặc định | Mô tả |
| :--- | :---: | :--- | :--- | :--- |
| `text` | **Có** | string | - | Văn bản cần chuyển thành giọng nói. |
| `ref_audio` | **Có** | file | - | File âm thanh mẫu (giọng đọc gốc) định dạng `.wav`, `.mp3`. |
| `ref_text` | Không | string | null | Văn bản của file mẫu. Bỏ trống hệ thống sẽ tự động nhận diện (Whisper). |
| `num_step` | Không | int | 32 | Số bước giải mã. Đặt `16` để sinh nhanh hơn (giảm chút chất lượng). |
| `denoise` | Không | bool | true | Bật để khử nhiễu đầu ra. |
| `guidance_scale`| Không | float | 2.0 | Mức độ tuân thủ giọng mẫu. |
| `t_shift` | Không | float | 0.1 | Độ dịch chuyển thời gian. |
| `position_temperature`| Không | float | 5.0 | Độ ngẫu nhiên chọn vị trí mask. |
| `class_temperature` | Không | float | 0.0 | Độ ngẫu nhiên chọn token. |
| `layer_penalty_factor`| Không | float | 5.0 | Hệ số ưu tiên giải mã các layer cơ bản trước. |
| `duration` | Không | float | null | Ép thời lượng file sinh ra dài chính xác X (giây). |
| `speed` | Không | float | null | Tốc độ đọc. > 1.0 (nhanh hơn), < 1.0 (chậm hơn). Bị bỏ qua nếu có `duration`. |
| `preprocess_prompt` | Không | bool | true | Tiền xử lý file mẫu (xóa khoảng lặng, thêm dấu). |
| `postprocess_output`| Không | bool | true | Hậu xử lý file kết quả (cắt khoảng lặng thừa). |
| `audio_chunk_duration`| Không | float | 15.0 | Thời lượng chia nhỏ văn bản dài (giây). |
| `audio_chunk_threshold`| Không | float | 30.0 | Ngưỡng kích hoạt chia nhỏ (giây). |

* **Kết quả trả về:** File âm thanh trực tiếp (MIME type: `audio/wav`).

---

## 3. Ví dụ Tích Hợp bằng Python (Client)

Dưới đây là một đoạn code mẫu sử dụng thư viện `requests` để tự động hóa việc gọi 2 API này từ một file Python khác.

```python
import requests

BASE_URL = "http://localhost:8000"

def load_model():
    print("Đang nạp model lên VRAM...")
    response = requests.post(f"{BASE_URL}/load_model")
    if response.status_code == 200:
        print("Trạng thái:", response.json()["message"])
    else:
        print("Lỗi nạp model:", response.text)

def generate_tts():
    print("Đang tạo âm thanh...")
    
    # Chuẩn bị file mẫu
    files = {
        "ref_audio": ("sample_voice.wav", open("recording2026-04-02.wav", "rb"), "audio/wav")
    }
    
    # Gửi tham số
    data = {
        "text": "Chào mừng bạn đến với OmniVoice. Đây là một bài kiểm tra tốc độ sinh giọng nói.",
        "speed": 1.2,          # Đọc nhanh hơn 20%
        "num_step": 16         # Tốc độ render nhanh
    }
    
    response = requests.post(f"{BASE_URL}/generate_audio", files=files, data=data)
    
    if response.status_code == 200:
        # Lưu file kết quả
        with open("ket_qua.wav", "wb") as f:
            f.write(response.content)
        print("Tạo thành công! Đã lưu file ket_qua.wav")
    else:
        print("Lỗi tạo âm thanh:", response.json())

if __name__ == "__main__":
    # Bước 1: Nạp model (chỉ cần gọi 1 lần khi server mới bật)
    load_model()
    
    # Bước 2: Sinh âm thanh
    generate_tts()
```