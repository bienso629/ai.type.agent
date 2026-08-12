import torch
import time

try:
    from omnivoice import OmniVoice
    
    # Tắt benchmark để tránh lag do input có kích thước động
    torch.backends.cudnn.benchmark = False
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32 = True

    model = OmniVoice.from_pretrained(
        r"D:\projects\apps\voiceclone-tts\models--k2-fsa--OmniVoice\models--k2-fsa--OmniVoice\snapshots\995b1b114ae423a4fd69b3834a6fd86423dd361c",
        device_map="cuda:0",
        dtype=torch.float16,
        local_files_only=True
    )
    
    sentences = [
        "Đêm khuya, tại văn phòng trung tâm dữ liệu của Nam – một CTO trẻ đang quản lý hệ thống máy chủ gánh vác hơn 500 website của các doanh nghiệp lớn nhỏ.",
        "Màn hình giám sát bỗng lóe lên những cảnh báo đỏ rực.",
        "Một cuộc tấn công tổng lực đang diễn ra."
    ]
    
    print("\n--- TEST BATCHING ---")
    start = time.time()
    with torch.inference_mode():
        out_batch = model.generate(text=sentences, num_step=32)
    print(f"Batched took: {time.time() - start:.2f}s")
    
except Exception as e:
    import traceback
    traceback.print_exc()
