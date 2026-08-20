# Colab Agent & MCP Bridge Plugin

Plugin chạy nền (Sidecar Daemon) cho ứng dụng `ai.type`, giúp tự động hóa 100% việc kết nối Google Colab GPU, bóc tách tài liệu MinerU, xây dựng Vector FAISS và thực thi mã Python từ xa.

## 🚀 Các tính năng chính
- **Tự động đăng ký Webhook (Auto-Discovery)**: Colab tự động bắn URL Cloudflare về cổng `7868`, người dùng không cần copy-paste link thủ công.
- **Bóc tách MinerU GPU**: Chuyển giao các tác vụ nặng cho card đồ họa NVIDIA T4/A100 trên Colab.
- **Thực thi Code từ xa (Python REPL)**: Gửi code Python động lên Colab và nhận kết quả tức thì.
- **Đóng gói độc lập**: Chạy như 1 file nhị phân độc lập `colab_agent_linux` không phụ thuộc vào môi trường Python của hệ thống.

## 📁 Cấu trúc thư mục
- `colab_agent.py`: Mã nguồn chính của Daemon FastAPI.
- `colab_agent_linux.spec`: File cấu hình PyInstaller.
- `build_linux.sh`: Script tự động build binary và sao chép vào `Documents/ai.type/plugins/`.
- `dist/colab_agent_linux`: File thực thi sau khi đóng gói (Standalone binary).

## 🔨 Cách build lại
```bash
cd /home/yenai/Documents/Projects/Typing/apps/plugins/colab
./build_linux.sh
```
