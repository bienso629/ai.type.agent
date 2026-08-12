import subprocess
import os

command = ["stdbuf", "-o0", "agy", "--print", "Hello world in 5 words"]

process = subprocess.Popen(
    command,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1
)

buffer = ""
while True:
    char = process.stdout.read(1)
    if not char: break
    buffer += char
    if len(buffer) == 5:
        print("CHUNK:", repr(buffer))
        buffer = ""
process.wait()
