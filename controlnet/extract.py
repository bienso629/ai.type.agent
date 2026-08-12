import json

with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

with open('extracted.py', 'w') as f:
    for cell in nb['cells']:
        if cell['cell_type'] == 'code':
            for line in cell['source']:
                if not line.strip().startswith('!') and not line.strip().startswith('%'):
                    f.write(line)
            f.write('\n')
