# Thứ Tự Ưu Tiên Sử Dụng AI Trong Dự Án (AI Service Hierarchy & Fallback Rules)

Tài liệu này quy định **thứ tự ưu tiên bắt buộc** và **sự phân định nhiệm vụ tuyệt đối** giữa các API trong toàn bộ dự án (`ai.type`).

---

## ⚠️ 0. PHÂN ĐỊNH TUYỆT ĐỐI GIỮA `/api/chat` VÀ `/api/profile/scene/`

Hệ thống chia làm **2 nhóm API chuyên biệt**:

1. **Nhóm API Chat & Sinh nội dung AI (`/api/chat`)**:
   - Áp dụng quy trình **Ưu tiên 3 Tầng & Fallback Rules** bên dưới (Sơn Tinh -> Mì Tôm -> Gemini Direct).
   - **HOÀN TOÀN KHÔNG CHỨA LOGIC 3D**, không đụng tới `Documents/ai.type/data/profiles`, và không dính dáng gì tới `/api/profile/scene`.
2. **Nhóm API Dữ liệu 3D Profile (`/api/profile/scene/`)**:
   - **CHỈ XỬ LÝ NGHIỆP VỤ 3D PLAYCANVAS** nằm trong `Documents/ai.type/data/profiles/{username}/` (GET/PUT profile JSON, POST/GET 3D asset GLB/texture).
   - **TUYỆT ĐỐI KHÔNG XỬ LÝ BẤT KỲ CÔNG VIỆC GÌ KHÁC** (không gọi LLM, không qua chuỗi Fallback AI, không thực thi lệnh OS, không sinh ảnh/video/TTS).

---

## 📌 THỨ TỰ ƯU TIÊN GỌI AI CHO `/api/chat` (PRIORITY ORDER)

### 🥇 1. Ưu tiên số 1: Sơn Tinh Agent (`https://sontinh.type.vn`)
- **Dịch vụ**: AI Agent Sơn Tinh (`https://sontinh.type.vn`).
- **Nơi bật/tắt & Cấu hình**: **Cài đặt -> Plugins -> AI Agent**.
- **Quy tắc**: Khi tính năng **AI Agent** được BẬT trong cài đặt (`isAiAgentActive = true`), **LUÔN LUÔN ƯU TIÊN SỬ DỤNG** `https://sontinh.type.vn` đầu tiên cho mọi thao tác sinh nội dung AI. Bắt buộc ép cứng model `gemini-3.6-flash`. Nếu Tầng 1 gặp lỗi, **KHÔNG FALLBACK** sang Tầng 2.

---

### 🥈 2. Ưu tiên số 2: Mì Tôm AI (Backend ChatGPT API)
- **Dịch vụ**: Mì Tôm AI (Endpoint `/blog/chatgpt/2025/answear` - ChatGPT API).
- **Nơi bật/tắt & Cấu hình**: **Cài đặt -> Tài khoản -> AI tab** (Khu vực Nâng cao của cấu hình Mì Tôm AI).
- **Quy tắc**: Chỉ sử dụng Mì Tôm AI khi **Sơn Tinh Agent (`sontinh.type.vn`) đang bị TẮT**, và Mì Tôm AI đang ở trạng thái **BẬT**.

---

### 🥉 3. Ưu tiên số 3: Gemini AI Miễn Phí (Gemini API Key)
- **Dịch vụ**: Gemini AI miễn phí trực tiếp từ Google (`secretKey`).
- **Nơi bật/tắt & Cấu hình**: **Cài đặt -> Tài khoản -> AI tab** (Khu vực nhập `Gemini API key` / `secretKey`).
- **Quy tắc**: Chỉ sử dụng Gemini AI khi **CẢ 2 THẰNG TRÊN ĐỀU KHÔNG ĐƯỢC BẬT** (Cả Sơn Tinh Agent và Mì Tôm AI đều TẮT).

---

## ⚙️ SƠ ĐỒ LUỒNG XỬ LÝ CHO `/api/chat` (FLOWCHART)

```
                       [Người dùng yêu cầu sinh nội dung AI / Chat]
                                          │
                                          ▼
                      ┌───────────────────────────────────────┐
                      │ Kiểm tra: Sơn Tinh Agent có BẬT không? │
                      │   (Cài đặt -> Plugins -> AI Agent)    │
                      └───────────────────┬───────────────────┘
                                          │
                         ┌────────────────┴────────────────┐
                      BẬT│                                 │TẮT
                         ▼                                 ▼
          ┌─────────────────────────────┐   ┌───────────────────────────────────────────┐
          │ Dùng https://sontinh.type.vn│   │ Kiểm tra: Mì Tôm AI có được BẬT không?   │
          │     (Sơn Tinh AI Agent)     │   │(Cài đặt -> Tài khoản -> AI -> Nâng cao)  │
          └─────────────────────────────┘   └─────────────────────┬─────────────────────┘
                                                                  │
                                                 ┌────────────────┴────────────────┐
                                              BẬT│                                 │TẮT
                                                 ▼                                 ▼
                                  ┌─────────────────────────────┐   ┌─────────────────────────────┐
                                  │      Dùng Mì Tôm AI         │   │   Dùng Gemini AI Miễn Phí   │
                                  │   (/blog/chatgpt/2025/...)  │   │(Cài đặt->Tài khoản->AI key) │
                                  └─────────────────────────────┘   └─────────────────────────────┘
```

---

## 🎨 BẢNG PHÂN ĐỊNH BIỆT LẬP

| Tiêu chí | `/api/chat` | `/api/profile/scene/` |
| :--- | :--- | :--- |
| **Nhiệm vụ duy nhất** | Trò chuyện AI, sinh nội dung, phát TTS, thực thi lệnh máy tính | Chỉ đọc/ghi và lưu trữ dữ liệu 3D PlayCanvas tại `Documents/ai.type/data/profiles/{username}/` |
| **Công việc khác** | Không chứa logic 3D | **Tuyệt đối Không** (không gọi LLM, không thực thi OS, không tạo TTS/media) |
| **Liên kết giữa 2 API** | **Không dính dáng** | **Không dính dáng** |
| **Giao thức** | Streaming SSE (`text/event-stream`) / WebSocket Relay | Standard REST JSON (GET/PUT) & Asset Upload/Download |
| **Chuỗi Fallback AI** | Sơn Tinh -> Mì Tôm -> Gemini Direct | **Không áp dụng** (REST Data trực tiếp) |
| **Thực thi OS (bash/run_command)** | Có (khi người dùng yêu cầu thao tác máy tính) | **Tuyệt đối Không** |
