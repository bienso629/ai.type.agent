import os
import subprocess
import json
import time
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel
from openai import OpenAI

app = FastAPI(title="AI Agent Server", description="Dịch vụ AI Agent thực thi lệnh hệ thống đa bước (Hỗ trợ Streaming)")

# Token bảo mật nội bộ giữa App Client và Server của bạn
MY_SECRET_TOKEN = os.environ.get("SECRET_TOKEN") or os.environ.get("AGENT_SECRET_TOKEN", "super_secret_token_123")

# Khởi tạo OpenAI Client kết nối qua Proxy (Lấy từ biến môi trường của Systemd)
client = OpenAI(
    base_url=os.environ.get("PROXY_BASE_URL") or os.environ.get("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"), 
    api_key=os.environ.get("PROXY_API_KEY") or os.environ.get("OPENROUTER_API_KEY", "")
)
MODEL_NAME = os.environ.get("AI_MODEL", "glm-5.3")

# 1. Kỹ năng (Tool) của AI: Thực thi lệnh hệ thống
def execute_terminal_command(command: str, working_dir: Optional[str] = None) -> str:
    print(f"[AI ĐANG CHẠY LỆNH]: {command} (cwd={working_dir})")
    try:
        env = os.environ.copy()
        env["PATH"] = f"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/root/.local/bin:{env.get('PATH', '')}"
        cwd = working_dir if (working_dir and os.path.isdir(working_dir)) else None
        result = subprocess.run(command, shell=True, executable="/bin/bash", capture_output=True, text=True, timeout=60, env=env, cwd=cwd)
        if result.returncode == 0:
            return result.stdout if result.stdout else "Lệnh chạy thành công, không có output."
        return f"Mã thoát ({result.returncode}): {result.stderr or result.stdout}"
    except Exception as e:
        return f"Lỗi thực thi: {str(e)}"

# 2. Health check
@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "model": MODEL_NAME,
        "proxy_base_url": os.environ.get("PROXY_BASE_URL", "https://openrouter.ai/api/v1")
    }

# 3. API Endpoint nhận lệnh từ App Client với Multi-step Streaming Agent Loop
class PromptRequest(BaseModel):
    message: str
    history: Optional[List[Dict[str, Any]]] = []
    working_dir: Optional[str] = None

SYSTEM_PROMPT = """Bạn là Tadu Cloud AI Agent - Kỹ sư DevOps Linux thực chiến cấp cao.
Bạn có quyền thực thi lệnh bash/shell thực tế trên máy chủ qua công cụ `execute_terminal_command`.

CÁC QUY TẮC BẮT BUỘC (VI PHẠM LÀ LỖI NGHIÊM TRỌNG):

1. TẬP TRUNG ĐÚNG 100% TRỌNG TÂM YÊU CẦU MỚI (STRICT SCOPE):
   - CHỈ kiểm tra và trả lời ĐÚNG DUY NHẤT đối tượng/domain/dịch vụ mà người dùng đang hỏi trong tin nhắn mới nhất.
   - TUYỆT ĐỐI KHÔNG kiểm tra lại hoặc liệt kê lại các domain, website, service khác đã hoàn thành ở các lượt trước (ví dụ: WordPress, SSL Blog, N8N...) trừ khi người dùng đích danh yêu cầu.
   - Lịch sử trò chuyện (`history`) CHỈ dùng để hiểu các đại từ liên hệ (như "nó", "cài đặt đi", "sửa lỗi đó"). CẤM tóm tắt lại toàn bộ lịch sử trò chuyện.

2. HÀNH ĐỘNG TIẾP NỐI - KHÔNG LÀM LẠI TỪ ĐẦU (CONTINUATION ACTION):
   - Khi người dùng ra lệnh tiếp nối ("Cài đặt đi", "Làm luôn đi", "Sửa đi", "Restart lại"): Dựa vào thông tin đã chẩn đoán ở lượt trước và BẮT TAY NGAY VÀO BƯỚC THỰC THI/CÀI ĐẶT. TUYỆT ĐỐI KHÔNG chạy lại quy trình kiểm tra ban đầu từ con số 0.

3. KẾT LUẬN NGẮN GỌN, LOGIC & ĐÚNG BẢN CHẤT (ZERO FLUFF):
   - Đi thẳng vào câu trả lời cốt lõi trong 1-3 câu ngắn gọn.
   - Cấu trúc: [Câu trả lời/Trạng thái trực tiếp] -> [Nguyên nhân kỹ thuật gốc rễ (nếu có lỗi)] -> [Hành động/Giải pháp cụ thể].
   - CẤM: Không chào hỏi, không cảm ơn, không văn mẫu xã giao, không liệt kê lại các bảng thông tin thừa thãi không được hỏi.
"""

