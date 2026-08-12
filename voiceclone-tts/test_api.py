import urllib.request
import urllib.parse
import json
import time

text = "Đêm khuya, tại văn phòng trung tâm dữ liệu của Nam – một CTO trẻ đang quản lý hệ thống máy chủ gánh vác hơn 500 website của các doanh nghiệp lớn nhỏ. Màn hình giám sát bỗng lóe lên những cảnh báo đỏ rực. Một cuộc tấn công tổng lực đang diễn ra."

data = json.dumps({
    "text": text,
    "num_step": 32
}).encode('utf-8')

print("Sending request to port 8981...")
t0 = time.time()
req = urllib.request.Request("http://127.0.0.1:8981/generate_audio_async", data=data, headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req)
resp_data = json.loads(resp.read())
task_id = resp_data["task_id"]
print(f"Task ID: {task_id}")

while True:
    status_resp = urllib.request.urlopen(f"http://127.0.0.1:8981/status/{task_id}")
    status = json.loads(status_resp.read())
    print(f"[{time.time()-t0:.1f}s] Status: {status['status']}")
    if status['status'] in ["done", "error", "cancelled"]:
        break
    time.sleep(1)
    
print(f"Total time: {time.time() - t0:.2f}s")
