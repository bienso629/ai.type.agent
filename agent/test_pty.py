import subprocess
import pty
import os

command = ["agy", "--print", "Hãy kể một câu chuyện dài."]
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
        if char == '\n':
            print("STREAM:", repr(buffer))
            buffer = ""
    except Exception as e:
        break
process.wait()
