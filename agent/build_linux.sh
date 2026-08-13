#!/bin/bash
echo "Installing requirements..."
pip install --break-system-packages pyinstaller google-antigravity fastapi uvicorn pydantic python-multipart gTTS

echo "Building Linux executable..."
~/.local/bin/pyinstaller ai_agent_linux.spec || pyinstaller ai_agent_linux.spec

echo "Build complete! Check the 'dist/' folder."
