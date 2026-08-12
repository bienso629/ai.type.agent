import json
import re

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        if 'api_code = ' in source_str:
            new_api_code = """
import uuid
import json
import urllib.request
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
            "inputs": { "ckpt_name": "DreamShaper_8_pruned.safetensors" },
            "class_type": "CheckpointLoaderSimple"
        },
        "5": {
            "inputs": { "width": 512, "height": 512, "batch_size": 1 },
            "class_type": "EmptyLatentImage"
        },
        "6": {
            "inputs": { "text": "masterpiece, best quality, " + prompt },
            "class_type": "CLIPTextEncode"
        },
        "7": {
            "inputs": { "text": "text, watermark, low quality, bad anatomy" },
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

    for prompt in prompts:
        workflow = get_workflow(prompt)
        req = urllib.request.Request("http://127.0.0.1:8188/prompt", data=json.dumps({"prompt": workflow}).encode('utf-8'), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read())
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

    req = urllib.request.Request("http://127.0.0.1:8188/history")
    with urllib.request.urlopen(req) as response:
        history = json.loads(response.read())

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
"""
            start_idx = source_str.find("api_code = '''")
            end_idx = source_str.find("with open(f\"{api_dir}/__init__.py\"")
            
            if start_idx != -1 and end_idx != -1:
                source_str = source_str[:start_idx] + "api_code = '''" + new_api_code + "'''\n\n" + source_str[end_idx:]
                
            lines = []
            for line in source_str.splitlines(True):
                lines.append(line)
            cell['source'] = lines

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
