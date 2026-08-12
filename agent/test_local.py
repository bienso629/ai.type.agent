import requests
import json
import base64
import time

url = "http://127.0.0.1:54321/api/chat"
headers = {"x-api-key": "381986yennguyeN"}
data = {
    "prompt": "Hãy dùng python mở ứng dụng calculator bằng thư viện subprocess. KHÔNG giải thích.",
    "system_instructions": "Bạn là AI. Chỉ dùng bash để thao tác.",
    "model": "gemini-3.6-flash"
}
try:
    response = requests.post(url, headers=headers, data=data, stream=True)
    for line in response.iter_lines():
        if line:
            print(line.decode('utf-8'))
except Exception as e:
    print("Error:", e)
