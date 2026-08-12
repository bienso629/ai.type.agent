import subprocess
import time
import urllib.request
import json

log_file = open("mineru_api_test.log", "w", encoding="utf-8")
print("Starting mineru_api.exe...")
p = subprocess.Popen(["mineru_api.exe"], stdout=log_file, stderr=log_file)

time.sleep(5) # Wait for startup

print("Sending /load_model...")
try:
    req = urllib.request.Request("http://127.0.0.1:48921/load_model", method="POST")
    with urllib.request.urlopen(req) as response:
        print(response.read().decode())
except Exception as e:
    print(f"Error: {e}")

time.sleep(2) # Let it log any exceptions
p.terminate()
log_file.close()
print("Done. Check mineru_api_test.log")
