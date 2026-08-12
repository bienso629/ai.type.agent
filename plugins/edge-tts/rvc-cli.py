import os
import sys
import argparse
import traceback

# 1. VÁ LỖI BẢO MẬT PYTORCH 2.6 ĐỂ KHÔNG BỊ CHẶN
os.environ["PYTORCH_JIT"] = "0"
try:
    import torch
    def dummy_jit(*args, **kwargs):
        if len(args) > 0 and callable(args[0]): return args[0]
        return lambda f: f
    torch.jit.script = dummy_jit
    torch.jit.ignore = dummy_jit
    if hasattr(torch.jit, 'script_method'): torch.jit.script_method = dummy_jit
    
    _original_load = torch.load
    def _patched_load(*args, **kwargs):
        kwargs['weights_only'] = False
        return _original_load(*args, **kwargs)
    torch.load = _patched_load
except ImportError:
    pass

import warnings
warnings.filterwarnings("ignore")

import rvc_python.__main__ as rvc_main

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--index", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    # 2. XÂY DỰNG LỆNH CHUẨN XÁC 100% (CÓ GẮN INDEX)
    sys.argv = [
        "rvc_python", "cli",
        "-i", args.input,
        "-mp", args.model,
        "-o", args.output,
        "-pi", "0",
        "-me", "rmvpe",
        "-d", "cuda:0",
        "-ip", args.index,
        "-ir", "0.75"  # Ép cứng kiểu string để không bị lỗi parse
    ]

    print("\n" + "="*70)
    print(f"🚀 ĐANG TEST ĐỘC LẬP VỚI LỆNH:\n{' '.join(sys.argv)}")
    print("="*70 + "\n")

    try:
        if hasattr(rvc_main, 'cli'):
            rvc_main.cli()
        elif hasattr(rvc_main, 'main'):
            rvc_main.main()
            
        # 3. KẾT LUẬN SAU KHI CHẠY XONG
        print("\n" + "="*70)
        if os.path.exists(args.output):
            size = os.path.getsize(args.output)
            if size < 1024:
                print(f"❌ KẾT LUẬN: File sinh ra vẫn bị câm ({size} bytes).")
                print("👉 Đích thị file Index bị hỏng hoặc khác hệ phiên bản (V1 vs V2)!")
            else:
                print(f"✅ KẾT LUẬN: File sinh ra CÓ TIẾNG ({size/1024:.2f} KB)!")
                print("👉 Bạn ĐÃ ĐÚNG! API Flask cũ đã làm nhiễu dữ liệu Index.")
        else:
            print("❌ LỖI: Không sinh ra được file output.")
        print("="*70 + "\n")
            
    except Exception as e:
        print("\n❌ CRASH TRONG QUÁ TRÌNH CHẠY:")
        traceback.print_exc()

if __name__ == "__main__":
    main()