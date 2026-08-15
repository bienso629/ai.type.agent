# Hướng dẫn Tạo & Quản lý 100 Profile Opera trên Ubuntu / Linux

Tài liệu hướng dẫn khởi tạo **Profile 0 (Profile000)** làm mẫu chuẩn (đã đăng nhập TikTok, bật VPN/Extensions) và tự động nhân bản thành **99 Profile (Profile001 -> Profile099)** trên Ubuntu.

---

## 🛠 1. Quy trình chuẩn gồm 3 bước

### Bước 1: Khởi chạy Profile000 mẫu để cài đặt & đăng nhập
Chạy lệnh sau trên Terminal:
```bash
python3 make_profiles.py --setup-base
```
- Opera sẽ tự động mở ra ở thư mục `~/OperaProfiles/Profile000`.
- Thực hiện: Đăng nhập tài khoản TikTok mẫu, bật VPN Opera, tùy chỉnh Cài đặt/Extension theo nhu cầu.
- **Sau khi hoàn tất, đóng hoàn toàn cửa sổ Opera.**

---

### Bước 2: Clone Profile000 thành 99 Profile (Profile001 -> Profile099)
Chạy lệnh nhân bản:
```bash
python3 make_profiles.py --from 1 --to 99 --force
```
- Lệnh trên sẽ tự động:
  1. Làm sạch các file khóa tạm thời (`SingletonLock`, `Crashpad`...) của `Profile000`.
  2. Nhân bản `Profile000` thành 99 profile từ `Profile001` tới `Profile099`.
  3. Làm sạch file Lock trên tất cả profile mới tạo để khi mở không bị báo lỗi "Browser Crashed".

---

### Bước 3: Mở thử dải Profile (ví dụ Profile 001 đến 005)
Chạy lệnh mở profile và kết nối cổng Remote Debugging (CDP):
```bash
python3 open_profiles.py --from 1 --to 5
```

Nếu muốn ngắt toàn bộ các cửa sổ Opera đang mở:
```bash
python3 open_profiles.py --kill-all
```

---

## ⚙️ 2. Chạy ứng dụng API Server trên Ubuntu

Khởi chạy server FastAPI:
```bash
python3 app.py
```
Hoặc dùng uvicorn:
```bash
uvicorn app:app --host 0.0.0.0 --port 8000
```

Mở Swagger UI tại: `http://localhost:8000/docs`
Các API kiểm tra profile, bật/tắt dải profile qua HTTP đều sẽ tự động nhận diện Opera trên Ubuntu (`/usr/bin/opera-gx` hoặc `/usr/bin/opera`).
