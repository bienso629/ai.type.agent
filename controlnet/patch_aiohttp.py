import json

with open('comfyui-controlnet-aux.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

# Find cell 3 (index 2)
cell3 = nb['cells'][2]
source = "".join(cell3['source'])

# Replace urllib imports and usages
source = source.replace("import urllib.request", "import aiohttp")

post_old = """    for prompt in prompts:
        workflow = get_workflow(prompt)
        req = urllib.request.Request("http://127.0.0.1:8188/prompt", data=json.dumps({"prompt": workflow}).encode('utf-8'), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read())
            prompt_id = res_data.get("prompt_id")
            if prompt_id:
                storyboard_jobs[job_id]["prompt_ids"].append(prompt_id)"""

post_new = """    async with aiohttp.ClientSession() as session:
        for prompt in prompts:
            workflow = get_workflow(prompt)
            async with session.post("http://127.0.0.1:8188/prompt", json={"prompt": workflow}) as response:
                res_data = await response.json()
                prompt_id = res_data.get("prompt_id")
                if prompt_id:
                    storyboard_jobs[job_id]["prompt_ids"].append(prompt_id)"""

source = source.replace(post_old, post_new)

get_old = """    req = urllib.request.Request("http://127.0.0.1:8188/history")
    with urllib.request.urlopen(req) as response:
        history = json.loads(response.read())"""

get_new = """    async with aiohttp.ClientSession() as session:
        async with session.get("http://127.0.0.1:8188/history") as response:
            history = await response.json()"""

source = source.replace(get_old, get_new)

# Re-write the cell source
cell3['source'] = [line + '\n' for line in source.split('\n') if line]

with open('comfyui-controlnet-aux.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)
print("PATCH_SUCCESS")