def generate_agent_stream(req: PromptRequest):
    tools = [{
        "type": "function",
        "function": {
            "name": "execute_terminal_command",
            "description": "Thực thi lệnh terminal bash/shell trên server Linux.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Lệnh bash cần chạy"}
                },
                "required": ["command"]
            }
        }
    }]

    current_sys_prompt = SYSTEM_PROMPT
    if req.working_dir:
        current_sys_prompt += f"""

🎯 PHẠM VI LÀM VIỆC ĐƯỢC GIỚI HẠN (WORKING DIRECTORY SCOPE):
- Thư mục làm việc mục tiêu: `{req.working_dir}`
- QUY TẮC BẢO VỆ PHẠM VI:
  1. Mọi lệnh bash, thao tác file và sửa đổi code/cấu hình PHẢI THỰC HIỆN TẠI HOẶC BÊN TRONG `{req.working_dir}`.
  2. Mọi lệnh terminal phải tự động chạy với tiền tố `cd {req.working_dir} && ...` hoặc trỏ trực tiếp đến các file bên trong thư mục này.
  3. TUYỆT ĐỐI KHÔNG can thiệp, sửa đổi hoặc xoá các file/service nằm ngoài phạm vi `{req.working_dir}` nếu không được yêu cầu cụ thể.
"""

    messages = [
        {"role": "system", "content": current_sys_prompt}
    ]

    # Nạp tối đa 4 tin nhắn gần nhất để giữ ngữ cảnh, cắt gọn tin nhắn cũ để chống ám thị lặp lại báo cáo thừa
    if req.history:
        for h in req.history[-4:]:
            r = h.get("role")
            c = h.get("content", "")
            if r in ["user", "assistant"] and c:
                if r == "assistant" and len(c) > 500:
                    c = c[:500] + "... [nội dung trước]"
                messages.append({"role": r, "content": c})

    messages.append({"role": "user", "content": req.message})

    executed_tools = []
    executed_commands = []
    max_turns = 25
    turn = 0
    full_reply = ""

    try:
        while turn < max_turns:
            turn += 1
            # Ở lượt thứ 25 nếu vẫn chưa dừng, tắt tools để ép mô hình tổng hợp toàn bộ kết quả
            current_tools = None if turn == max_turns else tools
            current_tool_choice = None if turn == max_turns else "auto"

            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                tools=current_tools,
                tool_choice=current_tool_choice,
                temperature=0.1
            )
            response_message = response.choices[0].message

            # Nếu AI yêu cầu chạy tool
            if response_message.tool_calls and current_tools is not None:
                messages.append(response_message)
                should_break_loop = False

                for tool_call in response_message.tool_calls:
                    if tool_call.function.name == "execute_terminal_command":
                        try:
                            args = json.loads(tool_call.function.arguments)
                            cmd = args.get("command", "").strip()
                        except Exception:
                            cmd = str(tool_call.function.arguments).strip()

                        # Phát hiện vòng lặp vô tận: nếu 1 lệnh bị gọi giống hệt 3 lần liên tiếp
                        executed_commands.append(cmd)
                        if len(executed_commands) >= 3 and executed_commands[-1] == executed_commands[-2] == executed_commands[-3]:
                            tool_res = f"[HỆ THỐNG]: Đã phát hiện lệnh lặp lại 3 lần liên tiếp: '{cmd}'. Vui lòng phân tích lỗi và đưa ra giải pháp thay vì chạy lại lệnh cũ."
                            should_break_loop = True
                        else:
                            yield f"data: {json.dumps({'type': 'status', 'message': f'Đang thực thi: {cmd}'}, ensure_ascii=False)}\n\n"
                            tool_res = execute_terminal_command(cmd, working_dir=req.working_dir)

                        tool_item = {
                            "tool": "execute_terminal_command",
                            "command": cmd,
                            "output": tool_res
                        }
                        executed_tools.append(tool_item)

                        yield f"data: {json.dumps({'type': 'tool', 'tool': tool_item}, ensure_ascii=False)}\n\n"

                        messages.append({
                            "role": "tool",
                            "tool_call_id": tool_call.id,
                            "name": tool_call.function.name,
                            "content": tool_res
                        })

                # Tiếp tục vòng lặp cho turn tiếp theo
                continue
            else:
                # Không gọi tool nữa, đây là câu trả lời kết luận
                reply_text = response_message.content or ""
                full_reply = reply_text

                # Bắn từng từ ra SSE stream để giao diện hiển thị mượt mà
                words = reply_text.split(" ")
                for idx, w in enumerate(words):
                    token = w + (" " if idx < len(words) - 1 else "")
                    yield f"data: {json.dumps({'type': 'token', 'delta': token}, ensure_ascii=False)}\n\n"
                    time.sleep(0.012)
                break

        # Đảm bảo 100% luôn có câu kết luận nếu vòng lặp kết thúc mà full_reply vẫn rỗng
        if not full_reply:
            try:
                final_res = client.chat.completions.create(
                    model=MODEL_NAME,
                    messages=messages,
                    temperature=0.1
                )
                full_reply = final_res.choices[0].message.content or ""
                words = full_reply.split(" ")
                for idx, w in enumerate(words):
                    token = w + (" " if idx < len(words) - 1 else "")
                    yield f"data: {json.dumps({'type': 'token', 'delta': token}, ensure_ascii=False)}\n\n"
                    time.sleep(0.012)
            except Exception as e:
                print(f"Lỗi tạo kết luận cuối: {e}")

        yield f"data: {json.dumps({'type': 'done', 'reply': full_reply, 'tool_calls': executed_tools}, ensure_ascii=False)}\n\n"

    except Exception as e:
        err_msg = f"Lỗi Agent: {str(e)}"
        yield f"data: {json.dumps({'type': 'error', 'message': err_msg}, ensure_ascii=False)}\n\n"

@app.post("/ai_agent")
def chat_with_agent(req: PromptRequest, x_api_token: str = Header(None)):
    if x_api_token != MY_SECRET_TOKEN:
        raise HTTPException(status_code=401, detail="Token không hợp lệ!")
    return StreamingResponse(generate_agent_stream(req), media_type="text/event-stream")

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("AGENT_PORT") or os.environ.get("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port)

