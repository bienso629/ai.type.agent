# start.py
# -*- coding: utf-8 -*-
import sys, os, socket, time, threading, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def check_port_in_use(port: int, host: str = "127.0.0.1") -> bool:
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.25)
        return s.connect_ex((host, port)) == 0

def stream_output(proc: subprocess.Popen, name: str):
    def _forward(stream, is_err=False):
        for line in iter(stream.readline, ""):
            if not line:
                break
            prefix = f"[{name}] "
            try:
                print(prefix + line.rstrip("\n"), flush=True, file=(sys.stderr if is_err else sys.stdout))
            except Exception:
                # dự phòng
                try:
                    safe = line.encode("utf-8", "ignore").decode("utf-8", "ignore").rstrip("\n")
                    print(prefix + safe, flush=True, file=(sys.stderr if is_err else sys.stdout))
                except Exception:
                    pass
        stream.close()

    t1 = threading.Thread(target=_forward, args=(proc.stdout, False), daemon=True)
    t2 = threading.Thread(target=_forward, args=(proc.stderr, True), daemon=True)
    t1.start(); t2.start()
    return t1, t2

def start_process(cmd, name, extra_env=None):
    env = os.environ.copy()
    # ép stdout/stderr Python của tiến trình con dùng UTF-8
    env["PYTHONIOENCODING"] = "UTF-8"
    env["PYTHONUTF8"] = "1"
    if extra_env:
        env.update(extra_env)
    print(f"Starting {name}: {' '.join(cmd)}")
    return subprocess.Popen(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",   # đọc UTF-8 từ pipe
        errors="replace",   # tránh vỡ khi gặp ký tự lạ
        bufsize=1,
        env=env
    )

def main():
    py = sys.executable
    env_file = ROOT / ".env"

    jobs = [
        {
            "name": "chatbot",
            "cmd": [py, "-m", "uvicorn", "chatbot:app", "--host", "0.0.0.0", "--port", "8002"],
            "env": None,
            "port": 8002
        },
        {
            "name": "website",
            "cmd": [py, "-m", "uvicorn", "website:app", "--host", "0.0.0.0", "--port", "8003"],
            # Bạn có thể truyền domain qua env nếu muốn:
            # "env": {"WEBSITE_SELECTED_DOMAINS": '["huyenthuyen.vn","olangvien.vn"]'},
            "env": None,
            "port": 8003
        },
    ]

    busy = [j for j in jobs if check_port_in_use(j["port"])]
    if busy:
        print("⚠️  Một số cổng đã bận:")
        for j in busy: print(f"   - {j['name']} -> {j['port']}")
        print("Vẫn tiếp tục khởi động các app khác...\n")

    procs = []
    try:
        for j in jobs:
            p = start_process(j["cmd"], j["name"], extra_env=j["env"])
            procs.append((j["name"], p))
            stream_output(p, j["name"])
            time.sleep(0.3)

        print("\nTất cả tiến trình đã khởi chạy. Nhấn Ctrl+C để tắt.")
        while any(p.poll() is None for _, p in procs):
            time.sleep(0.8)

    except KeyboardInterrupt:
        print("\nĐang dừng các tiến trình...")
    finally:
        for name, p in procs:
            if p.poll() is None:
                try:
                    print(f"Terminating {name} (pid={p.pid})")
                    p.terminate()
                except Exception:
                    pass
        time.sleep(1.0)
        for name, p in procs:
            if p.poll() is None:
                try:
                    print(f"Killing {name} (pid={p.pid})")
                    p.kill()
                except Exception:
                    pass
        print("Done.")

if __name__ == "__main__":
    main()
