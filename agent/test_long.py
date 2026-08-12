import subprocess
import time

command = ["agy", "--print", "Hãy viết một bài văn 500 chữ về chủ đề môi trường"]

process = subprocess.Popen(
    command,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1
)

buffer = ""
start = time.time()
while True:
    char = process.stdout.read(1)
    if not char: break
    buffer += char
    if len(buffer) == 10:
        print(f"[{time.time() - start:.2f}s] CHUNK: {repr(buffer)}")
        buffer = ""
process.wait()
