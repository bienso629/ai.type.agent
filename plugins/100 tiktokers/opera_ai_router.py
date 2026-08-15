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


def _get_devtools_port(profile_dir: Path) -> Optional[int]:
    """Đọc cổng DevTools từ file DevToolsActivePort trong profile."""
    active_port_file = profile_dir / "DevToolsActivePort"
    if not active_port_file.exists():
        active_port_file = profile_dir / "Default" / "DevToolsActivePort"

    if active_port_file.exists():
        try:
            content = active_port_file.read_text(encoding="utf-8").strip().splitlines()
            if content:
                return int(content[0].strip())
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
    for tab in tabs:
        url = tab.get("url", "")
        if "aria.opera.com" in url or "opera-ai" in url:
            target_tab = tab
            break

    if not target_tab:
        page_tabs = [t for t in tabs if t.get("type") == "page"]
        if page_tabs:
            target_tab = page_tabs[0]
            ws_url = target_tab.get("webSocketDebuggerUrl")
            ws = websocket.create_connection(ws_url, timeout=5.0, suppress_origin=True)
            ws.send(json.dumps({"id": 1, "method": "Page.navigate", "params": {"url": "https://aria.opera.com"}}))
            ws.close()
            time.sleep(2.5)

    if not target_tab or "webSocketDebuggerUrl" not in target_tab:
        raise RuntimeError("Không tìm thấy webSocketDebuggerUrl của Opera!")

    return target_tab["webSocketDebuggerUrl"]


@router.post("/ask")
def ask_opera_ai(req: AskAIReq) -> Dict[str, Any]:
    """
    Gửi câu hỏi cho AI của Opera (Aria) và nhận câu trả lời cùng danh sách câu hỏi gợi ý.
    """
    if not websocket:
        raise HTTPException(status_code=500, detail="Vui lòng cài đặt websocket-client: pip install websocket-client")

    pdir = Path(req.profiles_root) / req.profile
    port = _get_devtools_port(pdir)

    if not port:
        raise HTTPException(
            status_code=400,
            detail=f"Profile '{req.profile}' chưa chạy hoặc không mở DevTools port! Hãy bật profile trước."
        )

    try:
        ws_url = _get_aria_ws_url(req.host, port)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    # 1. Điền câu hỏi và gửi
    prompt_escaped = json.dumps(req.prompt)
    js_inject = f"""
    (async () => {{
        let input = document.querySelector('textarea, div[contenteditable="true"], input[type="text"]');
        if (!input) return {{ error: "Không tìm thấy ô nhập câu hỏi của Aria" }};

        input.focus();
        if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {{
            input.value = {prompt_escaped};
        }} else {{
            input.innerText = {prompt_escaped};
        }}
        input.dispatchEvent(new Event('input', {{ bubbles: true }}));
        input.dispatchEvent(new Event('change', {{ bubbles: true }}));

        let sendBtn = document.querySelector('button[type="submit"], button[aria-label*="Send"], button[aria-label*="Gửi"]');
        if (sendBtn) {{
            sendBtn.click();
        }} else {{
            input.dispatchEvent(new KeyboardEvent('keydown', {{ key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }}));
        }}
        return {{ success: true }};
    }})()
    """

    res = _cdp_eval(ws_url, js_inject, timeout=5.0)
    if isinstance(res, dict) and res.get("error"):
        return {"ok": False, "detail": res["error"]}

    # 2. Đợi và trích xuất câu trả lời + câu hỏi gợi ý (Suggestions)
    js_extract = """
    (async () => {
        let responseText = "";
        let messages = document.querySelectorAll('.message-content, .markdown-body, [class*="response"], [class*="message"], article');
        if (messages.length > 0) {
            responseText = (messages[messages.length - 1].innerText || "").trim();
        }

        let suggestions = [];
        let sugElements = document.querySelectorAll(
            'button[class*="suggestion"], div[class*="suggestion"], [class*="prompt-pill"], [class*="follow-up"], .chip-item, button.chip'
        );
        sugElements.forEach(el => {
            let txt = (el.innerText || el.textContent || "").trim();
            if (txt && !suggestions.includes(txt) && txt.length > 2) {
                suggestions.push(txt);
            }
        });

        return {
            answer: responseText,
            suggestions: suggestions
        };
    })()
    """

    time.sleep(3.5)
    extracted = _cdp_eval(ws_url, js_extract, timeout=req.timeout_s) or {}

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
            detail=f"Profile '{req.profile}' chưa chạy hoặc không mở DevTools port!"
        )

    try:
        ws_url = _get_aria_ws_url(req.host, port)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    match_text = json.dumps(req.suggestion_text) if req.suggestion_text else "null"
    idx = int(req.suggestion_index)

    js_click = f"""
    (async () => {{
        let sugElements = Array.from(document.querySelectorAll(
            'button[class*="suggestion"], div[class*="suggestion"], [class*="prompt-pill"], [class*="follow-up"], .chip-item, button.chip'
        ));

        if (sugElements.length === 0) {{
            return {{ error: "Không tìm thấy câu hỏi gợi ý nào trên màn hình" }};
        }}

        let target = null;
        let matchTxt = {match_text};
        if (matchTxt) {{
            target = sugElements.find(el => (el.innerText || "").includes(matchTxt));
        }}

        if (!target && {idx} < sugElements.length) {{
            target = sugElements[{idx}];
        }}

        if (!target) {{
            return {{ error: "Không tìm thấy câu gợi ý phù hợp" }};
        }}

        let clickedText = (target.innerText || target.textContent || "").trim();
        target.click();
        return {{ success: true, clicked_prompt: clickedText }};
    }})()
    """

    res = _cdp_eval(ws_url, js_click, timeout=5.0)
    if isinstance(res, dict) and res.get("error"):
        return {"ok": False, "detail": res["error"]}

    clicked_prompt = res.get("clicked_prompt", "") if isinstance(res, dict) else ""

    time.sleep(3.5)
    js_extract = """
    (async () => {
        let responseText = "";
        let messages = document.querySelectorAll('.message-content, .markdown-body, [class*="response"], [class*="message"], article');
        if (messages.length > 0) {
            responseText = (messages[messages.length - 1].innerText || "").trim();
        }

        let suggestions = [];
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

    extracted = _cdp_eval(ws_url, js_extract, timeout=req.timeout_s) or {}

    return {
        "ok": True,
        "profile": req.profile,
        "clicked_suggestion": clicked_prompt,
        "answer": extracted.get("answer", ""),
        "new_suggestions": extracted.get("suggestions", [])
    }

