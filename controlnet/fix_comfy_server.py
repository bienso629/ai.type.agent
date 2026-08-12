import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        if '!python main.py --dont-print-server' in source_str:
            patch_code = """
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
"""
            if "FIX CORS HEADERS TRONG COMFYUI" not in source_str:
                source_str = source_str.replace('# Thực thi server\n!python main.py', patch_code + '\n# Thực thi server\n!python main.py')
            
            lines = []
            for line in source_str.splitlines(True):
                lines.append(line)
            cell['source'] = lines

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
