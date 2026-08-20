import os
import sys
import json
import time
import requests

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

def load_config():
    default_cfg = {
        "server_ip": "192.168.1.100",
        "ssh_user": "root",
        "ssh_pass": "",
        "ssh_port": 22,
        "proxy_api_key": "sk-or-v1-...",
        "proxy_base_url": "https://openrouter.ai/api/v1",
        "ai_model": "glm-5.3",
        "remote_work_dir": "/opt/ai_agent",
        "api_port": 8000,
        "secret_token": "super_secret_token_123"
    }
    if not os.path.exists(CONFIG_FILE):
        return default_cfg
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return {**default_cfg, **json.load(f)}
    except Exception:
        return default_cfg

cfg = load_config()
SERVER_IP = cfg.get("server_ip", "192.168.1.100")
SSH_USER = cfg.get("ssh_user", "root")
SSH_PASS = cfg.get("ssh_pass", "")
SSH_PORT = int(cfg.get("ssh_port", 22))

PROXY_API_KEY = cfg.get("proxy_api_key", "")
PROXY_BASE_URL = cfg.get("proxy_base_url", "https://openrouter.ai/api/v1")
AI_MODEL = cfg.get("ai_model", "glm-5.3")

REMOTE_WORK_DIR = cfg.get("remote_work_dir", "/opt/ai_agent")
LOCAL_SCRIPT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ai_agent_service.py")

API_PORT = int(cfg.get("api_port", 8000))
SECRET_TOKEN = cfg.get("secret_token", "super_secret_token_123")

def get_ssh_client():
    try:
        import paramiko
    except ImportError:
        print("❌ Lỗi: Thư viện paramiko chưa được cài đặt. Hãy chạy: pip install paramiko")
        return None
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(SERVER_IP, port=SSH_PORT, username=SSH_USER, password=SSH_PASS or None, timeout=10)
    return ssh

# ==========================================
# 1. HÀM DEPLOY QUA SFTP
# ==========================================
def deploy_ai_agent():
    """Tự động upload file code từ máy tính lên Server qua SFTP."""
    try:
        print(f"🔄 Đang kết nối SSH tới {SERVER_IP}:{SSH_PORT}...")
        ssh = get_ssh_client()
        if not ssh: return
        
        print(f"📁 Tạo thư mục đích: {REMOTE_WORK_DIR}...")
        ssh.exec_command(f"mkdir -p {REMOTE_WORK_DIR}")
        
        sftp = ssh.open_sftp()
        filename = "ai_agent_service.py"
        remote_path = f"{REMOTE_WORK_DIR}/{filename}"
        
        print(f"📤 Đang tải lên: {LOCAL_SCRIPT_PATH} ➔ {remote_path}...")
        sftp.put(LOCAL_SCRIPT_PATH, remote_path)
        
        sftp.chmod(remote_path, 0o755)
        print("✅ Upload mã nguồn hoàn tất thành công!")
        sftp.close()
        ssh.close()
    except Exception as e:
        print(f"❌ Lỗi Deploy: {e}")

# ==========================================
# 2. HÀM CẤU HÌNH SYSTEMD
# ==========================================
def install_systemd_service():
    try:
        ssh = get_ssh_client()
        if not ssh: return
        
        print("📦 Đang kiểm tra & tự động cài đặt thư viện cần thiết trên máy chủ...")
        stdin, stdout, stderr = ssh.exec_command("pip3 install fastapi uvicorn openai requests 2>&1 || python3 -m pip install fastapi uvicorn openai requests 2>&1")
        stdout.read()
        
        service_content = f"""[Unit]
Description=Tadu Cloud AI Agent Service (GLM-5.3)
After=network.target

[Service]
User={SSH_USER}
WorkingDirectory={REMOTE_WORK_DIR}
Environment="PROXY_API_KEY={PROXY_API_KEY}"
Environment="PROXY_BASE_URL={PROXY_BASE_URL}"
Environment="AI_MODEL={AI_MODEL}"
Environment="SECRET_TOKEN={SECRET_TOKEN}"
ExecStart=/usr/bin/python3 -m uvicorn ai_agent_service:app --host 0.0.0.0 --port {API_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
"""
        setup_cmd = f"""
        sudo bash -c 'cat << "EOF" > /etc/systemd/system/ai-agent.service\n{service_content}\nEOF'
        sudo systemctl daemon-reload
        sudo systemctl enable ai-agent
        sudo systemctl restart ai-agent
        """
        print("⚙️ Đang ghi cấu hình Systemd...")
        ssh.exec_command(setup_cmd)
        time.sleep(2)
        print("✅ Ghi cấu hình và khởi động Systemd thành công!")
        ssh.close()
    except Exception as e:
        print(f"❌ Lỗi cấu hình Systemd: {e}")

