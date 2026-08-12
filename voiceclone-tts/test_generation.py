import urllib.request
import urllib.parse
import json
import time

data = json.dumps({
    "text": "Xin chào, đây là thử nghiệm.",
    "num_step": 16
}).encode('utf-8')

req = urllib.request.Request("http://localhost:8085/generate_audio_async", data=data, headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req)
resp_data = json.loads(resp.read())
print("Response:", resp_data)
task_id = resp_data["task_id"]

for _ in range(30):
    time.sleep(2)
    status_resp = urllib.request.urlopen(f"http://localhost:8085/status/{task_id}")
    status = json.loads(status_resp.read())
    print("Status:", status)
    if status["status"] in ["done", "error", "cancelled"]:
        break

