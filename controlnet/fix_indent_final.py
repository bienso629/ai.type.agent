import json

with open('comfyui-controlnet-aux.ipynb', 'r') as f:
    nb = json.load(f)

for cell in nb['cells']:
    if cell['cell_type'] == 'code':
        new_source = []
        for line in cell['source']:
            # The one we injected for Anything V5
            if 'AnythingV5V3_v5PrtRE.safetensors' in line and 'aria2c' in line:
                # Should have 0 spaces because the apt-get install aria2 before it has 0 spaces
                line = line.lstrip(' ')
            # The one for models_to_download loop
            elif 'aria2c' in line and '{model' in line:
                # Should have 8 spaces indentation inside the `if`
                line = '        ' + line.lstrip(' ')
            
            new_source.append(line)
        cell['source'] = new_source

with open('comfyui-controlnet-aux.ipynb', 'w') as f:
    json.dump(nb, f, indent=1)
