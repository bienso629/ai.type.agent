#!/bin/bash

# ==============================================================================
# SCRIPT CHẠY CLOUDFLARE TUNNEL BẰNG DỮ LIỆU TỪ WINDOWS COPY SANG
# ==============================================================================

# Hướng dẫn:
# Bạn hãy copy TOÀN BỘ thư mục C:\Users\Wing386\.cloudflared từ máy Windows
# và dán đè vào thư mục ~/.cloudflared trên máy Ubuntu này.
# Bằng cách này, máy Ubuntu sẽ thừa kế toàn bộ cấu hình, cert.pem và UUID từ máy Windows!

mkdir -p ~/.cloudflared
cd ~/.cloudflared

# Ra lệnh cho PM2 chạy ngầm Tunnel y hệt như trên máy Windows
pm2 start cloudflared --name "type-tunnel" -- tunnel run type-tunnel

# Lưu lại cấu hình PM2
pm2 save

echo "--------------------------------------------------------"
echo "Đã chạy type-tunnel thành công qua PM2!"
echo "Tunnel đang sử dụng cấu hình kế thừa từ máy Windows."
echo "Bạn có thể kiểm tra kết nối bằng lệnh: pm2 logs type-tunnel"
echo "--------------------------------------------------------"
