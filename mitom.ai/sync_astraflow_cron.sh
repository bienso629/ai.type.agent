#!/bin/bash
# Script tự động kích hoạt đồng bộ API Keys AstraFlow vào Payload CMS
# Thực thi trực tiếp tại thư mục dự án

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

CRON_SECRET=$(grep '^PAYLOAD_SECRET=' .env | cut -d '=' -f2)
PORT=$(grep '^PORT=' .env | cut -d '=' -f2)
PORT=${PORT:-30000}

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] Bắt đầu kích hoạt đồng bộ Keys AstraFlow qua cron..."

RESPONSE=$(curl -s -m 60 -X POST "http://localhost:${PORT}/api/astraflow/keys" \
  -H "Content-Type: application/json" \
  -H "x-cron-secret: ${CRON_SECRET}" \
  -d '{"mode":"fetch"}')

echo "[$TIMESTAMP] Kết quả: $RESPONSE"
