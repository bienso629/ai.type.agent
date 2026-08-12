

import os
import time
import threading
from pyngrok import ngrok, conf
# === THÔNG TIN NGROK CỦA BẠN ===
NGROK_TOKEN = "2wXfTcuQiOhQ6W9NBFuiE5mDaAm_3kBgThUHcckP27TDFLwyi"
STATIC_DOMAIN = "pangolin-innocent-especially.ngrok-free.app"
print("🚀 [1/3] Đang dựng cấu trúc thư mục ComfyUI...")
if not os.path.exists("/kaggle/working/ComfyUI/main.py"):
# Cài đặt thư viện lõi nếu chưa có
print("\n🚀 [2/3] Đang quét và thiết lập liên kết ảo (Symlink) từ Dataset...")
# Clone Custom Nodes nếu chưa có
if not os.path.exists("./custom_nodes/ComfyUI-AnimateDiff-Evolved"):
if not os.path.exists("./custom_nodes/comfyui_controlnet_aux"):
import os
import os
print("\n🚀 [2.5/3] Đang tải các file Model bằng công cụ tăng tốc độ cao (Aria2c)...")
# Cài đặt công cụ tăng tốc độ tải
os.system("apt-get update -qq && apt-get install -y -qq aria2")
print("\n📥 Đang tải Model Anything V5 chuyên dụng cho 2D/Anime/Vẽ tay...")
os.system("aria2c --console-log-level=error -c -x 16 -s 16 -k 1M https://huggingface.co/ckpt/anything-v5.0/resolve/main/AnythingV5V3_v5PrtRE.safetensors -d ./models/checkpoints -o AnythingV5V3_v5PrtRE.safetensors")
# === TỰ ĐỘNG SYMLINK MODEL TỪ DATASET KAGGLE ===
print("\n🔍 Đang tìm kiếm file model trong Kaggle Input...")
import glob
files = glob.glob("/kaggle/input/**/*.safetensors", recursive=True)
if files:
    model_file = files[0]
    dest = "/kaggle/working/ComfyUI/models/checkpoints/dataset_model.safetensors"
    if os.path.exists(dest):
        os.remove(dest)
    os.symlink(model_file, dest)
    print(f"✅ Đã kết nối tự động thành công!\nTừ: {model_file}\nĐến: {dest}")
else:
    print("❌ Không tìm thấy model nào trong thư mục Input!")