# ==========================================
# 3. HÀM ĐIỀU KHIỂN BẬT/TẮT AI AGENT
# ==========================================
def control_agent(action):
    try:
        ssh = get_ssh_client()
        if not ssh: return
        stdin, stdout, stderr = ssh.exec_command(f"sudo systemctl {action} ai-agent")
        err = stderr.read().decode().strip()
        out = stdout.read().decode().strip()
        if err and "Created symlink" not in err:
            print(f"⚠️ Thông báo: {err}")
        else:
            print(f"✅ Đã thực thi '{action}' cho AI Agent!")
        if out:
            print(f"Kết quả:\n{out}")
        ssh.close()
    except Exception as e:
        print(f"❌ Lỗi: {e}")

# ==========================================
# 4. GIAO DIỆN CHAT CLI
# ==========================================
def chat_loop():
    url = f"http://{SERVER_IP}:{API_PORT}/ai_agent"
    headers = {"x-api-token": SECRET_TOKEN}
    
    print("\n" + "="*50)
    print(f"🤖 CHAT VỚI AI AGENT ({AI_MODEL}) - {SERVER_IP}:{API_PORT}")
    print("Gõ 'exit' để thoát chat, AI vẫn chạy ngầm.")
    print("="*50 + "\n")
    
    while True:
        try:
            user_msg = input("Bạn: ")
        except (KeyboardInterrupt, EOFError):
            break
        if user_msg.lower() == 'exit':
            break
        if not user_msg.strip():
            continue
            
        print("⏳ AI đang xử lý...")
        try:
            res = requests.post(url, json={"message": user_msg}, headers=headers, timeout=120)
            if res.status_code == 200:
                data = res.json()
                if data.get("tool_calls"):
                    for tc in data["tool_calls"]:
                        print(f"\n[⚡ LỆNH TERMINAL ĐÃ CHẠY]: {tc.get('command')}")
                        print(f"[KẾT QUẢ]: {tc.get('output')}\n")
                print(f"AI ({AI_MODEL}): {data.get('reply')}\n")
            else:
                print(f"Lỗi {res.status_code}: {res.text}\n")
        except Exception as e:
            print(f"❌ Lỗi kết nối (Server đã bật chưa?): {e}\n")

def launch_web_ui():
    """Khởi động Giao diện Màn hình Web Dashboard"""
    import subprocess
    ui_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "client_ui.py")
    print("\n🚀 Đang khởi động Giao diện Màn hình Dashboard...")
    subprocess.run([sys.executable, ui_script])

# ==========================================
# MENU CHÍNH
# ==========================================
if __name__ == "__main__":
    if "--ui" in sys.argv or "-ui" in sys.argv:
        launch_web_ui()
        sys.exit(0)

    while True:
        print("\n" + "="*45)
        print(f"=== AI AGENT CONTROL PANEL ({AI_MODEL}) ===")
        print("="*45)
        print("1. 🌟 Mở Giao diện Màn hình Dashboard (Web UI)")
        print("2. 🚀 Deploy & Cài đặt Systemd (Push code mới)")
        print("3. ▶️  Bật AI Agent (Start)")
        print("4. ⏹️  Tắt AI Agent (Stop)")
        print("5. 🔄 Khởi động lại AI Agent (Restart)")
        print("6. 💬 Chat nhanh trong Terminal (CLI)")
        print("7. 🚪 Thoát")
        
        try:
            choice = input("\nChọn chức năng (1-7): ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nĐã thoát.")
            break
            
        if choice == '1':
            launch_web_ui()
        elif choice == '2':
            deploy_ai_agent()
            install_systemd_service()
        elif choice == '3':
            control_agent("start")
        elif choice == '4':
            control_agent("stop")
        elif choice == '5':
            control_agent("restart")
        elif choice == '6':
            chat_loop()
        elif choice == '7':
            print("Tạm biệt!")
            break
        else:
            print("Lựa chọn không hợp lệ.")