@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo  TẠO BẢN CÀI ĐẶT WINDOWS CHO ỨNG DỤNG MXH TỰ ĐỘNG
echo ========================================================

cd /d "%~dp0\.."

echo [1/3] Đang biên dịch Flutter Windows Release...
call flutter build windows --release

if %ERRORLEVEL% NEQ 0 (
    echo [LỖI] Quá trình build Flutter Windows thất bại!
    echo Vui lòng đảm bảo bạn đang chạy trên Windows và đã cài đặt C++ desktop development trong Visual Studio.
    exit /b %ERRORLEVEL%
)

set DIST_DIR=%~dp0\..\dist-flutter
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo.
echo [2/3] Đang đóng gói bản Portable ZIP...
powershell -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath '%DIST_DIR%\MXH-Tu-Dong-Portable-Windows-x64.zip' -Force"

echo [THÀNH CÔNG] Đã tạo gói Portable tại:
echo %DIST_DIR%\MXH-Tu-Dong-Portable-Windows-x64.zip

echo.
echo [3/3] Đang kiểm tra Inno Setup Compiler để tạo file Setup .exe...
set ISCC_PATH=""

if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" (
    set ISCC_PATH="%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
) else if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" (
    set ISCC_PATH="%ProgramFiles%\Inno Setup 6\ISCC.exe"
)

if not %ISCC_PATH%=="" (
    echo Đang biên dịch Setup Installer bằng Inno Setup...
    %ISCC_PATH% "%~dp0\installer_windows.iss"
    if !ERRORLEVEL! EQU 0 (
        echo [THÀNH CÔNG] Đã tạo file cài đặt: %DIST_DIR%\MXH-Tu-Dong-Setup-x64.exe
    ) else (
        echo [CẢNH BÁO] Không thể tạo file Setup qua Inno Setup.
    )
) else (
    echo [CHÚ Ý] Không tìm thấy Inno Setup 6 (ISCC.exe).
    echo Nếu muốn tạo file Setup tự động cài đặt (.exe), hãy cài Inno Setup tại: https://jrsoftware.org/isdl.php
)

echo.
echo ========================================================
echo  HOÀN TẤT ĐÓNG GÓI CHO WINDOWS!
echo ========================================================
pause
