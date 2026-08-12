import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        # Thêm thư viện aiohttp-cors
        if '!pip install -r requirements.txt -q' in source_str:
            source_str = source_str.replace('!pip install -r requirements.txt -q', '!pip install -r requirements.txt aiohttp-cors -q')
            
        # Thêm CORS vào endpoint API
        if '@PromptServer.instance.routes.post("/api/storyboard")' in source_str:
            api_code_fix = '''
import uuid
import json
import urllib.request
from server import PromptServer
from aiohttp import web
import aiohttp_cors

# Bật CORS cho API
cors = aiohttp_cors.setup(PromptServer.instance.app, defaults={
    "*": aiohttp_cors.ResourceOptions(
        allow_credentials=True,
        expose_headers="*",
        allow_headers="*",
    )
})

# Lưu kết quả
storyboard_jobs = {}
'''
            source_str = source_str.replace('''
import uuid
import json
import urllib.request
from server import PromptServer
from aiohttp import web

# Một workflow txt2img mẫu của ComfyUI''', api_code_fix + '''
# Một workflow txt2img mẫu của ComfyUI''')

            # Áp dụng CORS vào route POST
            source_str = source_str.replace('@PromptServer.instance.routes.post("/api/storyboard")', 'route = PromptServer.instance.routes.post("/api/storyboard")\ncors.add(route)')
            
            # Áp dụng CORS vào route GET
            source_str = source_str.replace('@PromptServer.instance.routes.get("/api/storyboard/{job_id}")', 'route_get = PromptServer.instance.routes.get("/api/storyboard/{job_id}")\ncors.add(route_get)')
        
        lines = []
        for line in source_str.splitlines(True):
            lines.append(line)
        cell['source'] = lines

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
