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
def execute_terminal_command(command: str) -> str:
    print(f"[AI ĐANG CHẠY LỆNH]: {command}")
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=60)
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

SYSTEM_PROMPT = """Bạn là Tadu Cloud AI Agent - trợ lý quản trị và điều khiển máy chủ Linux thông minh.
Bạn có quyền thực thi lệnh bash/shell trên máy chủ thông qua công cụ `execute_terminal_command`.

NGUYÊN TẮC HOẠT ĐỘNG:
1. Khi người dùng hỏi hoặc yêu cầu làm điều gì liên quan đến hệ thống, bạn HÃY CHỦ ĐỘNG GỌI TOOL `execute_terminal_command` để kiểm tra hoặc thực thi thực tế trên máy chủ.
2. Nếu lệnh đầu tiên không thành công hoặc chưa đủ dữ liệu (ví dụ: không tìm thấy package, cần tìm đường dẫn khác, kiểm tra log...), bạn HÃY TIẾP TỤC GỌI TOOL để chạy các lệnh thay thế/bổ sung (như which, whereis, find, systemctl, dpkg, v.v.).
3. KHÔNG BAO GIỜ dừng lại ở câu nói hứa hẹn như "Để mình kiểm tra tiếp", "Đợi mình một lát" mà KHÔNG gọi tool. Bạn phải thực hiện xong tất cả các bước cần thiết và đưa ra câu trả lời kết luận rõ ràng, đầy đủ nhất cho người dùng.
4. Trình bày kết quả rõ ràng, súc tích bằng tiếng Việt, giải thích ý nghĩa các thông số kỹ thuật nếu cần.
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

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT}
    ]

    # Nạp tối đa 10 lượt trao đổi trước đó để giữ context
    if req.history:
        for h in req.history[-10:]:
            r = h.get("role")
            c = h.get("content")
            if r in ["user", "assistant"] and c:
                messages.append({"role": r, "content": c})

    messages.append({"role": "user", "content": req.message})

    executed_tools = []
    max_turns = 8
    turn = 0
    full_reply = ""

    try:
        while turn < max_turns:
            turn += 1
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                tools=tools,
                tool_choice="auto"
            )
            response_message = response.choices[0].message

            # Nếu AI yêu cầu chạy tool
            if response_message.tool_calls:
                messages.append(response_message)
                for tool_call in response_message.tool_calls:
                    if tool_call.function.name == "execute_terminal_command":
                        try:
                            args = json.loads(tool_call.function.arguments)
                            cmd = args.get("command", "")
                        except Exception:
                            cmd = tool_call.function.arguments

                        yield f"data: {json.dumps({'type': 'status', 'message': f'Đang thực thi: {cmd}'}, ensure_ascii=False)}\n\n"

                        tool_res = execute_terminal_command(cmd)
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

