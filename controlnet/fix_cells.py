import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

for i, cell in enumerate(nb.get('cells', [])):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        source_str = "".join(source)
        
        # Remove any occurrence of the command from ALL cells first
        source_str = source_str.replace("!python main.py --dont-print-server\n", "")
        source_str = source_str.replace("!python main.py --dont-print-server", "")
        
        # Only add it to the LAST code cell (which is cell index 2, technically the 3rd cell, but let's just append to the specific cell that contains 'Đã tạo xong Custom API')
        if 'Đã tạo xong Custom API' in source_str:
            source_str = source_str.strip() + "\n\n# Thực thi server\n!python main.py --dont-print-server\n"
            
        lines = []
        for line in source_str.splitlines(True):
            lines.append(line)
        cell['source'] = lines
        
with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
