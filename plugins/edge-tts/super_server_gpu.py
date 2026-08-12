import os
import torch
import torchaudio
import edge_tts
import requests
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

# ==========================================
# 1. BẢN VÁ LỖI TENSOR/YAML (RESEMBLE ENHANCE)
# ==========================================
from resemble_enhance.hparams import HParams

@classmethod
def bypass_from_yaml(cls, path):
    return cls() 

HParams.from_yaml = bypass_from_yaml

from resemble_enhance.enhancer.inference import load_enhancer
from resemble_enhance.enhancer.download import download
from resemble_enhance.inference import inference


# ==========================================
# 2. KHỞI TẠO SERVER & MODEL GPU
# ==========================================
app = FastAPI()
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

print("⏳ Hệ thống đang khởi động (Phiên bản Chuẩn API Microsoft + PyTorch Chunking)...")
run_dir_str = download()
run_dir = Path(run_dir_str)

print("🚀 Đang nạp Model AI Enhance vào GPU (GTX 1070)...")
try:
    ENHANCER_MODEL = load_enhancer(run_dir, DEVICE)
    ENHANCER_MODEL = ENHANCER_MODEL.to(DEVICE)
    ENHANCER_MODEL.eval()
    print("✨ CHIẾN THẮNG! 100% Model đã nằm trên GPU và sẵn sàng!")
except Exception as e:
    print(f"❌ Lỗi nạp model: {e}")
    raise e

# Cấu hình API của RVC Server
RVC_API = "http://127.0.0.1:7890/api/rvc"
os.makedirs("temp_audio", exist_ok=True)


# ==========================================
# 3. ĐỊNH NGHĨA DỮ LIỆU TỪ ANGULAR APP
# ==========================================
class TTSPayload(BaseModel):
    text: str
    voice: str = "vi-VN-HoaiMyNeural"
    rate: str = "+30%"
    pitch_edge: str = "+3Hz"
    pitch_rvc: int = 0
    index_rate: float = 0.8
    rvc_model_path: str = "/mnt/c/Users/Wing386/Documents/ai.type/data/models/muaphosaigon/muaphosaigon_3700e_18500s.pth"
    rvc_index_path: str = "/mnt/c/Users/Wing386/Documents/ai.type/data/models/muaphosaigon/added_IVF44_Flat_nprobe_1_muaphosaigon_v2.index"


# ==========================================
# 4. CÁC HÀM XỬ LÝ PIPELINE (LÕI HỆ THỐNG)
# ==========================================

def split_text_by_caps(text: str):
    """
    Thuật toán tách câu thông minh bằng Python thuần: 
    Gom chữ thường thành 1 cụm, chữ IN HOA thành 1 cụm.
    """
    words = text.split()
    segments = []
    current_segment = []
    is_caps_mode = None

    for word in words:
        letters = [c for c in word if c.isalpha()]
        if letters:
            word_is_caps = all(c.isupper() for c in letters)
        else:
            word_is_caps = is_caps_mode if is_caps_mode is not None else False

        if is_caps_mode is None:
            is_caps_mode = word_is_caps

        if word_is_caps == is_caps_mode:
            current_segment.append(word)
        else:
            segments.append((" ".join(current_segment), is_caps_mode))
            current_segment = [word]
            is_caps_mode = word_is_caps

    if current_segment:
        segments.append((" ".join(current_segment), is_caps_mode))

    return segments

async def step_1_edge_tts(payload: TTSPayload, output_path: str):
    print(f"🎙️ Bước 1: Đang tạo giọng gốc (Đọc nguyên văn để tránh ngắt cục)...")
    
    # 🌟 Đã gỡ bỏ tính năng khâu chữ (split_text_by_caps) vì nó phá vỡ ngữ điệu (prosody) của TTS
    # Gây ra hiện tượng giọng đọc bị ngắt cục (stuttering), thiếu tự nhiên.
    communicate = edge_tts.Communicate(
        text=payload.text, 
        voice=payload.voice,
        rate=payload.rate,
        pitch=payload.pitch_edge,
        volume="+0%"
    )
    await communicate.save(output_path)

def step_2_ai_enhance(input_path: str, output_path: str):
    print("✨ Bước 2: AI Enhancer đang làm dày dây thanh quản (GPU)...")
    with torch.no_grad():
        dwav, sr = torchaudio.load(input_path)
        dwav = dwav.mean(0) if dwav.shape[0] > 1 else dwav.squeeze(0)
        hwav, sr_new = inference(model=ENHANCER_MODEL, dwav=dwav, sr=sr, device=DEVICE)
        torchaudio.save(output_path, hwav.unsqueeze(0).cpu(), sr_new)

def step_3_rvc_convert(input_path: str, output_path: str, payload: TTSPayload):
    print("🎭 Bước 3: RVC đang nhập vai...")
    rvc_payload = {
        "input": input_path, 
        "model": payload.rvc_model_path, 
        "index": payload.rvc_index_path, 
        "output": output_path, 
        "pitch": payload.pitch_rvc, # Đã fix lỗi đánh máy ở bản trước
        "index_rate": payload.index_rate, 
        "f0_method": "rmvpe"
    }
    
    response = requests.post(RVC_API, json=rvc_payload)
    if response.status_code != 200:
        raise Exception(f"RVC Error: {response.text}")


# ==========================================
# 5. API ENDPOINT (TRẢ VỀ BLOB CHO ANGULAR)
# ==========================================
@app.post("/generate")
async def generate(payload: TTSPayload):
    temp_edge = os.path.abspath("temp_audio/1_edge.wav")
    temp_enhanced = os.path.abspath("temp_audio/2_enhanced.wav")
    final_out = os.path.abspath("temp_audio/final_result.wav")

    try:
        # Chạy một mạch 3 bước siêu mượt
        await step_1_edge_tts(payload, temp_edge)
        step_2_ai_enhance(temp_edge, temp_enhanced)
        step_3_rvc_convert(temp_enhanced, final_out, payload)
        
        print("✅ Đã chốt đơn thành công! Đang bắn file Binary về Frontend...")
        return FileResponse(path=final_out, media_type="audio/wav", filename="chot_don.wav")
        
    except Exception as e:
        print(f"❌ Quy trình thất bại: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)