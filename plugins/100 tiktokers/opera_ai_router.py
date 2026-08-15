#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
opera_ai_router.py — Opera AI (Aria) Automation & Extraction Router

Chức năng:
Tự động hóa việc gửi câu hỏi tới AI của Opera (Aria) và lấy câu trả lời thông qua Chrome DevTools Protocol (CDP).

Endpoints:
  POST /v1/opera/ai/ask — Gửi câu hỏi cho Opera AI và nhận câu trả lời dạng JSON.
"""

from __future__ import annotations

import time
import json
import asyncio
import logging
from typing import Any, Dict, Optional
from pathlib import Path

import requests
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

# WebSocket client for CDP
try:
    import websocket  # type: ignore
except Exception:
    websocket = None

log = logging.getLogger("opera_ai_router")
router = APIRouter(prefix="/v1/opera/ai", tags=["opera-ai"])

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PROFILES_ROOT = r"D:\OperaProfiles" if Path.home().drive else str(Path.home() / "OperaProfiles")


class AskAIReq(BaseModel):
    profile: str = Field("Profile000", description="Tên Profile Opera đang chạy")
    prompt: str = Field("Chào Aria, hãy giới thiệu ngắn gọn về bản thân bạn.", description="Câu hỏi gửi cho Opera AI")
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT, description="Thư mục root chứa profile")
    host: str = Field(DEFAULT_HOST, description="Host DevTools")
    timeout_s: float = Field(30.0, description="Thời gian chờ tối đa (giây)")


class ClickSuggestionReq(BaseModel):
    profile: str = Field("Profile000", description="Tên Profile Opera đang chạy")
    suggestion_index: int = Field(0, description="Vị trí câu hỏi gợi ý muốn chọn (0 = câu đầu tiên)")
    suggestion_text: Optional[str] = Field(None, description="Nếu chỉ định, sẽ tìm câu gợi ý chứa văn bản này")
    profiles_root: str = Field(DEFAULT_PROFILES_ROOT, description="Thư mục root chứa profile")
    host: str = Field(DEFAULT_HOST, description="Host DevTools")
    timeout_s: float = Field(30.0, description="Thời gian chờ nhận câu trả lời (giây)")


def _is_port_open(port: int, host: str = "127.0.0.1") -> bool:
    import socket
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            return sock.connect_ex((host, port)) == 0
    except Exception:
        return False


def _get_devtools_port(profile_dir: Path) -> Optional[int]:
    """
    Tìm cổng DevTools đang mở của Opera Profile:
    1. Ưu tiên quét tiến trình Opera đang chạy (psutil) để lấy cổng --remote-debugging-port thực tế.
    2. Dự phòng: Đọc từ các file DevToolsActivePort trong thư mục profile.
    """
    pdir_str = str(profile_dir.resolve()).lower()

    # 1. Tìm từ cmdline của tiến trình Opera đang chạy
    try:
        import psutil
        for p in psutil.process_iter(["pid", "name", "cmdline"]):
            try:
                cmdline = p.info.get("cmdline") or []
                cmd_str = " ".join(cmdline).lower()
                if pdir_str in cmd_str:
                    for arg in cmdline:
                        if "--remote-debugging-port=" in arg.lower():
                            port_str = arg.split("=")[-1].strip()
                            if port_str.isdigit():
                                port = int(port_str)
                                if _is_port_open(port):
                                    return port
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
    except Exception:
        pass

    # 2. Dự phòng: Đọc từ file DevToolsActivePort
    for rel in ["DevToolsActivePort", "Default/DevToolsActivePort", "Opera Stable/DevToolsActivePort"]:
        fp = profile_dir / rel
        if fp.exists():
            try:
                content = fp.read_text(encoding="utf-8", errors="ignore").splitlines()
                if content:
                    port = int(content[0].strip())
                    if _is_port_open(port):
                        return port
            except Exception:
                pass

    return None


def _cdp_eval(ws_url: str, expression: str, timeout: float = 10.0) -> Any:
    """Thực thi đoạn mã JS thông qua WebSocket CDP."""
    if not websocket:
        raise RuntimeError("Thư viện 'websocket-client' chưa được cài đặt!")

    ws = websocket.create_connection(ws_url, timeout=timeout, suppress_origin=True)
    try:
        msg_id = 1
        payload = {
            "id": msg_id,
            "method": "Runtime.evaluate",
            "params": {
                "expression": expression,
                "returnByValue": True,
                "awaitPromise": True
            }
        }
        ws.send(json.dumps(payload))
        start_t = time.time()
        while time.time() - start_t < timeout:
            resp = json.loads(ws.recv())
            if resp.get("id") == msg_id:
                res = resp.get("result", {}).get("result", {})
                return res.get("value")
    finally:
        ws.close()
    return None


def _get_aria_ws_url(host: str, port: int) -> str:
    r = requests.get(f"http://{host}:{port}/json", timeout=3.0)
    tabs = r.json()

    target_tab = None
    # CHỈ DÙNG OPERA AI (ARIA) - KHÔNG DÙNG BẤT KỲ FALLBACK KHÁC
    opera_ai_keywords = ["aria.opera.com", "opera-ai", "aria"]
    for tab in tabs:
        url = tab.get("url", "").lower()
        title = tab.get("title", "").lower()
        if any(kw in url or kw in title for kw in opera_ai_keywords) and "404" not in title:
            target_tab = tab
            break

    if not target_tab:
        user_tabs = [
            t for t in tabs
            if t.get("type") == "page" and not t.get("url", "").startswith(("chrome://", "chrome-extension://", "opera://", "about:"))
        ]
        if user_tabs:
            target_tab = user_tabs[0]
            ws_url = target_tab.get("webSocketDebuggerUrl")
            ws = websocket.create_connection(ws_url, timeout=5.0, suppress_origin=True)
            ws.send(json.dumps({"id": 1, "method": "Page.navigate", "params": {"url": "https://aria.opera.com"}}))
            ws.close()
            time.sleep(2.5)

    if not target_tab or "webSocketDebuggerUrl" not in target_tab:
        raise RuntimeError("Không tìm thấy kết nối Opera AI (Aria). Vui lòng mở trợ lý Opera AI (Aria) trong Opera!")

    return target_tab["webSocketDebuggerUrl"]


def _send_cdp_human_input(ws_url: str, prompt: str) -> None:
    """Gửi câu hỏi bằng sự kiện phần cứng CDP (Input.insertText + Enter) để tương thích 100% mọi khung chat AI."""
    ws = websocket.create_connection(ws_url, timeout=10.0, suppress_origin=True)
    try:
        # Focus vào ô nhập liệu
        js_focus = """
        (() => {
            let el = document.querySelector('textarea, #prompt-textarea, [contenteditable="true"], input[type="text"]');
            if (el) {
                el.focus();
                try {
                    let nativeSetter = (Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, "value") || {}).set;
                    if (nativeSetter) nativeSetter.call(el, "");
                } catch(e){}
                return true;
            }
            return false;
        })()
        """
        ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": js_focus, "returnByValue": True}}))
        ws.recv()

        # Gửi chuỗi văn bản qua CDP Input API
        ws.send(json.dumps({"id": 2, "method": "Input.insertText", "params": {"text": prompt}}))
        ws.recv()

        time.sleep(0.3)

        # Bấm phím Enter phần cứng
        ws.send(json.dumps({"id": 3, "method": "Input.dispatchKeyEvent", "params": {"type": "rawKeyDown", "windowsVirtualKeyCode": 13, "key": "Enter", "code": "Enter"}}))
        ws.recv()
        ws.send(json.dumps({"id": 4, "method": "Input.dispatchKeyEvent", "params": {"type": "keyUp", "windowsVirtualKeyCode": 13, "key": "Enter", "code": "Enter"}}))
        ws.recv()

        # Click nút Send làm dự phòng
        js_click_send = """
        (() => {
            let btn = document.querySelector('button[type="submit"], button[aria-label*="Send"], button[aria-label*="Gửi"], button[aria-label*="Ask"], button[data-testid="send-button"]');
            if (btn) btn.click();
        })()
        """
        ws.send(json.dumps({"id": 5, "method": "Runtime.evaluate", "params": {"expression": js_click_send, "returnByValue": True}}))
        ws.recv()
    finally:
        ws.close()


def _extract_ai_response(ws_url: str, timeout_s: float = 25.0) -> Dict[str, Any]:
    """Theo dõi dòng phản hồi (response streaming) và trích xuất câu trả lời đầy đủ."""
    ws = websocket.create_connection(ws_url, timeout=10.0, suppress_origin=True)
    try:
        js_extract = """
        (() => {
            let responseText = "";
            let suggestions = [];

            // 1. Marker-based text parsing (ChatGPT said:, Aria said:, Assistant:, etc.)
            let bodyText = document.body.innerText || "";
            let markers = ["ChatGPT said:", "ChatGPT nói:", "Aria said:", "Aria nói:", "Assistant:", "AI:"];
            for (let m of markers) {
                if (bodyText.includes(m)) {
                    let parts = bodyText.split(m);
                    let rawAns = parts[parts.length - 1].trim();
                    let footerIndex = rawAns.search(/ChatGPT is AI|Terms & Privacy|Log in to get answers|Terms of Service|Chính sách bảo mật/i);
                    if (footerIndex > 0) {
                        rawAns = rawAns.slice(0, footerIndex).trim();
                    }
                    if (rawAns && rawAns.length > 5) {
                        responseText = rawAns;
                        break;
                    }
                }
            }

            // 2. ChatGPT Assistant role selectors
            if (!responseText) {
                let gptMsgs = document.querySelectorAll('[data-message-author-role="assistant"]');
                if (gptMsgs.length > 0) {
                    responseText = gptMsgs[gptMsgs.length - 1].innerText.trim();
                }
            }

            // 3. Generic Markdown / Response message selectors
            if (!responseText) {
                let msgs = document.querySelectorAll('.message-content, .markdown-body, [class*="response"], [class*="message"], article');
                if (msgs.length > 0) {
                    responseText = msgs[msgs.length - 1].innerText.trim();
                }
            }

            // 3. Fallback: Lấy văn bản từ thẻ p hoặc div cuối cùng
            if (!responseText) {
                let main = document.querySelector('main') || document.body;
                let pars = main.querySelectorAll('p, div[class*="content"]');
                if (pars.length > 0) {
                    let lastP = pars[pars.length - 1];
                    responseText = lastP.innerText.trim();
                }
            }

            // Gợi ý tiếp theo (Suggestions)
            let sugElements = document.querySelectorAll(
                'button[class*="suggestion"], div[class*="suggestion"], [class*="prompt-pill"], [class*="follow-up"], .chip-item, button.chip'
            );
            sugElements.forEach(el => {
                let txt = (el.innerText || el.textContent || "").trim();
                if (txt && !suggestions.includes(txt) && txt.length > 2) {
                    suggestions.push(txt);
                }
            });

            return { answer: responseText, suggestions: suggestions };
        })()
        """

        start_t = time.time()
        last_answer = ""
        stable_count = 0

        # Đợi 1.5 giây cho AI bắt đầu trả lời
        time.sleep(1.5)

        while time.time() - start_t < timeout_s:
            ws.send(json.dumps({"id": 10, "method": "Runtime.evaluate", "params": {"expression": js_extract, "returnByValue": True}}))
            resp = json.loads(ws.recv())
            res = resp.get("result", {}).get("result", {}).get("value") or {}
            ans = (res.get("answer") or "").strip()

            if ans and ans in ["Searching the web", "Thinking", "Thinking...", "Deep research...", "Searching...", "Analyzing..."]:
                ans = ""

            if ans and ans == last_answer:
                stable_count += 1
                if stable_count >= 2:  # Văn bản ổn định 2 lần quét liên tiếp -> AI đã sinh lời phản hồi xong
                    return res
            else:
                if ans:
                    last_answer = ans
                    stable_count = 0

            time.sleep(1.0)

        return {"answer": last_answer, "suggestions": []}
    finally:
        ws.close()


def _extract_active_page_context(host: str, port: int) -> Optional[str]:
    """Trích xuất tiêu đề và nội dung chính của trang web người dùng đang xem trong Opera."""
    try:
        r = requests.get(f"http://{host}:{port}/json", timeout=3.0)
        tabs = r.json()
        ai_keywords = ["chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "poe.com", "aria.opera.com", "duck.ai"]

        content_tabs = [
            t for t in tabs
            if t.get("type") == "page"
            and not t.get("url", "").startswith(("chrome://", "chrome-extension://", "opera://", "about:"))
            and not any(kw in t.get("url", "").lower() for kw in ai_keywords)
        ]

        if content_tabs:
            target = content_tabs[0]
            ws_url = target.get("webSocketDebuggerUrl")
            if ws_url:
                ws = websocket.create_connection(ws_url, timeout=3.0, suppress_origin=True)
                js_get_text = """
                (() => {
                    let title = document.title || "";
                    let text = document.body.innerText || "";
                    text = text.replace(/\\s+/g, " ").trim().slice(0, 3000);
                    return { url: window.location.href, title: title, content: text };
                })()
                """
                ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": js_get_text, "returnByValue": True}}))
                resp = json.loads(ws.recv())
                ws.close()
                val = resp.get("result", {}).get("result", {}).get("value")
                if val and val.get("content") and len(val.get("content")) > 30:
                    return f"[Nội dung trang web đang xem: {val.get('title', '')} ({val.get('url', '')})]:\n{val['content']}"
    except Exception:
        pass
    return None


@router.post("/ask")
def ask_opera_ai(req: AskAIReq) -> Dict[str, Any]:
    """
    Gửi câu hỏi cho AI của Opera/ChatGPT và nhận câu trả lời cùng danh sách câu hỏi gợi ý.
    """
    if not websocket:
        raise HTTPException(status_code=500, detail="Vui lòng cài đặt websocket-client: pip install websocket-client")

    pdir = Path(req.profiles_root) / req.profile
    port = _get_devtools_port(pdir)

    if not port:
        raise HTTPException(
            status_code=400,
            detail=f"Profile '{req.profile}' chưa chạy hoặc cổng DevTools đã đóng. Vui lòng bật/khởi động lại profile."
        )

    try:
        ws_url = _get_aria_ws_url(req.host, port)
    except requests.exceptions.RequestException:
        raise HTTPException(
            status_code=400,
            detail=f"Không thể kết nối cổng DevTools ({port}) của '{req.profile}'. Vui lòng bật lại profile."
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    page_context = _extract_active_page_context(req.host, port)
    final_prompt = req.prompt
    if page_context:
        final_prompt = f"{page_context}\n\nYêu cầu của người dùng: {req.prompt}"

    try:
        _send_cdp_human_input(ws_url, final_prompt)
    except Exception as e:
        return {"ok": False, "detail": f"Không thể điền câu hỏi: {e}"}

    extracted = _extract_ai_response(ws_url, timeout_s=req.timeout_s) or {}

    return {
        "ok": True,
        "profile": req.profile,
        "question": req.prompt,
        "answer": extracted.get("answer", ""),
        "suggestions": extracted.get("suggestions", []),
        "suggestion_count": len(extracted.get("suggestions", []))
    }


@router.post("/click-suggestion")
def click_aria_suggestion(req: ClickSuggestionReq) -> Dict[str, Any]:
    """
    Tự động nhấp vào một câu hỏi gợi ý của Aria để AI tiếp tục trả lời.
    """
    if not websocket:
        raise HTTPException(status_code=500, detail="Vui lòng cài đặt websocket-client: pip install websocket-client")

    pdir = Path(req.profiles_root) / req.profile
    port = _get_devtools_port(pdir)

    if not port:
        raise HTTPException(
            status_code=400,
            detail=f"Profile '{req.profile}' chưa chạy hoặc cổng DevTools đã đóng. Vui lòng bật/khởi động lại profile."
        )

    try:
        ws_url = _get_aria_ws_url(req.host, port)
    except requests.exceptions.RequestException:
        raise HTTPException(
            status_code=400,
            detail=f"Không thể kết nối cổng DevTools ({port}) của '{req.profile}'. Vui lòng bật lại profile."
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    match_text_json = json.dumps(req.suggestion_text) if req.suggestion_text else "null"
    idx = int(req.suggestion_index)

    js_click = (
        "(async () => {\n"
        "    let sugElements = Array.from(document.querySelectorAll('button[class*=\"suggestion\"], div[class*=\"suggestion\"], [class*=\"prompt-pill\"], [class*=\"follow-up\"], .chip-item, button.chip'));\n"
        "    if (sugElements.length === 0) return { error: 'Không tìm thấy câu hỏi gợi ý nào trên màn hình' };\n"
        "    let target = null;\n"
        "    let matchTxt = " + match_text_json + ";\n"
        "    if (matchTxt) target = sugElements.find(el => (el.innerText || '').includes(matchTxt));\n"
        "    if (!target && " + str(idx) + " < sugElements.length) target = sugElements[" + str(idx) + "];\n"
        "    if (!target) return { error: 'Không tìm thấy câu gợi ý phù hợp' };\n"
        "    let clickedText = (target.innerText || target.textContent || '').trim();\n"
        "    target.click();\n"
        "    return { success: true, clicked_prompt: clickedText };\n"
        "})()\n"
    )

    res = _cdp_eval(ws_url, js_click, timeout=5.0)
    if isinstance(res, dict) and res.get("error"):
        return {"ok": False, "detail": res["error"]}

    clicked_prompt = res.get("clicked_prompt", "") if isinstance(res, dict) else ""
    extracted = _extract_ai_response(ws_url, timeout_s=req.timeout_s) or {}

    return {
        "ok": True,
        "profile": req.profile,
        "clicked_suggestion": clicked_prompt,
        "answer": extracted.get("answer", ""),
        "new_suggestions": extracted.get("suggestions", [])
    }

