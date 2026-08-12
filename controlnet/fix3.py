import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        for i, line in enumerate(source):
            if 'Đang cài đặt Custom API cho Storyboard...' in line:
                source[i] = 'print("\\n🚀 Đang cài đặt Custom API cho Storyboard...")\n'
            elif line.strip() == '")' and i > 0 and 'Đang cài đặt Custom API' in source[i-1]:
                source[i] = ''
            elif '!python main.py --dont-prin' in line:
                source[i] = ''
                
with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
