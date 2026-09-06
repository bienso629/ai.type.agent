# Mì Tôm AI - API Gateway Reverse Proxy

Dịch vụ Reverse Proxy cho tên miền **`https://api-vn-sg.mitom.ai/v1`** wrap lại **`https://api-us-ca.umodelverse.ai/v1`**.

## Chức năng chính:
1. **Xác thực API Key**: Kiểm tra `x-api-key` hoặc `Authorization: Bearer <API_KEY>` trực tiếp từ Database SQLite của Mì Tôm AI.
2. **Kiểm tra số dư tài khoản**: Chỉ những tài khoản hợp lệ và có số dư > 0 mới được phép forward request sang upstream thật.
3. **Hỗ trợ Streaming SSE**: Đầy đủ tính năng Stream `text/event-stream` cho chat completions.
4. **Tương thích hoàn toàn chuẩn OpenAI**: Hỗ trợ mọi endpoint `/v1/chat/completions`, `/v1/models`, `/v1/embeddings`, v.v.

## Cách chạy thử nghiệm:
```bash
cd api-gateway-proxy
pnpm install
pnpm dev
```
