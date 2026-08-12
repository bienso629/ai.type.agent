# Quy tắc Tích hợp & Định tuyến AI Agent (Sơn Tinh & Mì Tôm AI)

Dưới đây là các nguyên tắc cốt lõi và bắt buộc phải tuân thủ khi tích hợp, gọi API và viết code liên quan đến module **AI Agent** và **Gemini API** trong dự án `ai.type`.

---

## 🛑 1. PHÂN ĐỊNH TUYỆT ĐỐI GIỮA `/api/chat` VÀ `/api/profile/scene/`

Hệ thống chuyên môn hóa 100% nhiệm vụ cho hai nhóm API:

### 💬 Nhóm 1: API `/api/chat` (LLM Agent Chat & Streaming Execution)
- **Chức năng duy nhất**: Trò chuyện thông minh, sinh nội dung (văn bản, hình ảnh, video), phát tổng hợp TTS và thực thi lệnh hệ điều hành.
- **Phương thức & Giao thức**: `POST /api/chat` dạng **Server-Sent Events (SSE)** streaming (`text/event-stream`). Hỗ trợ chế độ Relay WebSocket tới máy trạm PC Agent.
- **Biệt lập nghiệp vụ**:
  1. **KHÔNG CHỨA LOGIC 3D**: Tuyệt đối KHÔNG có bất kỳ logic kiểm tra prompt 3D, KHÔNG nạp ngữ cảnh 3D (`load_all_user_3d_profiles_summary`), KHÔNG đọc/ghi hay can thiệp vào thư mục `Documents/ai.type/data/profiles`, và KHÔNG dính dáng gì tới `/api/profile/scene`.
  2. **Quy tắc Sử dụng AI & Fallback (3 Tầng)**:
     - **Tầng 1 (Ưu tiên số 1)**: AI Agent Sơn Tinh (`https://sontinh.type.vn`). Khi `isAiAgentActive = true`, **bắt buộc** đi qua Sơn Tinh Agent và **ép cứng (force) model `gemini-3.6-flash`**. Nếu Tầng 1 lỗi, **TUYỆT ĐỐI KHÔNG FALLBACK** sang Tầng 2 mà phải báo lỗi trực tiếp.
     - **Tầng 2 (Ưu tiên số 2)**: Mì Tôm AI (Backend ChatGPT API). Chỉ kích hoạt khi Sơn Tinh Agent TẮT và Mì Tôm AI BẬT.
     - **Tầng 3 (Ưu tiên số 3)**: Gemini API Key miễn phí trực tiếp từ Google (`secretKey`). Kích hoạt khi cả 2 tầng trên TẮT.
  3. **Quy tắc Thực thi Hệ điều hành (OS Execution Rules)**:
     - Khi có tác vụ trên máy tính (mở app, xem Youtube, thao tác file, đăng bài), bắt buộc gọi tool `run_command` để bash/terminal thực thi thực tế.
     - Mở GUI/Trình duyệt phải dùng `systemd-run --user` với các biến môi trường Wayland/X11, ưu tiên trình duyệt native (Opera GX).
     - Tìm kiếm YouTube phải dùng `yt-dlp` lấy Video ID trước để mở URL trực tiếp.

---

### 🎨 Nhóm 2: API `/api/profile/scene/` (3D PlayCanvas Data Persistence)
Các endpoint: `/api/profile/scene/{username}` và `/api/profile/scene/assets/{username}/{filename}`.
- **Chức năng duy nhất**: Chỉ xử lý các nghiệp vụ 3D PlayCanvas lưu trữ tại `Documents/ai.type/data/profiles/{username}/` (Nhân vật, Căn phòng 306, Đồ vật Props, Động tác Animations, Kịch bản Events, tệp asset 3D `.glb`, `.png`, `.jpg`...). **TUYỆT ĐỐI KHÔNG xử lý bất kỳ công việc nào khác**.
- **Biệt lập nghiệp vụ**:
  1. **Không xử lý công việc khác**: Không gọi LLM (Gemini/ChatGPT), không chạy chuỗi Fallback AI, không phát stream chat, không tạo giọng nói TTS, không sinh ảnh/video AI.
  2. **Không chứa Side-effect Lệnh OS (No Shell Execution)**: Tuyệt đối KHÔNG thực thi bất kỳ lệnh shell/bash hay gọi `run_command` từ các API này.
  3. **Cơ chế Phân quyền & Xác thực (Auth & Public Access)**:
     - Các endpoint `GET`, `PUT` profile và `POST` upload asset bắt buộc kiểm tra Header `x-api-key == SECRET_AGENT_KEY`.
     - Endpoint `GET /api/profile/scene/assets/{username}/{filename}` là **Public Access** (không yêu cầu Auth) để engine PlayCanvas 3D có thể tải trực tiếp file GLB/Texture.

---

## 2. Định tuyến Máy chủ (Endpoint Routing)
- **Tuyệt đối KHÔNG hardcode** hoặc gọi trực tiếp đến `apiv3.type.vn`. Mọi kết nối API (nếu có) phải được đọc động từ cấu hình: `config.settings.api[user.server]`.
- Mọi lời gọi API đang trỏ tới Localhost (ví dụ: `http://127.0.0.1:54321`) phải được chuyển hướng toàn bộ sang endpoint chính thức của AI Agent plugin là: **`https://sontinh.type.vn`**.

---

## 3. Cấu hình Model (Model Forcing)
- Trong toàn bộ các luồng xử lý mà AI Agent đang active (`isAiAgentActive === true`), **BẮT BUỘC** phải ép cứng (force) tham số model thành **`gemini-3.6-flash`**. 
- Không cho phép hệ thống tự động đổi model hay dùng các model cũ/chậm hơn khi đang ở chế độ Agent Mode.

---

## 4. Quản lý Settings & Cấu hình API Key
- API Key (như `aiAgentApiKey`) và các cấu hình nhạy cảm của người dùng (ví dụ: cookie, secret tokens) chỉ được phép lưu giữ và đồng bộ thông qua `multiAccountService.setItem('settings', settings)`.
- **CẤM** sử dụng lệnh `localStorage.setItem('settings', ...)` ở giao diện (Frontend) để ghi đè hoặc lưu trữ các thông số này, tránh nguy cơ rò rỉ dữ liệu và làm hỏng kiến trúc đồng bộ đa tài khoản.
