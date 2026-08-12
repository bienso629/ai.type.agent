# Thứ Tự Ưu Tiên Sử Dụng AI Trong Dự Án (AI Service Hierarchy & Fallback Rules)

Tài liệu này quy định **thứ tự ưu tiên bắt buộc** khi gọi các dịch vụ AI trong toàn bộ dự án (`ai.type`).

---

## 📌 THỨ TỰ ƯU TIÊN GỌI AI (PRIORITY ORDER)

### 🥇 1. Ưu tiên số 1: Sơn Tinh Agent (`https://sontinh.type.vn`)
- **Dịch vụ**: AI Agent Sơn Tinh (`https://sontinh.type.vn`).
- **Nơi bật/tắt & Cấu hình**: **Cài đặt -> Plugins -> AI Agent**.
- **Quy tắc**: Khi tính năng **AI Agent** được BẬT trong cài đặt, **LUÔN LUÔN ƯU TIÊN SỬ DỤNG** `https://sontinh.type.vn` đầu tiên cho mọi thao tác sinh nội dung AI.

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

## ⚙️ SƠ ĐỒ LUỒNG XỬ LÝ (FLOWCHART)

```
                       [Người dùng yêu cầu sinh nội dung AI]
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

## 📝 BẢNG TỔNG HỢP TRẠNG THÁI

| Thứ tự | Tên dịch vụ AI | Vị trí cài đặt cấu hình | Điều kiện kích hoạt |
| :---: | :--- | :--- | :--- |
| **1** | **Sơn Tinh Agent** (`sontinh.type.vn`) | `Cài đặt` -> `Plugins` -> `AI Agent` | BẬT AI Agent trong Plugins (Ưu tiên cao nhất) |
| **2** | **Mì Tôm AI** (Backend ChatGPT) | `Cài đặt` -> `Tài khoản` -> `AI tab` -> `Nâng cao` | AI Agent TẮT + Mì Tôm AI BẬT |
| **3** | **Gemini AI** (Gemini API Key) | `Cài đặt` -> `Tài khoản` -> `AI tab` -> `Gemini API key` | Cả AI Agent và Mì Tôm AI đều TẮT |

