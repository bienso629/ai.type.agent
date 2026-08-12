import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        if '!python main.py --dont-print-server' in source_str:
            if '--enable-cors-header' not in source_str:
                source_str = source_str.replace('!python main.py --dont-print-server', '!python main.py --dont-print-server --enable-cors-header "*"')
            
            lines = []
            for line in source_str.splitlines(True):
                lines.append(line)
            cell['source'] = lines

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
