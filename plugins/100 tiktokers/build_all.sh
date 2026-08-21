#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ELECTRON_DIR="/home/yenai/Documents/Projects/Typing/ai.type/electron"
cd "$DIR"

echo "======================================================="
echo "🚀 1. Building Linux Binary (100tiktok-linux)..."
echo "======================================================="
BIN_NAME=100tiktok-linux pyinstaller --clean -y build.spec
if [ -f "$DIR/dist/100tiktok-linux" ]; then
    cp "$DIR/dist/100tiktok-linux" "$ELECTRON_DIR/100tiktok-linux"
    chmod +x "$ELECTRON_DIR/100tiktok-linux"
    echo "✅ Copied 100tiktok-linux -> $ELECTRON_DIR/100tiktok-linux"
fi

echo ""
echo "======================================================="
echo "🚀 2. Building Windows Binary (100tiktok-win.exe via Docker)..."
echo "======================================================="
if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "$DIR:/src" --entrypoint bash cdrx/pyinstaller-windows:python3 -c \
        "python -m pip install -U pip wheel setuptools pyinstaller && pip install fastapi uvicorn pydantic==2.5.3 httpx requests pycryptodomex websocket-client pychrome psutil && pyinstaller --clean -y --dist ./dist/windows build-win.spec"
    
    if [ -f "$DIR/dist/windows/100tiktok-win.exe" ]; then
        cp "$DIR/dist/windows/100tiktok-win.exe" "$ELECTRON_DIR/100tiktok-win.exe"
        echo "✅ Copied 100tiktok-win.exe -> $ELECTRON_DIR/100tiktok-win.exe"
    fi
else
    echo "⚠️ Docker is not installed or running. Skipped Windows build."
fi

echo ""
echo "======================================================="
echo "🎉 Build process finished!"
echo "======================================================="
