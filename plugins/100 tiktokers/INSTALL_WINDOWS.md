
# Hướng dẫn cài đặt thư viện (Windows 10) — CPU-only & NVIDIA GPU

Tài liệu giúp chuẩn bị môi trường chạy Whisper/STT + SSE cho Windows 10 (Python 3.12 x64). Gồm 2 cấu hình: **không có card rời (CPU-only)** và **có card rời NVIDIA (CUDA)**.

---

## 0) Chuẩn bị chung

**PowerShell (Run as Administrator)**

### 0.1 Visual C++ Redistributable (x64 & x86)
```powershell
winget install --id Microsoft.VCRedist.2015+.x64 -e
winget install --id Microsoft.VCRedist.2015+.x86 -e
```
> Reboot Windows sau khi cài.

### 0.2 Python 3.12 x64 + Virtualenv
```powershell
py -3.12 -m venv venv
.env\Scripts\Activate.ps1
python -m pip install --upgrade pip setuptools wheel
python - << 'PY'
import platform, sys; print(sys.version); print(platform.architecture())
PY
```
Kỳ vọng `('64bit', ...)`.

### 0.3 FFmpeg
```powershell
winget install Gyan.ffmpeg
ffmpeg -version
```

---

## 1) Máy **KHÔNG có card rời** (CPU-only)

### 1.1 Cài Torch CPU
```powershell
pip uninstall -y torch torchvision torchaudio
pip cache purge
pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

### 1.2 Cài Whisper & Faster-Whisper (tuỳ chọn)
```powershell
pip install --no-cache-dir openai-whisper
pip install --no-cache-dir "ctranslate2==4.5.0" "faster-whisper==1.0.3"
```
> Muốn chạy ngay, ép backend dùng openai-whisper (CPU):
```powershell
setx WHISPER_BACKEND openai
```

### 1.3 Kiểm tra
```powershell
python - << 'PY'
import torch; print("torch:", torch.__version__); print("cuda:", torch.cuda.is_available())
PY
python - << 'PY'
import ctranslate2; print("ctranslate2:", ctranslate2.__file__)
PY
```

---

## 2) Máy **CÓ card rời NVIDIA (CUDA)**

### 2.1 Kiểm tra driver
```powershell
nvidia-smi
```

### 2.2 Cài Torch CUDA (ví dụ cu121)
```powershell
pip uninstall -y torch torchvision torchaudio
pip cache purge
pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```
> Chọn đúng index `cuXXX` theo phiên bản bạn hỗ trợ.

### 2.3 Cài Faster-Whisper / CTranslate2
Bắt đầu bằng CPU để chắc chắn rồi mới bật GPU:
```powershell
pip install --no-cache-dir "ctranslate2==4.5.0" "faster-whisper==1.0.3"
```
Nếu dùng `openai-whisper` trên GPU, chỉ cần Torch CUDA ok; set device `"cuda"` trong app.

### 2.4 Kiểm tra
```powershell
python - << 'PY'
import torch
print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())
print("device count:", torch.cuda.device_count())
if torch.cuda.is_available():
    i = torch.cuda.current_device()
    print("current:", i, torch.cuda.get_device_name(i))
PY
```

---

## 3) Thư viện server/app (ví dụ)
```powershell
pip install fastapi uvicorn python-multipart pydantic pydub
```

---

## 4) Biến môi trường hữu ích
```powershell
# auto: thử faster-whisper, lỗi thì fallback openai-whisper
# openai: chỉ dùng openai-whisper
# ctranslate2: chỉ dùng faster-whisper
setx WHISPER_BACKEND auto
setx WHISPER_MODEL small
```
**Cloudflared** (SSE qua Cloudflare):
```powershell
# Quick Tunnel
cloudflared tunnel --url http://127.0.0.1:8000 --no-chunked-encoding --edge-ip-version auto
```

---

## 5) Chạy server (ổn định SSE)
```powershell
uvicorn app:app --host 0.0.0.0 --port 8000 --workers 1 --timeout-keep-alive 120
```

---

## 6) Lỗi thường gặp

### WinError 126 / thiếu `c10.dll` (Torch)
- Cài VC++ x64 & x86 → reboot.
- Cài lại Torch đúng index (CPU hoặc CUDA).
- Dùng venv sạch; test import:
```powershell
python - << 'PY'
import torch; print(torch.__version__); print("cuda:", torch.cuda.is_available())
PY
```

### Thiếu `ctranslate2.dll`
- `pip install "ctranslate2==4.5.0" "faster-whisper==1.0.3"`
- Tạm thời `setx WHISPER_BACKEND openai` để chạy ngay bằng PyTorch CPU.

### SSE 200 OK nhưng không có dữ liệu
- Phải gọi `/start` để có `session_id` và job chạy.
- Ở client lắng nghe event theo tên: `ready`, `segment`, `heartbeat`, `done`.

### Cloudflare 530 (unregistered)
- Quick Tunnel phải đang **chạy** (không đóng terminal).
- Dùng URL **mới** khi mở lại Quick Tunnel.
- Khuyên dùng **Named Tunnel** + subdomain riêng.

---

## 7) Checklist CPU-only để chạy ngay
1. VC++ x64/x86 → reboot
2. venv & pip upgrade
3. Cài Torch CPU theo index `.../whl/cpu`
4. `pip install openai-whisper` (+ `ctranslate2 faster-whisper` tuỳ chọn)
5. Cài FFmpeg
6. `setx WHISPER_BACKEND openai`
7. `uvicorn app:app --workers 1`
8. Gọi `/start` → mở SSE (thấy `ready` → `segment`)

Chúc bạn chạy mượt!
