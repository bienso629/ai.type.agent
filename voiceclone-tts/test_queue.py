import urllib.request
import urllib.parse
import json
import time
import threading

def fire_request(text, idx):
    data = json.dumps({
        "text": text,
        "num_step": 10
    }).encode('utf-8')
    req = urllib.request.Request("http://localhost:8085/generate_audio_async", data=data, headers={'Content-Type': 'application/json'})
    resp = urllib.request.urlopen(req)
    resp_data = json.loads(resp.read())
    print(f"[Req {idx}] Response: {resp_data}")
    return resp_data["task_id"]

tasks = []
for i in range(3):
    t_id = fire_request(f"Test number {i}", i)
    tasks.append(t_id)

print(f"Tracking tasks: {tasks}")
while True:
    all_done = True
    print("--- Status ---")
    for t_id in tasks:
        status_resp = urllib.request.urlopen(f"http://localhost:8085/status/{t_id}")
        status = json.loads(status_resp.read())
        print(f"Task {t_id}: {status['status']}")
        if status['status'] not in ["done", "error", "cancelled"]:
            all_done = False
    print("--------------")
    if all_done:
        break
    time.sleep(3)
