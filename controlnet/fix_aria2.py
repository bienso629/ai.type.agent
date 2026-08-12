import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

download_code = """
import os

print("\\n🚀 [2.5/3] Đang tải các file Model bằng công cụ tăng tốc độ cao (Aria2c)...")

# Cài đặt công cụ tăng tốc độ tải
os.system("apt-get update -qq && apt-get install -y -qq aria2")

models_to_download = [
    {
        "url": "https://huggingface.co/Lykon/DreamShaper/resolve/main/DreamShaper_8_pruned.safetensors",
        "path": "./models/checkpoints/DreamShaper_8_pruned.safetensors",
        "name": "DreamShaper"
    },
    {
        "url": "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.pth",
        "path": "./models/controlnet/control_v11p_sd15_openpose.pth",
        "name": "OpenPose"
    },
    {
        "url": "https://huggingface.co/guoyww/animatediff/resolve/main/mm_sd_v15_v2.ckpt",
        "path": "./custom_nodes/ComfyUI-AnimateDiff-Evolved/models/mm_sd_v15_v2.ckpt",
        "name": "AnimateDiff"
    }
]

os.makedirs("./models/checkpoints", exist_ok=True)
os.makedirs("./models/controlnet", exist_ok=True)
os.makedirs("./custom_nodes/ComfyUI-AnimateDiff-Evolved/models", exist_ok=True)

for model in models_to_download:
    if not os.path.exists(model["path"]):
        print(f"📥 Đang tải {model['name']}...")
        os.system(f"aria2c --console-log-level=error -c -x 16 -s 16 -k 1M {model['url']} -d {os.path.dirname(model['path'])} -o {os.path.basename(model['path'])}")
        print(f"✅ Đã tải xong {model['name']}!")
    else:
        print(f"✅ {model['name']} đã tồn tại, bỏ qua tải xuống.")
"""

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        # Find where the old download code is
        import re
        if 'Đang kiểm tra và tải các file Model còn thiếu' in source_str:
            start_idx = source_str.find('print("\\n🚀 [2.5/3]')
            end_idx = source_str.find('print("\\n🚀 [3/3]')
            if start_idx != -1 and end_idx != -1:
                new_source_str = source_str[:start_idx] + download_code + "\n" + source_str[end_idx:]
                
                lines = []
                for line in new_source_str.splitlines(True):
                    lines.append(line)
                cell['source'] = lines

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
