# Agent Chatbot 2026 - Cloud Sync Server (PHP + MySQL)

Cụm máy chủ Cloud Server giúp đồng bộ hóa dữ liệu người dùng, mật khẩu, cấu hình và lịch sử trò chuyện để không bao giờ bị mất dữ liệu khi cài lại máy tính.

## 1. Cấu trúc thư mục
- `Dockerfile`: Cấu hình container PHP 8.2 Apache + PDO MySQL.
- `docker-compose.yml`: Triển khai cụm dịch vụ MariaDB (MySQL) + PHP API trên Docker.
- `database/schema.sql`: Khởi tạo bảng `users`, `user_configs`, `chat_sessions`, `chat_messages`.
- `api/auth/`: Đăng ký, Đăng nhập, Xác thực Token.
- `api/config/`: Đồng bộ cấu hình ứng dụng lên Cloud.
- `api/chat/`: Đồng bộ phiên chat và tin nhắn.

## 2. Cách khởi chạy bằng Docker
```bash
cd /home/yenai/Documents/Projects/Typing/apps/plugins/agent-chatbot-2026/backend-cloud-sync
docker compose up -d --build
```

## 3. Cổng dịch vụ
- **PHP REST API**: `http://localhost:8888`
- **MySQL / MariaDB**: `localhost:3307` (Tài khoản: `agent_user` / `AgentPass2026!`, Database: `agent_chatbot_db`)

## 4. Dừng dịch vụ
```bash
docker compose down
```
