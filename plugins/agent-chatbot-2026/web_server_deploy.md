# Huong Dan Trien Khai AI Agent Chatbot 2026 Len Website Server

Tai lieu nay huong dan chi tiet cach trien khai he thong AI Agent Chatbot len Website Server (gồm Frontend Web va Backend Cloud Sync Server).

---

## 1. Tong Quan Kien Truc
- **Frontend (Web Client)**: Ứng dụng Flutter Web đã được biên dịch thành HTML, JS, CSS, CanvasKit và Assets tĩnh. Phù hợp chạy trên bất kỳ Web Server nào (Nginx, Apache, Caddy, Cloudflare Pages...).
- **Backend (Cloud Sync API)**: Cụm dịch vụ PHP 8.2 (REST API) + MariaDB/MySQL (Docker Compose) xử lý lưu trữ người dùng, phiên chat, tin nhắn và cấu hình AI Model.

---

## 2. Cach 1: Chay Nhanh Bang Docker Compose (Khuyen Dung)
Trong thu muc `backend-cloud-sync`, he thong da duoc dong goi san:
```bash
cd /home/yenai/Documents/Projects/Typing/apps/plugins/agent-chatbot-2026/backend-cloud-sync
docker compose up -d --build
```
Dich vu se tu dong khoi chay:
- **MySQL / MariaDB**: Port `3307` (User: `agent_user`, Pass: `AgentPass2026!`, Database: `agent_chatbot_db`)
- **PHP REST API**: Port `8888`

---

## 3. Cach 2: Bien Dich Frontend De Deploy Len Web Server
Chay script tu dong:
```bash
cd /home/yenai/Documents/Projects/Typing/apps/plugins/agent-chatbot-2026
bash scripts/build_web.sh
```
Sau khi lenh hoan tat:
1. Thu muc ma nguon web tinh nam tai: `build/web/`
2. File nen dong goi san de upload: `dist/agent-chatbot-2026-web-release.tar.gz`

---

## 4. Cau Hinh Reverse Proxy Nginx Mau (Tich Hop Web & API)
```nginx
server {
    listen 80;
    server_name agent.yourdomain.com;

    # Thu muc chua ban build Flutter Web (giai nen tu agent-chatbot-2026-web-release.tar.gz)
    root /var/www/agent-chatbot-web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy toi Backend API (PHP container / port 8888)
    location /api/ {
        proxy_pass http://127.0.0.1:8888/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
