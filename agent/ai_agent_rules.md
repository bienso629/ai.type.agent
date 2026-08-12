# Quy tắc Tích hợp & Định tuyến AI Agent (Sơn Tinh & Mì Tôm AI)

Dưới đây là các nguyên tắc cốt lõi và bắt buộc phải tuân thủ khi viết code liên quan đến module **AI Agent** và luồng xử lý của **Gemini API** trong dự án.

## 1. Định tuyến Máy chủ (Endpoint Routing)
- **Tuyệt đối KHÔNG hardcode** hoặc gọi trực tiếp đến `apiv3.type.vn`. Mọi kết nối API (nếu có) phải được đọc động từ cấu hình: `config.settings.api[user.server]`.
- Mọi lời gọi API đang trỏ tới Localhost (ví dụ: `http://127.0.0.1:54321`) phải được chuyển hướng toàn bộ sang endpoint chính thức của AI Agent plugin là: **`https://sontinh.type.vn`**.

## 2. Quy tắc Dự phòng (Fallback Logic)
Kiến trúc AI của chúng ta chia làm 2 tầng:
- **Tầng 1 (AI Agent):** `sontinh.type.vn` (Hoạt động thông qua Plugin AI Agent của Electron/Local).
- **Tầng 2 (Web AI):** Mì Tôm AI (API xử lý AI chung trên nền web).

**Quy tắc:**
Khi biến trạng thái **`isAiAgentActive`** (hoặc Plugin AI Agent) đang được **BẬT**, luồng xử lý bắt buộc phải đi qua **Tầng 1 (`sontinh.type.vn`)**. 
- Nếu Tầng 1 gặp lỗi (timeout, crash, hết quota...), **KHÔNG ĐƯỢC PHÉP FALLBACK** (chuyển hướng dự phòng) về Tầng 2 (Mì Tôm AI). 
- Hãy throw error và báo lỗi thẳng cho người dùng để họ kiểm tra lại kết nối/API Key của AI Agent. Việc fallback về Tầng 2 trong trạng thái này sẽ phá vỡ tính nhất quán của Agent.

## 3. Cấu hình Model (Model Forcing)
- Trong toàn bộ các luồng xử lý mà AI Agent đang active (`isAiAgentActive === true`), **BẮT BUỘC** phải ép cứng (force) tham số model thành **`gemini-3.6-flash`**. 
- Không cho phép hệ thống tự động đổi model hay dùng các model cũ/chậm hơn khi đang ở chế độ Agent Mode.

## 4. Quản lý Settings & Cấu hình API Key
- API Key (như `aiAgentApiKey`) và các cấu hình nhạy cảm của người dùng (ví dụ: cookie, secret tokens) chỉ được phép lưu giữ và đồng bộ thông qua `multiAccountService.setItem('settings', settings)`.
- **CẤM** sử dụng lệnh `localStorage.setItem('settings', ...)` ở giao diện (Frontend) để ghi đè hoặc lưu trữ các thông số này, tránh nguy cơ rò rỉ dữ liệu và làm hỏng kiến trúc đồng bộ đa tài khoản.
- Lịch sử mục tiêu (KPI) của domain (`domainTargets`) được lưu ở dạng Cây thư mục `Năm -> Tháng -> KPI` nằm trong `settings` của tài khoản để đảm bảo các báo cáo thống kê luôn giữ được dữ liệu cũ khi mục tiêu thay đổi ở tương lai.
