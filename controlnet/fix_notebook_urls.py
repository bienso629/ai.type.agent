import json

with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

for cell in nb['cells']:
    if cell['cell_type'] == 'code':
        new_source = []
        for line in cell['source']:
            # Fix the broken DreamShaper URL
            if 'https://huggingface.co/Lykon/DreamShaper/resolve/main/AnythingV5V3_v5PrtRE.safetensors' in line:
                line = line.replace('https://huggingface.co/Lykon/DreamShaper/resolve/main/AnythingV5V3_v5PrtRE.safetensors', 'https://huggingface.co/ckpt/anything-v5.0/resolve/main/AnythingV5V3_v5PrtRE.safetensors')
            
            # Remove the symlink block that overwrites AnythingV5
            if 'dest = "/kaggle/working/ComfyUI/models/checkpoints/AnythingV5V3_v5PrtRE.safetensors"' in line:
                line = '    dest = "/kaggle/working/ComfyUI/models/checkpoints/dataset_model.safetensors"\n'
            
            new_source.append(line)
        cell['source'] = new_source

with open('comfyui-controlnet-aux.ipynb', 'w') as f:
    json.dump(nb, f, indent=1)
