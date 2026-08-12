import json

with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

for cell in nb['cells']:
    if cell['cell_type'] == 'code':
        new_source = []
        for line in cell['source']:
            if 'Đang tải Model Anything V5' in line:
                line = line.lstrip(' ')
            if 'aria2c --console-log-level=error' in line:
                line = line.lstrip(' ')
            new_source.append(line)
        cell['source'] = new_source

with open('comfyui-controlnet-aux.ipynb', 'w') as f:
    json.dump(nb, f, indent=1)
