@echo off
echo ====================================================
echo  Building AI Type Agent Flutter for Windows
echo ====================================================

cd /d "%~dp0\.."
call flutter build windows --release

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter Windows build failed!
    exit /b %ERRORLEVEL%
)

set DIST_DIR=%~dp0\..\..\dist-flutter
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo Packaging Windows release bundle...
powershell -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath '%DIST_DIR%\tadu-cloud-ai-agent-flutter-windows-x64.zip' -Force"

echo [SUCCESS] Windows package created at: %DIST_DIR%\tadu-cloud-ai-agent-flutter-windows-x64.zip
