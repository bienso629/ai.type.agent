import subprocess, os, re, time

# Cai thu vien nhanh neu thieu
for pkg in ["pymupdf", "pypdf", "faiss-gpu", "sentence-transformers"]:
    subprocess.run(f"pip install -q {pkg}", shell=True)

# Tai cloudflared
if subprocess.run("which cloudflared", shell=True, capture_output=True).returncode != 0:
    subprocess.run("curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared", shell=True)

# Ghi file server doc lap
server_code = open('/home/yenai/Documents/Projects/Typing/apps/plugins/colab/colab_mineru_mcp.py', 'r').read()
with open('/tmp/server.py', 'w') as f:
    f.write(server_code)

# Chay nohup server & cloudflare
subprocess.run("pkill -9 -f 'uvicorn.*8000'; pkill -9 cloudflared", shell=True)
if os.path.exists('/tmp/cf.log'): os.remove('/tmp/cf.log')

subprocess.Popen("nohup python3 /tmp/server.py > /tmp/server.log 2>&1 &", shell=True)

for i in range(25):
    time.sleep(1)
    if os.path.exists('/tmp/cf.log'):
        match = re.search(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", open('/tmp/cf.log').read())
        if match:
            print("COLAB_READY:" + match.group(0))
            break
