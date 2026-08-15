# 100tiktok Opera Profiles — API & Controller

Bộ đôi công cụ giúp bạn **quản lý (tạo/xoá/bật/tắt) profile Opera** và **điều khiển bằng tự động hoá (Playwright/CDP)**.  
Mặc định mọi **đường dẫn có thể viết _tương đối_** theo thư mục đặt dự án.

- API: `opera_api.py` — FastAPI quản lý profile, VPN patch, CPU affinity/priority, hooks PowerShell…
- Controller: `opera_controller.py` — Python điều khiển Opera qua **Chrome DevTools Protocol** (Playwright), **luôn chọn tab đầu tiên**.

> Windows-first, Python 3.9+ (khuyên dùng 3.10+).  
> Không cần cài Chrome/Chromium cho Playwright vì ta **kết nối CDP** vào Opera đang chạy.

python app.py --tunnel ngrok --ngrok --ngrok-url pandurate-substantival-corazon.ngrok-free.app --ngrok-authtoken 32U4QGD3lQJ9ZFJxNOTtndK4pJ9_4fgqiTm4gzsLCTnhbHv4M

hoặc bây giờ chơi với cloudflare thì chạy:

uvicorn app:app --host 0.0.0.0 --port 8000

# hoặc:

python app.py --tunnel cloudflared --cloudflared-bin ./cloudflared.exe --cloudflared-args "tunnel --url http://localhost:8000 --protocol http2"

# hoặc:

uvicorn app:app --host 0.0.0.0 --port 8000
./cloudflared.exe --config C:\Users\WING386\.cloudflared\config.yml tunnel run


Opera Multi-Profile Kit — v2 (Wing386 preset)
=================================================
Config: opera_profiles.config.json
- OperaExe        = C:\Users\Wing386\AppData\Local\Programs\Opera\opera.exe
- ProfilesRoot    = D:\OperaProfiles
- BaseTemplateDir = D:\OperaProfiles\_BaseTemplate
- LauncherDir     = D:\OperaProfiles\Launchers
- Count=100, ProfilePrefix="Profile", StartIndex=1

Quick start:
1) Launch_Template.bat -> enable VPN in Opera -> close Opera.
2) Opera_MakeProfiles_v2.ps1 -> creates profiles + .bat launchers inside D:\OperaProfiles\Launchers
3) Open_Profiles_Range.ps1 -From 1 -To 10 -MaxParallel 5
4) Cleanup_Profiles.ps1 -DeleteProfiles -DeleteLaunchers

Customize:
- Edit opera_profiles.config.json or override via parameters, e.g.:
  powershell -ExecutionPolicy Bypass -File .\Opera_MakeProfiles_v2.ps1 -Count 50 -ProfilePrefix Acc -StartIndex 101 -LauncherDir "D:\OperaProfiles\Launchers2"

### Hướng dẫn cài trên Windows
Mở PowerShell (Win+X → Windows PowerShell / Windows Terminal).

1. Đi tới thư mục dự án của bạn:
Set-Location 'C:\Users\Wing386\Documents\GitHub\100tiktok'

2. (Nếu bạn vừa tải zip v2) giải nén vào đây:
Expand-Archive '.\Opera_MultiProfile_Kit_Wing386_v2.zip' -DestinationPath . -Force

3. Mở template để bật VPN lần đầu:
& '.\Launch_Template.bat'

4. → Trong Opera: Settings → Advanced/Features → bật Enable VPN → đóng Opera.

5. Chạy script tạo profile (không cần đổi ExecutionPolicy toàn máy):
powershell -ExecutionPolicy Bypass -File '.\Opera_MakeProfiles_v2.ps1'

6. (hoặc tuỳ biến tham số)
powershell -ExecutionPolicy Bypass -File '.\Opera_MakeProfiles_v2.ps1' `
  -Count 100 -ProfilePrefix 'Profile' -StartIndex 1

7. Mở một loạt profile (ví dụ 1 → 7, tối đa 50 cửa sổ song song):
powershell -ExecutionPolicy Bypass -File '.\Open_Profiles_Range.ps1' -From 1 -To 7 -MaxParallel 50 -DelayMs 700

---

### Đóng gói EXE
pip install -U pystray pillow

pyinstaller --clean --noconfirm --name 100TikTok --onefile --windowed --icon "assets\100tiktok.ico" --version-file version_info.txt --add-binary "ngrok.exe;." --add-data "assets\tray.png;assets" --hidden-import profiles_router --hidden-import search_click_router --hidden-import like_click_router --hidden-import captcha_auto_router --hidden-import comment_click_router opera_api.py

## 1) Cấu trúc thư mục gợi ý

100tiktok/
├─ opera_api.py
├─ opera_controller.py
├─ opera_profiles.config.json # file cấu hình (có thể tương đối)
├─ profiles/ # nơi chứa các profile Opera
├─ launchers/ # nơi sinh file .bat
├─ _BaseTemplate/ # template profile (tuỳ chọn)
├─ scripts/ # PowerShell scripts (tuỳ chọn)
├─ requirements.txt
└─ Opera_Profiles_API.postman_collection.json

---

## 2) Cài đặt

bash
# (Khuyến nghị) tạo venv
python -m venv .venv
.\.venv\Scripts\activate    # trên Windows PowerShell
# source .venv/bin/activate # trên Linux/macOS

# Cài phụ thuộc
pip install -r requirements.txt

## 3) Chạy

## Cấu hình

GET /v1/opera/config — xem config hiện tại.

PUT /v1/opera/config — cập nhật toàn bộ cấu hình.

Quản lý profile

GET /v1/opera/profiles — liệt kê tất cả profiles (đang chạy hay không, PIDs).

GET /v1/opera/profiles/{name} — thông tin 1 profile.

POST /v1/opera/profiles/create — tạo mới (theo from_config hoặc names/indexes/count/start_index).

DELETE /v1/opera/profiles — xoá theo names/indexes (tuỳ chọn force_kill, remove_launcher).

## Bật/tắt & chạy theo dải

POST /v1/opera/profiles/{name}/start — bật 1 profile (hỗ trợ url, proxy, extra_args như --remote-debugging-port=..., lang, user_agent, mute_audio, cpu_affinity, priority…).

POST /v1/opera/profiles/start-range — bật dải {start..end} (hỗ trợ proxy_pattern, cpu_affinity_mode=roundrobin-N, priority, delay_s).

POST /v1/opera/profiles/{name}/stop — tắt một profile.

POST /v1/opera/stop-all — tắt tất cả Opera trong ProfilesRoot.

## Dọn dẹp

POST /v1/opera/cleanup/{name} — xoá file Singleton* & dọn Crashpad của profile.

POST /v1/opera/cleanup-all — dọn cho tất cả profiles.

Preferences & VPN

PATCH /v1/opera/profiles/{name}/preferences — patch Preferences theo dot-path (khi Opera tắt).

POST /v1/opera/profiles/{name}/vpn — bật/tắt VPN + đặt region (auto|europe|asia|americas).

CPU affinity & Priority (Windows)

POST /v1/opera/profiles/{name}/cpu-affinity — đặt danh sách core CPU.

POST /v1/opera/profiles/{name}/priority — đặt mức ưu tiên tiến trình.

PowerShell hooks (tuỳ chọn)

POST /v1/opera/scripts/make-profiles — gọi Opera_MakeProfiles_v2.ps1 (nếu đã khai báo trong config).

POST /v1/opera/scripts/open-range — gọi Open_Profiles_Range.ps1.

POST /v1/opera/scripts/cleanup — gọi Cleanup_Profiles.ps1.
