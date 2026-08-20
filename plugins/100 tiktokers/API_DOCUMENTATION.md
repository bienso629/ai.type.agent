# 📚 Tài Liệu Hướng Dẫn Sử Dụng API Mới Nhất (100tiktok Platform)

> Hệ thống tự động hóa đa Profile Opera, quản lý VPN, tương tác TikTok và tích hợp AI Opera (Aria).
> Hỗ trợ đa nền tảng 100%: **Linux**, **Windows**, và **macOS**.

---

## 🚀 1. Khởi Chạy Server API

### Trên Linux / macOS / Windows:
```bash
python3 app.py
# hoặc
uvicorn app:app --host 0.0.0.0 --port 8000
```

- **Swagger UI (Tài liệu tương tác)**: `http://localhost:8000/docs`
- **Health Check**: `http://localhost:8000/health`
- **Lấy Cấu Hình Mặc Định Hệ Thống**: `GET /v1/opera/profiles/config`

---

## ⚙️ 0. API Lấy Đường Dẫn & Cấu Hình Mặc Định (`GET /v1/opera/profiles/config`)

Client chỉ cần gọi endpoint này để **tự động lấy đường dẫn `profiles_root`** và file thực thi `opera_exe` chuẩn của hệ điều hành hiện tại (**Linux / Windows / macOS**) mà không cần tự nhập thủ công:

- **Response JSON ví dụ (trên Linux)**:
```json
{
  "system": "Linux",
  "profiles_root": "/home/yenai/OperaProfiles",
  "opera_exe": "/usr/bin/opera-gx",
  "default_host": "127.0.0.1",
  "default_cdp_port": 54900
}
```

- **Response JSON ví dụ (trên macOS)**:
```json
{
  "system": "Darwin",
  "profiles_root": "/Users/username/OperaProfiles",
  "opera_exe": "/Applications/Opera GX.app/Contents/MacOS/Opera GX",
  "default_host": "127.0.0.1",
  "default_cdp_port": 54900
}
```

## 🤖 2. API Opera AI (Aria AI Automation) - MỚI NHẤT

### 2.1. Gửi câu hỏi cho AI Opera (`POST /v1/opera/ai/ask`)
Tự động mở/kết nối giao diện Aria AI, điền câu hỏi, nhận câu trả lời và **tự động bóc tách các câu hỏi gợi ý (Suggestions)**.

- **Request Body (JSON)**:
```json
{
  "profile": "Profile000",
  "prompt": "Tóm tắt tin pháp luật mới nhất",
  "timeout_s": 30.0
}
```

- **Response JSON**:
```json
{
  "ok": true,
  "profile": "Profile000",
  "question": "Tóm tắt tin pháp luật mới nhất",
  "answer": "Dưới đây là tóm tắt các tin tức pháp luật nổi bật...",
  "suggestions": [
    "Chi tiết vụ án thầy giáo phi tang thi thể nữ đồng nghiệp?",
    "Thủ đoạn lừa đảo tiêm nano canxi xảy ra ở địa bàn nào?",
    "Trách nhiệm đền bù khi đấu giá đất không nhận được đất?"
  ],
  "suggestion_count": 3
}
```

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/ai/ask" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "Profile000",
       "prompt": "Cho mình xin 3 mẹo tăng follow TikTok"
     }'
```

---

### 2.2. Tự động click câu hỏi gợi ý (`POST /v1/opera/ai/click-suggestion`)
Tự động nhấp vào 1 câu hỏi gợi ý của Aria để AI tiếp tục trả lời trong cùng cuộc hội thoại.

- **Request Body (JSON)**:
```json
{
  "profile": "Profile000",
  "suggestion_index": 0,
  "suggestion_text": "Chi tiết vụ án",
  "timeout_s": 30.0
}
```
*Ghi chú:*
- `suggestion_index`: Vị trí câu hỏi (0 = câu đầu tiên).
- `suggestion_text`: (Tùy chọn) Khớp câu gợi ý có chứa từ khóa này.

- **Response JSON**:
```json
{
  "ok": true,
  "profile": "Profile000",
  "clicked_suggestion": "Chi tiết vụ án thầy giáo phi tang thi thể nữ đồng nghiệp?",
  "answer": "Dưới đây là chi tiết diễn biến vụ án...",
  "new_suggestions": [
    "Khung hình phạt đối với tội Giết người?",
    "Động cơ gây án chính xác là gì?"
  ]
}
```

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/ai/click-suggestion" \
     -H "Content-Type: application/json" \
     -d '{"profile": "Profile000", "suggestion_index": 0}'
```

