@echo off
echo Installing requirements...
pip install pyinstaller google-antigravity fastapi uvicorn pydantic python-multipart

echo Building Windows executable...
pyinstaller --name "ai_agent_windows" --onefile ai_agent.py

echo Build complete! Check the 'dist\' folder.
pause
