import json

with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

with open('extracted2.py', 'w') as f:
    for cell in nb['cells']:
        if cell['cell_type'] == 'code':
            for line in cell['source']:
                # Replace ! and % with python comments so py_compile doesn't crash, but indentation is preserved
                if line.strip().startswith('!'):
                    f.write(line.replace('!', '#!'))
                elif line.strip().startswith('%'):
                    f.write(line.replace('%', '#%'))
                else:
                    f.write(line)
            f.write('\n')
