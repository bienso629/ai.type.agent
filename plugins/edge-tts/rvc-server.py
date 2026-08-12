import os
import sys
import torch
import traceback
import subprocess
from flask import Flask, request, jsonify
from flask_cors import CORS

# ==============================================================================
# 🛠️ PHẦN 1: FIX LỖI PYTORCH & MÔI TRƯỜNG (DÀNH CHO WSL)
# ==============================================================================
os.environ["PYTORCH_JIT"] = "0"
try:
    # Fix lỗi JIT thường gặp trên môi trường Linux mới
    def dummy_jit(*args, **kwargs):
        if len(args) > 0 and callable(args[0]): return args[0]
        return lambda f: f
    torch.jit.script = dummy_jit
    torch.jit.ignore = dummy_jit
    if hasattr(torch.jit, 'script_method'): torch.jit.script_method = dummy_jit
    
    # Fix lỗi bảo mật khi load model (.pth)
    _original_load = torch.load
    def _patched_load(*args, **kwargs):
        kwargs['weights_only'] = False
        return _original_load(*args, **kwargs)
    torch.load = _patched_load
except Exception:
    pass

# ==============================================================================
# 🤖 PHẦN 2: WORKER XỬ LÝ RVC (CHẠY TRONG LUỒNG RIÊNG)
# ==============================================================================
if len(sys.argv) > 1 and sys.argv[1] == "worker":
    import rvc_python.__main__ as rvc_main
    sys.argv.pop(1) 
    sys.argv[0] = "rvc_python" 
    try:
        if hasattr(rvc_main, 'cli'): rvc_main.cli()
        elif hasattr(rvc_main, 'main'): rvc_main.main()
    except Exception as e:
        traceback.print_exc()
        sys.exit(1)
    sys.exit(0)

# ==============================================================================
# 🌐 PHẦN 3: FLASK API SERVER
# ==============================================================================
app = Flask(__name__)
CORS(app) # Cho phép Angular/Electron gọi API thoải mái

@app.route('/api/rvc', methods=['POST'])
def run_rvc_api():
    try:
        data = request.json
        
        # Đường dẫn file (Hỗ trợ cả đường dẫn Windows /mnt/c/...)
        input_path = os.path.normpath(data.get('input', ''))
        model_path = os.path.normpath(data.get('model', ''))
        output_path = os.path.normpath(data.get('output', ''))
        pitch = data.get('pitch', 0)
        index_path = os.path.normpath(data.get('index', '')) if data.get('index') else ""

        if not os.path.exists(input_path) or not os.path.exists(model_path):
            return jsonify({"success": False, "error": "Không tìm thấy file Input hoặc Model"}), 400

        print(f"\n🎤 [RVC] Đang xử lý giọng nói: {os.path.basename(input_path)}")

        # Lệnh gọi RVC CLI (Sử dụng RMVPE để có chất lượng tốt nhất)
        command = [
            sys.executable, __file__, "worker", "cli",
            "-i", input_path,
            "-mp", model_path,
            "-o", output_path,
            "-pi", str(pitch),
            "-me", "rmvpe",      # Thuật toán tốt nhất
            "-d", "cuda:0"       # Chạy bằng GPU
        ]
        
        if index_path and os.path.exists(index_path):
            command.extend(["-ip", index_path, "-ir", "0.75"])

        # Thực thi xử lý
        result = subprocess.run(command, capture_output=True, text=True)
        
        # IN LOG ĐỂ DEBUG (QUAN TRỌNG)
        print("--- RVC DEBUG LOG ---")
        print("STDOUT:", result.stdout)
        print("STDERR:", result.stderr) 
        print("---------------------")

        if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
            print(f"✅ [RVC] Hoàn tất! File lưu tại: {output_path}")
            
            # --- TÙY CHỌN: TỰ ĐỘNG LÀM SẠCH (ENHANCE) NẾU CÓ THƯ VIỆN ---
            # Nếu bạn đã cài resemble-enhance, có thể gọi lệnh ở đây để làm âm thanh trong vắt
            
            return jsonify({
                "success": True, 
                "path": output_path,
                "message": "Đã chuyển đổi giọng nói thành công"
            })
        else:
            print(f"❌ Error: {result.stderr}")
            return jsonify({"success": False, "error": "Xử lý thất bại hoặc file đầu ra trống"}), 500

    except Exception as e:
        traceback.print_exc()
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    print("\n" + "="*50)
    print("🚀 RVC API SERVER - WSL EDITION")
    print("📍 URL: http://127.0.0.1:7890")
    print("🛠️  Hệ thống: " + ("GPU (NVIDIA)" if torch.cuda.is_available() else "CPU (Chậm)"))
    print("="*50 + "\n")
    
    # Chạy trên 0.0.0.0 để Windows có thể gọi vào WSL
    app.run(host='0.0.0.0', port=7890, debug=False)