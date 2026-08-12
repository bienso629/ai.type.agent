import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

cell3 = nb['cells'][2]
source = "".join(cell3['source'])

# Replace the CLIPTextEncode nodes
old_6 = """        "6": {
            "inputs": { "text": "masterpiece, best quality, " + prompt },
            "class_type": "CLIPTextEncode"
        },"""

new_6 = """        "6": {
            "inputs": { "text": "masterpiece, best quality, " + prompt, "clip": [ "4", 1 ] },
            "class_type": "CLIPTextEncode"
        },"""

old_7 = """        "7": {
            "inputs": { "text": "text, watermark, low quality, bad anatomy" },
            "class_type": "CLIPTextEncode"
        },"""

new_7 = """        "7": {
            "inputs": { "text": "text, watermark, low quality, bad anatomy", "clip": [ "4", 1 ] },
            "class_type": "CLIPTextEncode"
        },"""

source = source.replace(old_6, new_6)
source = source.replace(old_7, new_7)

cell3['source'] = [line + '\n' for line in source.split('\n') if line]

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
