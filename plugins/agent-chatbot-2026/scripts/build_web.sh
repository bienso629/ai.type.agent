#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WEB_BUILD_DIR="$ROOT_DIR/build/web"
OUTPUT_TAR="$DIST_DIR/agent-chatbot-2026-web-release.tar.gz"

echo "=========================================================="
echo "  Chuan bi & Build ban Website Server (Flutter Web)"
echo "=========================================================="

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

# 1. Kiem tra va build Flutter Web voi renderer canvaskit/html toi uu
echo "--> [1/3] Thuc hien build Flutter Web Release..."
flutter build web --release --base-href "/"

# 2. Dong goi toan bo thu muc build/web thanh tar.gz de de dang upload len hosting/server
echo "--> [2/3] Dong goi thu muc web phan phoi..."
if [ -d "$WEB_BUILD_DIR" ]; then
    cd "$WEB_BUILD_DIR"
    tar -czf "$OUTPUT_TAR" .
    echo "[THANH CONG] Goi Web Release da tao tai: $OUTPUT_TAR"
else
    echo "[LOI] Khong tim thay thu muc $WEB_BUILD_DIR!"
    exit 1
fi

# 3. Kiem tra dung luong va thong tin goi
echo "--> [3/3] Thong tin goi thanh pham:"
ls -lh "$OUTPUT_TAR"

echo "=========================================================="
echo "  HOAN TAT! San pham san sang de deploy len Web Server."
echo "=========================================================="
