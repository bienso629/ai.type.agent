# Hướng dẫn Tạo & Quản lý 100 Profile Opera trên Ubuntu / Linux

Tài liệu hướng dẫn khởi tạo **Profile 0 (Profile000)** làm mẫu chuẩn (đã cài đặt Extensions, VPN, Bookmarks) và tự động nhân bản thành **99 Profile (Profile001 -> Profile099)** trên Ubuntu.

---

## 🛠 1. Quy trình chuẩn gồm 3 bước

### Bước 1: Khởi chạy Profile000 mẫu để cài đặt Extension & VPN
Chạy lệnh sau trên Terminal:
```bash
python3 make_profiles.py --setup-base
```
- Opera sẽ tự động mở ra ở thư mục `~/OperaProfiles/Profile000`.
- Thực hiện: Bật VPN Opera, cài đặt các Extension cần thiết, tùy chỉnh Cài đặt/Bookmarks theo nhu cầu.
- ⚠️ **LƯU Ý QUAN TRỌNG**: **KHÔNG ĐĂNG NHẬP bất kỳ tài khoản TikTok/Facebook/Google nào ở Profile000 trước khi clone** để tránh các profile con bị dính chung phiên đăng nhập.
- **Sau khi hoàn tất cài đặt mẫu, đóng hoàn toàn cửa sổ Opera.**

---

### Bước 2: Clone Profile000 thành 99 Profile (Profile001 -> Profile099)
Chạy lệnh nhân bản:
```bash
python3 make_profiles.py --from 1 --to 99 --force
```
- Lệnh trên sẽ tự động:
  1. Làm sạch các file khóa tạm thời (`SingletonLock`, `Crashpad`...) của `Profile000`.
  2. Nhân bản `Profile000` thành 99 profile từ `Profile001` tới `Profile099`.
  3. **Tự động làm sạch Cookie/Session cũ** để từng profile từ 001 đến 099 có môi trường đăng nhập hoàn toàn mới và độc lập.
  4. Làm sạch file Lock trên tất cả profile mới tạo để khi mở không bị báo lỗi "Browser Crashed".

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

---

## 🌐 3. Cấu hình Proxy Dân cư (Residential Proxy) cho 100 Profile

Đảm bảo mỗi Profile có một địa chỉ IP riêng biệt để không bị TikTok đánh dấu Spam / Botnet.

### Thêm Proxy hàng loạt qua API:
Gửi request đến `POST http://localhost:8000/v1/opera/profiles/proxy/import`:
```bash
curl -X POST "http://localhost:8000/v1/opera/profiles/proxy/import" \
     -H "Content-Type: application/json" \
     -d '{
           "proxy_list": "103.15.50.1:8080:user001:pass001\n103.15.50.2:8080:user002:pass002",
           "start_index": 1
         }'
```
- Hệ thống tự động tạo extension xác thực tài khoản/mật khẩu proxy ngầm.
- Khi khởi chạy qua `open_profiles.py` hoặc API `start-range`, proxy sẽ tự động được áp dụng.

---

## 📊 4. Quản lý Trạng thái Profile Thực Tế

Xem danh sách profile kèm theo trạng thái Đang mở (`running: true`) hoặc Đã tắt (`running: false`):
```bash
# Kiểm tra toàn bộ danh sách profile:
curl -s "http://localhost:8000/v1/opera/profiles/list"

# Chỉ lọc ra các Profile đang chạy:
curl -s "http://localhost:8000/v1/opera/profiles/list?filter=running"
```

---

## 📦 5. Backup & Khôi phục phiên đăng nhập (Cookies & Session)

Toàn bộ Cookie, Session và Mật khẩu tài khoản được lưu tại thư mục `~/OperaProfiles/`.

### 1. Nén Backup:
```bash
# Tắt sạch cửa sổ Opera
python3 open_profiles.py --kill-all

# Nén backup toàn bộ profile
tar -czvf opera_profiles_backup.tar.gz ~/OperaProfiles
```

### 2. Khôi phục (Restore):
```bash
# Giải nén đè lại thư mục OperaProfiles
tar -xzvf opera_profiles_backup.tar.gz -C ~/

# Làm sạch file khóa tạm để không bị báo "Browser Crashed"
python3 make_profiles.py --from 1 --to 99 --force
```

