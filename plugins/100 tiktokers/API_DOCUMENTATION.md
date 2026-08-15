# 📚 Tài Liệu Hướng Dẫn Sử Dụng API Mới Nhất (100tiktok Platform)

> Hệ thống tự động hóa đa Profile Opera, quản lý VPN, tương tác TikTok và tích hợp AI Opera (Aria).

---

## 🚀 1. Khởi Chạy Server API

### Trên Ubuntu / Linux:
```bash
python3 app.py
# hoặc
uvicorn app:app --host 0.0.0.0 --port 8000
```

- **Swagger UI (Tài liệu tương tác)**: `http://localhost:8000/docs`
- **Health Check**: `http://localhost:8000/health`

---

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

## 🖥 4. API Khởi Chạy & Quản Lý Profile Opera (Bao gồm Headless)

### 4.1. Khởi chạy dải Profile (`POST /v1/opera/profiles/start-range`)
Bật hàng loạt profile Opera với các tùy chọn chạy ẩn (Headless), gán cổng CDP, mở sẵn trang web.

- **Request Body (JSON)**:
```json
{
  "start": 1,
  "end": 10,
  "zero_pad": 3,
  "headless": true,
  "new_tab_url": "https://www.tiktok.com",
  "window_state": "maximized"
}
```

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/start-range" \
     -H "Content-Type: application/json" \
     -d '{"start": 1, "end": 5, "headless": true}'
```

---

### 4.2. Tắt toàn bộ Opera (`POST /v1/opera/profiles/kill-all`)
Tắt sạch sẽ toàn bộ cửa sổ trình duyệt Opera đang mở.

- **Ví dụ cURL**:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/kill-all"
```

---

## 🛠 5. Công Cụ Lệnh Command-Line (CLI Tools)

Dành cho khởi tạo và mở dải Profile trên Ubuntu / Linux mà không cần dùng API HTTP:

### 5.1. Tạo & Nhân bản 100 Profile (`make_profiles.py`)
```bash
# 1. Bật Profile 000 mẫu để cài đặt ban đầu (đăng nhập TikTok/bật VPN):
python3 make_profiles.py --setup-base

# 2. Nhân bản từ Profile 000 thành 99 Profile (001 -> 099):
python3 make_profiles.py --from 1 --to 99 --force
```

### 5.2. Mở dải Profile (`open_profiles.py`)
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
*Tài liệu được cập nhật ngày 15/08/2026 cho phiên bản 100tiktok v5.0+*
