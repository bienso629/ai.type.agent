import asyncio
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google.antigravity import Agent, LocalAgentConfig, CapabilitiesConfig
import uvicorn

app = FastAPI(title="Mì Tôm AI Chatbot API")

# Định nghĩa cấu trúc dữ liệu gửi lên
class ChatRequest(BaseModel):
    prompt: str
    system_instructions: str = "Bạn là trợ lý AI thông minh, hỗ trợ cho ứng dụng Mì Tôm AI."

# Định nghĩa cấu trúc dữ liệu trả về
class ChatResponse(BaseModel):
    success: bool
    result: str
    error: str = None

@app.post("/api/chat", response_model=ChatResponse)
async def chat_endpoint(req: ChatRequest):
    try:
        # Cấu hình AI Agent với hướng dẫn hệ thống tuỳ chỉnh
        config = LocalAgentConfig(
            system_instructions=req.system_instructions,
            capabilities=CapabilitiesConfig(), # Cho phép AI dùng công cụ khi cần
        )
        
        # Mở một phiên làm việc với Agent
        async with Agent(config) as agent:
            # Gửi tin nhắn và đợi AI trả lời
            response = await agent.chat(req.prompt)
            
            # Trả về kết quả JSON
            return ChatResponse(success=True, result=response.text)
            
    except Exception as e:
        return ChatResponse(success=False, result="", error=str(e))

if __name__ == "__main__":
    # Chạy server FastAPI trên cổng 8000
    uvicorn.run("ai_agent:app", host="0.0.0.0", port=8000, reload=True)
