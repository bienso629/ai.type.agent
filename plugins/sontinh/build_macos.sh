#!/bin/bash
echo "Setting up virtual environment..."
python3 -m venv venv
source venv/bin/activate

echo "Installing requirements..."
pip install pyinstaller google-antigravity fastapi uvicorn pydantic python-multipart

echo "Building macOS executable..."
# --onefile tạo ra một file Unix executable duy nhất
pyinstaller --name "ai_agent_macos" --onefile ai_agent.py

echo "Build complete! Check the 'dist/' folder."
deactivate
