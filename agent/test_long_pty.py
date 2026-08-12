import subprocess
import time
import pty
import os

command = ["agy", "--print", "Hãy viết một bài văn 500 chữ về chủ đề môi trường"]
master, slave = pty.openpty()

process = subprocess.Popen(
    command,
    stdout=slave,
    stderr=slave,
    text=True,
    close_fds=True
)
os.close(slave)

buffer = ""
start = time.time()
while True:
    try:
        char = os.read(master, 1).decode('utf-8', errors='ignore')
        if not char: break
        buffer += char
        if len(buffer) == 10:
            print(f"[{time.time() - start:.2f}s] CHUNK: {repr(buffer)}")
            buffer = ""
    except Exception:
        break
process.wait()