models_to_download = [
    {
        "url": "https://huggingface.co/ckpt/anything-v5.0/resolve/main/AnythingV5V3_v5PrtRE.safetensors",
        "path": "./models/checkpoints/AnythingV5V3_v5PrtRE.safetensors",
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
print("\n🚀 [3/3] Kích hoạt cổng kết nối Ngrok và chạy Server...")
conf.get_default().auth_token = NGROK_TOKEN
def start_ngrok():
    time.sleep(12) # Chờ server local ổn định
    try:
        public_url = ngrok.connect(8188, domain=STATIC_DOMAIN).public_url
        print("\n" + "★"*65)
        print(f"✅ TRUY CẬP GIAO DIỆN COMFYUI TẠI: {public_url}")
        print("★"*65 + "\n")
    except Exception as e:
        print(f"\n❌ Đường truyền ngrok thất bại: {e}")
threading.Thread(target=start_ngrok, daemon=True).start()
# === BỔ SUNG CUSTOM API CHO STORYBOARD ===
print("\n🚀 Đang cài đặt Custom API cho Storyboard...")
api_dir = "./custom_nodes/StoryboardAPI"
if not os.path.exists(api_dir):
    os.makedirs(api_dir)
api_code = '''
import uuid
import json
import aiohttp
from server import PromptServer
from aiohttp import web
# CORS headers
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Allow-Headers": "*",
}
# Một workflow txt2img mẫu của ComfyUI
def get_workflow(prompt):
    return {
        "3": {
            "inputs": {
                "seed": 123456789,
                "steps": 20,
                "cfg": 8.0,
                "sampler_name": "euler",
                "scheduler": "normal",
                "denoise": 1.0,
                "model": [ "4", 0 ],
                "positive": [ "6", 0 ],
                "negative": [ "7", 0 ],
                "latent_image": [ "5", 0 ]
            },
            "class_type": "KSampler"
        },
        "4": {
            "inputs": { "ckpt_name": "AnythingV5V3_v5PrtRE.safetensors" },
            "class_type": "CheckpointLoaderSimple"
        },
        "5": {
            "inputs": { "width": 512, "height": 512, "batch_size": 1 },
            "class_type": "EmptyLatentImage"
        },
        "6": {
            "inputs": { "text": prompt, "clip": [ "4", 1 ] },
            "class_type": "CLIPTextEncode"
        },
        "7": {
            "inputs": { "text": "text, watermark, low quality, bad anatomy", "clip": [ "4", 1 ] },
            "class_type": "CLIPTextEncode"
        },
        "8": {
            "inputs": { "samples": [ "3", 0 ], "vae": [ "4", 2 ] },
            "class_type": "VAEDecode"
        },
        "9": {
            "inputs": { "filename_prefix": "storyboard", "images": [ "8", 0 ] },
            "class_type": "SaveImage"
        }
    }
storyboard_jobs = {}
@PromptServer.instance.routes.options("/api/storyboard")
async def storyboard_options(request):
    return web.Response(headers=CORS_HEADERS)
@PromptServer.instance.routes.options("/api/storyboard/{job_id}")
async def storyboard_status_options(request):
    return web.Response(headers=CORS_HEADERS)
@PromptServer.instance.routes.post("/api/storyboard")
async def generate_storyboard(request):
    data = await request.json()
    prompts = data.get("prompts", [])
    job_id = str(uuid.uuid4())
    storyboard_jobs[job_id] = {
        "status": "processing",
        "total": len(prompts),
        "completed": 0,
        "results": [],
        "prompt_ids": []
    }
    async with aiohttp.ClientSession() as session:
        for prompt in prompts:
            workflow = get_workflow(prompt)
            async with session.post("http://127.0.0.1:8188/prompt", json={"prompt": workflow}) as response:
                res_data = await response.json()
                prompt_id = res_data.get("prompt_id")
                if prompt_id:
                    storyboard_jobs[job_id]["prompt_ids"].append(prompt_id)
    return web.json_response({"job_id": job_id, "status": "processing", "expected_images": len(prompts)}, headers=CORS_HEADERS)
@PromptServer.instance.routes.get("/api/storyboard/{job_id}")
async def get_storyboard_status(request):
    job_id = request.match_info.get("job_id")
    if job_id not in storyboard_jobs:
        return web.json_response({"error": "Job not found"}, status=404, headers=CORS_HEADERS)
    job = storyboard_jobs[job_id]
    completed_count = 0
    results = []
    async with aiohttp.ClientSession() as session:
        async with session.get("http://127.0.0.1:8188/history") as response:
            history = await response.json()
        for pid in job["prompt_ids"]:
            if pid in history:
                completed_count += 1
                outputs = history[pid].get("outputs", {})
                if "9" in outputs and "images" in outputs["9"]:
                    for img in outputs["9"]["images"]:
                        img_url = f"/view?filename={img['filename']}&subfolder={img['subfolder']}&type={img['type']}"
                        results.append(img_url)
    job["completed"] = completed_count
    job["results"] = results
    if completed_count == job["total"]:
        job["status"] = "completed"
    return web.json_response(job, headers=CORS_HEADERS)
NODE_CLASS_MAPPINGS = {}
'''
with open(f"{api_dir}/__init__.py", "w", encoding="utf-8") as f:
    f.write(api_code)
print("✅ Đã tạo xong Custom API cho Storyboard!")
# Thực thi server
# === FIX CORS HEADERS TRONG COMFYUI ===
import os
import re
server_py_path = "/kaggle/working/ComfyUI/server.py"
if os.path.exists(server_py_path):
    with open(server_py_path, 'r', encoding='utf-8') as f:
        content = f.read()
    # Sửa Content-Type, Authorization thành * để cho phép ngrok-skip-browser-warning
    content = content.replace("'Content-Type, Authorization'", "'*'")
    with open(server_py_path, 'w', encoding='utf-8') as f:
        f.write(content)
# Thực thi server

