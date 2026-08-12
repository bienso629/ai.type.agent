import json

with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

for cell in nb['cells']:
    if cell['cell_type'] == 'code':
        source = cell['source']
        for i, line in enumerate(source):
            if line.startswith('os.system(f"aria2c --console-log-level=error -c -x 16 -s 16 -k 1M {model[\'url\']}'):
                source[i] = '        ' + line.lstrip()
            if 'print(f"✅ Đã tải xong {model[\'name\']}!")' in line:
                source[i] = '        ' + line.lstrip()

with open('comfyui-controlnet-aux.ipynb', 'w') as f:
    json.dump(nb, f, indent=1)