---

## 🌐 3. API Quản Lý Cấu Hình VPN Opera - MỚI NHẤT

### 3.1. Đổi vị trí VPN cho 1 Profile (`POST /v1/opera/profiles/{profile}/vpn`)
Cấu hình bật/tắt và chọn khu vực VPN cho 1 profile cụ thể.

- **Request Body (JSON)**:
```json
{
  "enabled": true,
  "location": "asia"
}
```
*Vị trí hỗ trợ:* `"asia"` (Châu Á), `"americas"` (Châu Mỹ), `"europe"` (Châu Âu), `"optimal"` (Tự động / Tối ưu).

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/Profile001/vpn" \
     -H "Content-Type: application/json" \
     -d '{"enabled": true, "location": "asia"}'
```

---

### 3.2. Đổi vị trí VPN cho hàng loạt Profile (`POST /v1/opera/profiles/vpn-range`)
Đổi VPN cho dải Profile từ `start` đến `end`. Hỗ trợ chế độ xoay vòng vị trí (`"rotate"`).

- **Request Body (JSON)**:
```json
{
  "start": 1,
  "end": 99,
  "zero_pad": 3,
  "prefix": "Profile",
  "enabled": true,
  "location": "rotate"
}
```
*Ghi chú:* Nếu dùng `"location": "rotate"`, hệ thống sẽ xoay vòng ngẫu nhiên/lần lượt các khu vực (*Asia -> Americas -> Europe*) cho 99 profile.

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/vpn-range" \
     -H "Content-Type: application/json" \
     -d '{"start": 1, "end": 99, "enabled": true, "location": "rotate"}'
```

---

---

### 3.3. API Quản Lý Proxy Dân Cư / Private Proxy & Cấu Hình Profile

Gán Proxy riêng biệt (HTTP, HTTPS, SOCKS5) cho từng profile để đảm bảo 100% địa chỉ IP độc lập.

#### 🔄 Cơ chế tự động cấu hình Proxy vào Profile:
1. **Lưu trữ cấu hình**: Lưu ánh xạ Profile $\rightarrow$ Proxy tại `<profiles_root>/proxies.json`.
2. **Tự động sinh Extension xác thực**: Tạo thư mục extension ngầm `proxy_extension/` (`manifest.json` + `background.js` tự xác thực `user`/`pass`) ngay trong thư mục Profile để tránh popup yêu cầu đăng nhập Proxy của trình duyệt.
3. **Áp dụng khi khởi chạy Profile**: Khi gọi API khởi chạy Profile (`/start-range` hoặc `/start-profiles`), hệ thống tự động truyền tham số `--proxy-server=<scheme>://<host>:<port>` và tự nạp `--load-extension=<profile_dir>/proxy_extension`.

#### A. Import Proxy hàng loạt (`POST /v1/opera/profiles/proxy/import`)
Dán danh sách Proxy (dạng `ip:port:user:pass` hoặc `http://user:pass@ip:port` hoặc `socks5://...`).

- **Request Body (JSON)**:
```json
{
  "proxy_list": "103.15.50.1:8080:user001:pass001\n103.15.50.2:8080:user002:pass002\n103.15.50.3:8080:user003:pass003",
  "start_index": 1,
  "prefix": "Profile",
  "zero_pad": 3
}
```

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/proxy/import" \
     -H "Content-Type: application/json" \
     -d '{
           "proxy_list": "103.15.50.1:8080:user001:pass001\n103.15.50.2:8080:user002:pass002",
           "start_index": 1
         }'
