# Hướng Dẫn Cấu Hình Nginx Reverse Proxy Cho api-vn-sg.mitom.ai

Tài liệu này hướng dẫn cách khắc phục triệt để lỗi trang trắng HTML `404 Not Found` của Apache trên máy chủ Plesk khi gọi API qua `https://api-vn-sg.mitom.ai/v1/chat/completions`.

---

## 1. Bản chất vì sao bị lỗi 404 HTML?

* Phản hồi trả về có dạng:
  ```html
  <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
  <html><head><title>404 Not Found</title></head>...
  ```
* Đây là trang lỗi mặc định của **Apache Web Server** trên Plesk.
* Trên Plesk, mặc định chế độ **Proxy mode** được bật, khiến Nginx đẩy các request động xuống Apache. Do Apache không có thư mục hoặc mã nguồn `/v1/` cục bộ nên Apache báo lỗi 404.
* Đồng thời, nếu dùng `location /v1/` mà Plesk cấu hình sai lệch giữa HTTP và HTTPS, Nginx sẽ bỏ qua và đẩy xuống Apache.

---

## 2. Các bước xử lý chuẩn xác trên Plesk Control Panel

### Bước 1: Vào mục cấu hình Web Server
1. Đăng nhập vào trang quản trị **Plesk**.
2. Chọn đúng tên miền: **`api-vn-sg.mitom.ai`**.
3. Chọn thẻ **Hosting & DNS** -> bấm vào **Apache & nginx Settings**.

---

### Bước 2: Tắt hoàn toàn Apache (Bắt buộc)
Cuộn xuống phần **nginx settings**:
1. **BỎ CHỌN (Uncheck)** ô **Proxy mode** (Chế độ ủy quyền).
   * *Ý nghĩa: Tắt Apache can thiệp, buộc Nginx đứng mũi chịu sào và tự chuyển tiếp 100% request.*
2. **BỎ CHỌN (Uncheck)** ô **Smart static files processing** (nếu có).

---

### Bước 3: Dán đoạn chỉ thị Nginx bắt toàn bộ Route
Tại ô **Additional nginx directives**, xóa hết các nội dung cũ và dán đoạn cấu hình chuẩn sau:

```nginx
# 1. DNS Resolver de Nginx phan giai domain upstream
resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
resolver_timeout 5s;

# 2. Bat toan bo cac duong dan bat dau tu /
location / {
    # Chuyen tiep sang upstream umodelverse
    proxy_pass https://api-us-ca.umodelverse.ai;

    # Bat xac thuc SNI SSL voi may chu upstream
    proxy_ssl_server_name on;
    proxy_ssl_protocols TLSv1.2 TLSv1.3;

    # Thiet lap Header
    proxy_set_header Host api-us-ca.umodelverse.ai;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Tu dong doi x-api-key thanh Bearer neu client gui x-api-key
    set $auth_header $http_authorization;
    if ($http_x_api_key != "") {
        set $auth_header "Bearer $http_x_api_key";
    }
    proxy_set_header Authorization $auth_header;

    # Toi uu cho Streaming LLM (Server-Sent Events)
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_cache off;
    chunked_transfer_encoding on;

    # Thoi gian timeout dai cho cac model suy luan
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
    proxy_connect_timeout 30s;
}
```

---

### Bước 4: Lưu cấu hình
* Bấm nút **OK** hoặc **Apply** ở cuối trang để lưu lại.

---

## 3. Lệnh cURL kiểm thử sau khi lưu cấu hình

Chạy lệnh kiểm tra bằng terminal:

```bash
curl -X POST https://api-vn-sg.mitom.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-api-key: mt_843b3632c56c5ac94039802c58b8067daffdb16901cd2887" \
  -d '{
    "model": "deepseek-ai/DeepSeek-V3",
    "messages": [
      {
        "role": "user",
        "content": "Hello! Hãy giới thiệu bạn là ai?"
      }
    ],
    "stream": false
  }'
```

* **Kết quả thành công**: Nhận về dữ liệu JSON từ upstream thay vì trang HTML `404 Not Found` của Apache.
