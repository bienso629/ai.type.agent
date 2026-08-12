# Gemini PDF Chatbot

## 1) Tạo/kích hoạt môi trường ảo `.chatbot`
Nếu đã có `.chatbot` thì bỏ qua bước tạo.

```powershell
# Tạo venv nếu chưa có
cd C:\Users\Wing386\apps\chatbot
python -m venv .chatbot

# Kích hoạt
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
& .\.chatbot\Scripts\Activate.ps1
```

Gemini PDF Chatbot is a Streamlit-based application that allows users to chat with a conversational AI model trained on PDF documents. The chatbot extracts information from uploaded PDF files and answers user questions based on the provided context.
<https://gmultichat.streamlit.app/>

<https://github.com/kaifcoder/gemini_multipdf_chat/assets/57701861/f6a841af-a92d-4e54-a4fd-4a52117e17f6>

## Features

- **PDF Upload:** Users can upload multiple PDF files.
- **Text Extraction:** Extracts text from uploaded PDF files.
- **Conversational AI:** Uses the Gemini conversational AI model to answer user questions.
- **Chat Interface:** Provides a chat interface to interact with the chatbot.

## Yêu cầu cài đặt

Cài đặt nhanh cho OCR trên Windows

Cài Tesseract:

PowerShell:

```bash
winget install --id UB-Mannheim.TesseractOCR -e
```
(Bản UB Mannheim kèm tiếng Việt.)
Hoặc tải installer từ dự án UB Mannheim.

Cài Python libs:

```bash
pip install -U pytesseract pymupdf pillow

pip install -U \
  "langchain>=0.3,<0.4" \
  "langchain-community>=0.3,<0.4" \
  "langchain-text-splitters>=0.3,<0.4" \
  "langchain-huggingface>=0.0.3" \
  "langchain-google-genai>=2.1.0" \
  "sentence-transformers" "faiss-cpu"

pip install pypdf

# (khuyên) gỡ SDK cũ
pip uninstall -y google-generativeai

// cần cài cái libreoffice trên ubuntu để nó đọc hiểu được file doc
sudo apt update
sudo apt install libreoffice  # hoặc: sudo apt install unoconv
pip install python-docx
```

## Getting Started

Một số cấu hình cần lưu ý: 

### Chatbot LLM Gemini

```bash
# Crawl tất cả sitemap trong sitemaps.json
python crawler.py

# Chỉ crawl domain cụ thể (lọc sitemap theo domain)
python crawler.py --domain example.com

# Xoá dữ liệu cũ của domain rồi crawl lại (data/<domain> và report của domain đó)
python crawler.py --domain example.com --force

uvicorn account:app --host 0.0.0.0 --port 8001
uvicorn chatbot:app --host 0.0.0.0 --port 8002
uvicorn website:app --host 0.0.0.0 --port 8003

// cái watchdog chỉ chạy dưới local windows thôi
uvicorn watchdog_main:app --host 0.0.0.0 --port 8004 --env-file .env

// rồi chạy ngrok của bienso629@gmail.com
./ngrok.exe config add-authtoken 2wdGdFOSS4y8vWzWiBbd7owCb1G_82KCZJczjbzdZfNUdkse8
./ngrok.exe http --url=sturgeon-hardy-uniformly.ngrok-free.app 8002
```

### Kết nối Telegram với WebHook

```bash
curl -X POST "https://api.telegram.org/bot7836604278:AAG0FM1kcH58-WM07jFIvvOk_lANKNi_o3c/setWebhook" -d "url=https://n8n.type.vn/webhook/telegram-gemini"
curl https://api.telegram.org/bot7836604278:AAG0FM1kcH58-WM07jFIvvOk_lANKNi_o3c/getWebhookInfo
curl https://api.telegram.org/bot7836604278:AAG0FM1kcH58-WM07jFIvvOk_lANKNi_o3c/getUpdates
curl https://api.telegram.org/bot7836604278:AAG0FM1kcH58-WM07jFIvvOk_lANKNi_o3c/deleteWebhook
```