```

#### B. Xem danh sách Proxy đã gán (`GET /v1/opera/profiles/proxy/list`)
- **Ví dụ cURL**:
```bash
curl -s "http://localhost:8000/v1/opera/profiles/proxy/list"
```

#### C. Gán Proxy cho 1 Profile lẻ (`POST /v1/opera/profiles/proxy/set`)
- **Request Body (JSON)**:
```json
{
  "profile": "Profile001",
  "proxy": "103.15.50.1:8080:user001:pass001"
}
```

#### D. Xóa Proxy đã cài đặt (`DELETE /v1/opera/profiles/proxy/remove`)
- **Ví dụ cURL**:
```bash
curl -X DELETE "http://localhost:8000/v1/opera/profiles/proxy/remove" \
     -H "Content-Type: application/json" \
     -d '{"profiles": ["Profile001", "Profile002"]}'
```

---

## 🖥 4. API Khởi Chạy & Quản Lý Profile Opera (Bao gồm Headless)

### 4.1. Khởi chạy dải Profile (`POST /v1/opera/profiles/start-range`)
Bật hàng loạt profile Opera với các tùy chọn chạy ẩn (Headless), gán cổng CDP, mở sẵn trang web, tự động áp dụng Proxy và Tiền tố tiêu đề.

- **Request Body (JSON)**:
```json
{
  "start": 1,
  "end": 10,
  "zero_pad": 3,
  "headless": true,
  "new_tab_url": "https://www.tiktok.com",
  "prefix_title_with_profile": true,
  "window_state": "maximized"
}
```

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/start-range" \
     -H "Content-Type: application/json" \
     -d '{"start": 1, "end": 5, "headless": true, "prefix_title_with_profile": true}'
```

---

### 4.2. Quét Trạng Thái Profile Thực Tế (`GET /v1/opera/profiles/list`)
Kiểm tra danh sách 100 Profile kèm tiến trình PID, Cổng CDP, Trạng thái thực tế (`running: true/false`), cùng toàn bộ cấu hình **VPN** (`enabled`, `location`) và **Proxy** đã gán cho từng profile.

- **Query Parameters**:
  - `verify=true`: Thực hiện kiểm tra socket/CDP live trên từng cổng.
  - `filter=running`: Chỉ lọc ra danh sách profile ĐANG BẬT.
  - `filter=stopped`: Chỉ lọc ra danh sách profile ĐÃ TẮT.

- **Response JSON ví dụ**:
```json
{
  "ok": true,
  "root": "/home/yenai/OperaProfiles",
  "count": 2,
  "total": 100,
  "limit": 2,
  "offset": 0,
  "order_by": "profile",
  "order_dir": "asc",
  "results": [
    {
      "profile": "Profile001",
      "dir": "/home/yenai/OperaProfiles/Profile001",
      "avatar": null,
      "devtools_port": 54901,
      "running": false,
      "vpn": {
        "enabled": true,
        "location": "americas"
      },
      "proxy": {
        "scheme": "http",
        "host": "103.15.50.1",
        "port": 8080,
        "user": "user001",
        "pass": "pass001",
        "raw": "103.15.50.1:8080:user001:pass001"
      }
    }
  ]
}
```

- **Ví dụ cURL**:
```bash
# Lấy toàn bộ danh sách profile kèm cấu hình VPN và Proxy:
curl -s "http://localhost:8000/v1/opera/profiles/list"

# Chỉ lọc các profile đang chạy:
curl -s "http://localhost:8000/v1/opera/profiles/list?filter=running"
```

---

---

### 4.4. API Làm Sạch Cookie & Session (`POST /v1/opera/profiles/{profile}/clear-session`)
Xóa bỏ toàn bộ Session, Cookie và LocalStorage của một profile hoặc dải profile mà vẫn giữ nguyên Extension và Cài đặt.

