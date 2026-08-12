import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        # Replace the condition to check for main.py instead of just the folder
        source_str = source_str.replace('if not os.path.exists("/kaggle/working/ComfyUI"):', 'if not os.path.exists("/kaggle/working/ComfyUI/main.py"):')
        
        # Also clean up the directory if it's empty/broken before cloning
        clone_fix = """if not os.path.exists("/kaggle/working/ComfyUI/main.py"):
    !rm -rf /kaggle/working/ComfyUI
    !git clone https://github.com/comfyanonymous/ComfyUI /kaggle/working/ComfyUI -q"""
        source_str = source_str.replace("""if not os.path.exists("/kaggle/working/ComfyUI/main.py"):
    !git clone https://github.com/comfyanonymous/ComfyUI /kaggle/working/ComfyUI -q""", clone_fix)
        
        lines = []
        for line in source_str.splitlines(True):
            lines.append(line)
        cell['source'] = lines

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
