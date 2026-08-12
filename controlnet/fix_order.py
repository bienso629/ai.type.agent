import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

cell3 = nb['cells'][2]
source = "".join(cell3['source'])

# Extract symlink code
symlink_code_start = "# === TỰ ĐỘNG SYMLINK MODEL TỪ DATASET KAGGLE ==="
symlink_code_end = "else:\n    print(\"❌ Không tìm thấy model nào trong thư mục Input!\")\n"

s_idx = source.find(symlink_code_start)
e_idx = source.find(symlink_code_end) + len(symlink_code_end)

symlink_block = source[s_idx:e_idx]

# Remove from current pos
source = source.replace(symlink_block, "")

# Insert BEFORE aria2c (before models_to_download)
target_pos = source.find("models_to_download = [")
source = source[:target_pos] + symlink_block + "\n" + source[target_pos:]

cell3['source'] = [line + '\n' for line in source.split('\n') if line]

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
