import subprocess
import pty
import os

command = ["agy", "--print", "Hello world in 5 words"]
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
while True:
    try:
        char = os.read(master, 1).decode('utf-8', errors='ignore')
        if not char: break
        buffer += char
        if len(buffer) == 5:
            print("CHUNK:", repr(buffer))
            buffer = ""
    except Exception as e:
        break
process.wait()