- **Request 1 Profile**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/Profile001/clear-session"
```

- **Request Dải Profile (`POST /v1/opera/profiles/clear-session-range`)**:
```json
{
  "start": 1,
  "end": 99,
  "zero_pad": 3,
  "prefix": "Profile"
}
```
- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/clear-session-range" \
     -H "Content-Type: application/json" \
     -d '{"start": 1, "end": 99}'
```

---

## 🛠 5. Công Cụ Lệnh Command-Line (CLI Tools)

Dành cho khởi tạo và mở dải Profile trên Ubuntu / Linux mà không cần dùng API HTTP:

### 5.1. Tạo & Nhân bản 100 Profile (`make_profiles.py`)

> ⚠️ **Quy tắc quan trọng khi tạo Profile mẫu (`Profile000`)**:
> - Chỉ dùng `Profile000` để cài đặt **Extension**, **Bookmark**, **Cấu hình VPN** và **Cài đặt trình duyệt**.
> - **KHÔNG ĐĂNG NHẬP tài khoản TikTok / Facebook / Google trên `Profile000`** trước khi clone để tránh việc các profile từ `001 -> 099` bị dính chung phiên đăng nhập.
> - Mặc định khi chạy lệnh clone, hệ thống sẽ **tự động làm sạch Session** của `Profile000` trên các profile mới tạo.

```bash
# 1. Bật Profile 000 mẫu để cài đặt ban đầu (Cài extension / cấu hình VPN):
python3 make_profiles.py --setup-base

# 2. Nhân bản từ Profile 000 thành 99 Profile mới (Tự động xóa session cũ):
python3 make_profiles.py --from 1 --to 99 --force

# (Tùy chọn) Nếu muốn giữ nguyên Cookie từ Profile000:
python3 make_profiles.py --from 1 --to 99 --force --keep-session
```

### 5.2. Mở dải Profile (`open_profiles.py`)
Tự động áp dụng Proxy từ `proxies.json` (nếu có) khi mở profile.
```bash
# Mở có giao diện cửa sổ (GUI):
python3 open_profiles.py --from 1 --to 10

# Mở chế độ chạy ẩn tiết kiệm tài nguyên (Headless Mode):
python3 open_profiles.py --from 1 --to 10 --headless

# Tắt toàn bộ Opera:
python3 open_profiles.py --kill-all
```

---

## 🎯 6. API Tự Động Hóa Tương Tác TikTok

### 6.1. Tìm kiếm & Follow (`POST /v1/search/click`)
- Nhập từ khóa tìm kiếm và tự động click nút Follow theo tọa độ.

### 6.2. Thả tim (`POST /v1/like/click`)
- Tự động thả tim trên video hoặc phòng TikTok Live.

### 6.3. Viết bình luận (`POST /v1/comment/click`)
- Quét Iframe / Shadow DOM để tự động điền văn bản và gửi comment.

---

## 📦 7. Hướng Dẫn Backup & Khôi Phục Dữ Liệu Profile (Cookies & Session)

Toàn bộ Session, Cookie, Mật khẩu đã lưu và LocalStorage được lưu tại thư mục `~/OperaProfiles/` (trên Linux) hoặc `D:\OperaProfiles\` (trên Windows).

### Các bước Backup 100 Profile:
1. **Tắt toàn bộ tiến trình Opera**:
   ```bash
   python3 open_profiles.py --kill-all
   ```
2. **Nén thư mục Profile**:
   ```bash
   tar -czvf opera_profiles_backup.tar.gz ~/OperaProfiles
   ```

### Các bước Khôi Phục (Restore):
1. **Giải nén đè lại thư mục `~/OperaProfiles`**.
2. **Xóa các file khóa tạm (Lock files)**:
   ```bash
   python3 make_profiles.py --from 1 --to 99 --force --keep-session
   ```

---

*Tài liệu được cập nhật ngày 17/08/2026 cho phiên bản 100tiktok v5.2+*
