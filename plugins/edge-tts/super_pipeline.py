import asyncio
import edge_tts
import requests
import os
import torch
import gc
import torchaudio
from resemble_enhance.enhancer.inference import enhance

# --- CẤU HÌNH HỆ THỐNG ---
RVC_API = "http://127.0.0.1:7890/api/rvc"
MODEL_PATH = "/mnt/c/Users/Wing386/Documents/ai.type/data/models/muaphosaigon/muaphosaigon_3700e_18500s.pth"
INDEX_PATH = "/mnt/c/Users/Wing386/Documents/ai.type/data/models/muaphosaigon/added_IVF44_Flat_nprobe_1_muaphosaigon_v2.index"

TEMP_EDGE = "1_edge_raw.wav"
TEMP_ENHANCED = "2_enhanced.wav"
FINAL_OUTPUT = "final_nu_voice.wav"

# --- ĐỊNH NGHĨA PHONG CÁCH CHO GIỌNG NỮ (PRESETS) ---
# Với giọng nữ HoaiMy, chúng ta tăng Pitch nhẹ để giọng thanh thoát hơn
PRESETS = {
    "tam_su": {
        "voice": "vi-VN-HoaiMyNeural",
        "rate": "-8%",           # Đọc chậm, thủ thỉ
        "pitch_edge": "-1Hz",    # Hạ nhẹ tông để giọng sâu lắng
        "pitch_rvc": 0,          # Giữ nguyên cao độ gốc của HoaiMy
        "index_rate": 0.85,
        "description": "Giọng nữ tâm sự, nhẹ nhàng, truyền cảm."
    },
    "ban_hang_nu": {
        "voice": "vi-VN-HoaiMyNeural",
        "rate": "+45%",           # << Tăng mạnh tốc độ ở đây
        "pitch_edge": "+3Hz",     # << Tăng tông cao hơn chút cho năng lượng
        "pitch_rvc": 0,           
        "index_rate": 0.45,       # << Giảm cái này để giọng nói "lướt" hơn
        "description": "Giọng nữ livestream siêu tốc, chốt đơn thần tốc."
    },
    "ke_chuyen_ma": {
        "voice": "vi-VN-HoaiMyNeural",
        "rate": "-15%",          # Rất chậm
        "pitch_edge": "-3Hz",    # Hạ tông tạo vẻ huyền bí
        "pitch_rvc": -2,         # RVC ép giọng trầm xuống
        "index_rate": 0.95,
        "description": "Giọng nữ ma mị, lạnh lẽo, kịch tính."
    },
    "thanh_thoi": {
        "voice": "vi-VN-HoaiMyNeural",
        "rate": "+0%", 
        "pitch_edge": "+1Hz",
        "pitch_rvc": 0,
        "index_rate": 0.8,
        "description": "Giọng nữ đọc review, tin tức nhẹ nhàng."
    }
}

async def step_1_edge_tts_nu(text, preset_name):
    config = PRESETS.get(preset_name, PRESETS["thanh_thoi"])
    print(f"🎤 Bước 1: Tạo giọng Nữ {preset_name} (HoaiMy SSML)...")
    
    # Bọc SSML để điều khiển "hồn" của giọng nữ
    ssml_text = f"""
    <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="vi-VN">
        <voice name="{config['voice']}">
            <prosody rate="{config['rate']}" pitch="{config['pitch_edge']}" contour="(0%, +0Hz) (100%, +2Hz)">
                {text}
            </prosody>
        </voice>
    </speak>
    """
    communicate = edge_tts.Communicate(ssml_text)
    await communicate.save(TEMP_EDGE)

def step_2_ai_enhance():
    print("✨ Bước 2: AI Enhancer đang làm dày dây thanh quản...")
    # Dọn dẹp bộ nhớ trước khi chạy
    torch.cuda.empty_cache()
    gc.collect()
    dwav, sr = torchaudio.load(TEMP_EDGE)
    # Chuyển Stereo sang Mono (Xử lý lỗi 2D)
    if dwav.shape[0] > 1:
        dwav = dwav.mean(0)
    else:
        dwav = dwav.squeeze(0)
        
    # Chạy Enhancer (Lớp này cực quan trọng để giọng HoaiMy bớt chất robot)
    hwav, sr = enhance(dwav, sr, device="cuda") 
    torchaudio.save(TEMP_ENHANCED, hwav.unsqueeze(0).cpu(), sr)

def step_3_rvc_convert_nu(preset_name):
    config = PRESETS.get(preset_name, PRESETS["thanh_thoi"])
    print(f"🎭 Bước 3: RVC nhập vai giọng Nữ với Pitch {config['pitch_rvc']}...")
    
    payload = {
        "input": os.path.abspath(TEMP_ENHANCED),
        "model": MODEL_PATH,
        "index": INDEX_PATH,
        "output": os.path.abspath(FINAL_OUTPUT),
        "pitch": config['pitch_rvc'],
        "index_rate": config['index_rate'],
        "f0_method": "rmvpe" # Thuật toán RMVPE giữ luyến láy giọng nữ tốt nhất
    }
    
    res = requests.post(RVC_API, json=payload)
    if res.status_code == 200:
        print(f"🎉 HOÀN THÀNH! File: {FINAL_OUTPUT}")
        print(f"📝 Mô tả style: {config['description']}")
    else:
        print(f"❌ Lỗi RVC: {res.text}")

async def run_pipeline_nu(text, style):
    await step_1_edge_tts_nu(text, style)
    step_2_ai_enhance()
    step_3_rvc_convert_nu(style)

if __name__ == "__main__":
    # CHỌN STYLE: 'tam_su', 'ban_hang_nu', 'ke_chuyen_ma', 'thanh_thoi'
    STYLE_SELECTION = "ban_hang_nu" 
    
    noi_dung = "Nồi chiên không dầu là MỘT BƯỚC PHÁT TRIỂN MỚI trong công nghệ chế biến thức ăn, đặc biệt với các món chiên rán. Với cách chế biến truyền thống, bạn cần một lượng dầu mỡ nhất định mới có thể làm chín thực phẩm, đi kèm với đó là những lo ngại về sức khỏe và sự an toàn khi chế biến."
    
    asyncio.run(run_pipeline_nu(noi_dung, STYLE_SELECTION))