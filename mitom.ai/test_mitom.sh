#!/usr/bin/env bash
curl -s -X POST https://api-vn-sg.mitom.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer uNs6JWCNxWAjQj9m65386fF9-b653-4c9a-9Af6-A4B848C1" \
  -d '{
    "model": "gemini-2.5-flash",
    "messages": [
      {
        "role": "user",
        "content": "Chào bạn, hãy giới thiệu ngắn gọn trong 1 câu bạn là ai và hôm nay thời tiết thế nào?"
      }
    ],
    "temperature": 0.7
  }'
