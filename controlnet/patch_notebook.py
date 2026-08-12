import json
with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

for cell in nb['cells']:
    if cell['cell_type'] == 'code':
        new_source = []
        for line in cell['source']:
            # Replace DreamShaper with AnythingV5
            line = line.replace('DreamShaper_8_pruned.safetensors', 'AnythingV5V3_v5PrtRE.safetensors')
            
            # Inject aria2c download right after aria2 is installed
            new_source.append(line)
            if 'apt-get install -y -qq aria2' in line:
                new_source.append('    print("\\n📥 Đang tải Model Anything V5 chuyên dụng cho 2D/Anime/Vẽ tay...")\n')
                new_source.append('    os.system("aria2c --console-log-level=error -c -x 16 -s 16 -k 1M https://huggingface.co/ckpt/anything-v5.0/resolve/main/AnythingV5V3_v5PrtRE.safetensors -d ./models/checkpoints -o AnythingV5V3_v5PrtRE.safetensors")\n')

        cell['source'] = new_source

with open('comfyui-controlnet-aux.ipynb', 'w') as f:
    json.dump(nb, f, indent=1)
