#!/bin/bash
echo "Installing requirements..."
pip install --break-system-packages pyinstaller google-antigravity fastapi uvicorn pydantic python-multipart gTTS

echo "Building Linux executable..."
# Lệnh này sẽ tạo ra 1 file thực thi duy nhất (--onefile)
# PyInstaller installs to ~/.local/bin if --user is used, or just globally.
~/.local/bin/pyinstaller --name "ai_agent_linux" --onefile --collect-all google.antigravity --hidden-import gtts ai_agent.py || pyinstaller --name "ai_agent_linux" --onefile --collect-all google.antigravity --hidden-import gtts ai_agent.py

echo "Build complete! Check the 'dist/' folder."
