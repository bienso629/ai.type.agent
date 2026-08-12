# Cẩm nang quy tắc bắt buộc (Mandatory Rules) cho ai_agent_linux

Tài liệu này ghi chú các quy tắc kỹ thuật và "bẫy" hệ thống (đặc biệt trên Ubuntu/Wayland) mà `ai_agent_linux` (và các AI Agent được gọi từ nó) BẮT BUỘC phải tuân thủ khi thao tác với hệ thống của người dùng.

## 1. Quy tắc mở ứng dụng đồ hoạ (GUI) và trình duyệt
Khi AI thực thi lệnh mở một ứng dụng GUI (như trình duyệt web) từ một tiến trình chạy ngầm, thường sẽ gặp hai lỗi chí mạng:
- **Lỗi SIGHUP (chết yểu):** Lệnh thực thi qua công cụ `run_command` thường tạo ra một PTY (pseudo-terminal) ảo. Ngay khi lệnh hoàn tất, PTY đóng lại và gửi tín hiệu SIGHUP giết chết toàn bộ tiến trình con, kể cả khi dùng `&` hay `nohup`.
- **Lỗi Snap/AppArmor (tàng hình):** Dùng `xdg-open` thường vô tình gọi trình duyệt mặc định (VD: Firefox bản snap). Khi Snap khởi chạy từ một daemon ngầm, nó thường bị chặn vẽ giao diện lên Wayland, khiến ứng dụng kẹt ở trạng thái "headless" (chạy ngầm ăn CPU nhưng không có cửa sổ).

**Cách giải quyết BẮT BUỘC:**
- **TUYỆT ĐỐI KHÔNG** dùng `xdg-open`, `&`, `nohup` hay `setsid` để mở ứng dụng GUI.
- **BẮT BUỘC** dùng `systemd-run --user` để đẩy tiến trình sang cho trình quản lý hệ thống (systemd) của người dùng khởi chạy.
- **BẮT BUỘC** truyền đầy đủ các biến môi trường Wayland/X11 vào `systemd-run`.
- **SỬ DỤNG TRÌNH DUYỆT NATIVE:** Sử dụng trực tiếp `/usr/bin/opera-gx` (bản native không bị snap cô lập).

**Cú pháp chuẩn để mở URL (hoặc app GUI):**
```bash
systemd-run --user --setenv=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus --setenv=DISPLAY=:0 --setenv=WAYLAND_DISPLAY=wayland-0 --setenv=XDG_RUNTIME_DIR=/run/user/1000 /usr/bin/opera-gx "https://..."
```

## 2. Quy tắc tìm và mở nhạc/video trên YouTube
Người dùng rất ghét việc AI mở ra một trang tìm kiếm (`results?search_query=...`) rồi bắt họ tự click.

**Cách giải quyết BẮT BUỘC:**
- Dùng `yt-dlp` (hoặc các lệnh tương tự) để tìm ID video chính xác.
- Cú pháp tìm ID: `yt-dlp "ytsearch1:<tên bài hát>" --get-id`
- Sau khi có ID (ví dụ: `jPjQJYKhhk4`), ghép thành URL `https://www.youtube.com/watch?v=jPjQJYKhhk4` rồi truyền vào lệnh `systemd-run` mở trình duyệt ở mục 1.

## 3. Quy tắc tương tác với website (ví dụ Facebook)
- **TUYỆT ĐỐI KHÔNG** dùng các công cụ automation (như Puppeteer/Playwright) để click vào các nút dạng "Tải ảnh/video lên" (Upload button) mà gọi ra hộp thoại chọn file của hệ điều hành (File Picker Dialog). Việc này sẽ làm treo tiến trình automation do AI không thể tương tác với hộp thoại hệ thống.
- **Cách giải quyết:** Phải tìm phần tử `<input type="file" ...>` ẩn ở dưới nền DOM web và đẩy thẳng đường dẫn file vào đó bằng code JS (vd: `elementHandle.setInputFiles(...)`).

## 4. Tham số bắt buộc khi tạo ảnh
- Khi gọi Tool tạo ảnh, tham số `ImageName` luôn luôn phải được truyền cứng bằng UUID đặc biệt mà Desktop App quy định. Việc truyền tên lung tung sẽ làm hỏng dữ liệu hiển thị. (Xem thêm trong chuỗi Prompt gốc truyền từ App).

## 5. Xác nhận thao tác bằng `run_command`
- Nếu người dùng yêu cầu hành động (action), Agent không được phép chỉ "nói mồm" bằng Markdown. Phải thực sự gọi tool `run_command` để bash/terminal thực hiện lệnh trên máy tính người dùng. Lời nói chỉ có giá trị sau khi Tool đã thực thi thành công.
