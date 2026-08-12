import json

notebook_path = '/home/yenai/Documents/Projects/Typing/apps/controlnet/comfyui-controlnet-aux.ipynb'

with open(notebook_path, 'r', encoding='utf-8') as f:
    nb = json.load(f)

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        # Iterate over source lines and fix the unterminated string
        for i, line in enumerate(source):
            if 'print("✅ Đã tạo xong Custom API cho Storyboard!\n' in line:
                source[i] = line.replace('print("✅ Đã tạo xong Custom API cho Storyboard!\n', 'print("✅ Đã tạo xong Custom API cho Storyboard!\\n')
            elif line == '")\n' and i > 0 and 'Custom API' in source[i-1]:
                # It might have been split into two lines
                pass
                
        # Better approach: just join the whole source, fix it, and resplit
        source_str = "".join(source)
        source_str = source_str.replace('print("✅ Đã tạo xong Custom API cho Storyboard!\n")\n', 'print("✅ Đã tạo xong Custom API cho Storyboard!\\n")\n')
        # In case the newline is just \n without trailing quote on same line
        source_str = source_str.replace('print("✅ Đã tạo xong Custom API cho Storyboard!\n\n")\n', 'print("✅ Đã tạo xong Custom API cho Storyboard!\\n")\n')
        
        # Another possibility based on screenshot:
        # print("✅ Đã tạo xong Custom API cho Storyboard!\n
        # ")
        source_str = source_str.replace('print("✅ Đã tạo xong Custom API cho Storyboard!\n")\n# Thực thi server', 'print("✅ Đã tạo xong Custom API cho Storyboard!\\n")\n# Thực thi server')
        
        # Just to be completely safe, let's replace any instance of that exact broken print
        bad_print = 'print("✅ Đã tạo xong Custom API cho Storyboard!\n")'
        good_print = 'print("✅ Đã tạo xong Custom API cho Storyboard!\\n")'
        if bad_print in source_str:
            source_str = source_str.replace(bad_print, good_print)
            
        # Re-split into lines keeping \n
        lines = []
        for line in source_str.splitlines(True):
            lines.append(line)
        cell['source'] = lines

with open(notebook_path, 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)

print("Notebook fixed!")
