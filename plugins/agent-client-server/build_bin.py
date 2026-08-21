import os
import sys
import shutil
import zipfile
import subprocess

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def build_appimage(binary_path):
    """Đóng gói thành file duy nhất .AppImage chuẩn Linux (Click đúp chạy ngay, không cần .sh)."""
    app_dir = os.path.join(BASE_DIR, "build", "AppDir")
    if os.path.exists(app_dir):
        shutil.rmtree(app_dir)

    os.makedirs(os.path.join(app_dir, "usr", "bin"), exist_ok=True)
    os.makedirs(os.path.join(app_dir, "usr", "share", "icons", "hicolor", "256x256", "apps"), exist_ok=True)

    # 1. Copy binary
    binary_dest = os.path.join(app_dir, "usr", "bin", "tadu-cloud-ai-agent")
    shutil.copy2(binary_path, binary_dest)
    os.chmod(binary_dest, 0o755)

    # 2. Copy icon
    icon_src = os.path.join(BASE_DIR, "templates", "icon.png")
    if os.path.exists(icon_src):
        shutil.copy2(icon_src, os.path.join(app_dir, "tadu-cloud-ai-agent.png"))
        shutil.copy2(icon_src, os.path.join(app_dir, "usr", "share", "icons", "hicolor", "256x256", "apps", "tadu-cloud-ai-agent.png"))

    # 3. Desktop file trong AppDir
    desktop_content = """[Desktop Entry]
Version=1.0
Type=Application
Name=Tadu Cloud AI Agent Control Center
GenericName=Tadu Cloud AI Agent (GLM-5.3)
Comment=Trình điều khiển Tadu Cloud AI Agent và Terminal Server
Exec=tadu-cloud-ai-agent
Icon=tadu-cloud-ai-agent
Terminal=false
Categories=Development;Utility;
StartupNotify=true
"""
    with open(os.path.join(app_dir, "tadu-cloud-ai-agent.desktop"), "w", encoding="utf-8") as f:
        f.write(desktop_content)

    # 4. AppRun
    apprun_content = """#!/bin/sh
SELF=$(readlink -f "$0")
HERE=$(dirname "$SELF")
export PATH="${HERE}/usr/bin:${PATH}"
export APPDIR="${HERE}"
exec "${HERE}/usr/bin/tadu-cloud-ai-agent" "$@"
"""
    apprun_path = os.path.join(app_dir, "AppRun")
    with open(apprun_path, "w", encoding="utf-8") as f:
        f.write(apprun_content)
    os.chmod(apprun_path, 0o755)

    # 5. Build AppImage bằng appimagetool
    appimagetool_bin = "/tmp/appimagetool"
    if not os.path.exists(appimagetool_bin):
        subprocess.run(["curl", "-s", "-L", "-o", appimagetool_bin, "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"])
        os.chmod(appimagetool_bin, 0o755)

    env = os.environ.copy()
    env["ARCH"] = "x86_64"
    appimage_out = os.path.join(BASE_DIR, "dist", "Tadu-Cloud-AI-Agent-Control-Center-x86_64.AppImage")
    
    res = subprocess.run([appimagetool_bin, "--appimage-extract-and-run", "-n", app_dir, appimage_out], env=env)
    if res.returncode == 0:
        os.chmod(appimage_out, 0o755)
        return appimage_out
    return None

def build_deb(binary_path):
    """Đóng gói file .deb cho Ubuntu/Debian."""
    deb_dir = os.path.join(BASE_DIR, "build", "deb_pkg")
    if os.path.exists(deb_dir):
        shutil.rmtree(deb_dir)

    os.makedirs(os.path.join(deb_dir, "DEBIAN"), exist_ok=True)
    os.makedirs(os.path.join(deb_dir, "usr", "bin"), exist_ok=True)
    os.makedirs(os.path.join(deb_dir, "usr", "share", "applications"), exist_ok=True)
    os.makedirs(os.path.join(deb_dir, "usr", "share", "icons", "hicolor", "256x256", "apps"), exist_ok=True)

    # 1. Binary & Icon
    shutil.copy2(binary_path, os.path.join(deb_dir, "usr", "bin", "tadu-cloud-ai-agent"))
    os.chmod(os.path.join(deb_dir, "usr", "bin", "tadu-cloud-ai-agent"), 0o755)
    
    icon_src = os.path.join(BASE_DIR, "templates", "icon.png")
    if os.path.exists(icon_src):
        shutil.copy2(icon_src, os.path.join(deb_dir, "usr", "share", "icons", "hicolor", "256x256", "apps", "tadu-cloud-ai-agent.png"))

    # 2. Desktop
    desktop_content = """[Desktop Entry]
Version=1.0
Type=Application
Name=Tadu Cloud AI Agent Control Center
GenericName=Tadu Cloud AI Agent (GLM-5.3)
Comment=Trình điều khiển Tadu Cloud AI Agent và Terminal Server
Exec=/usr/bin/tadu-cloud-ai-agent
Icon=tadu-cloud-ai-agent
Terminal=false
Categories=Development;Utility;
StartupNotify=true
"""
    with open(os.path.join(deb_dir, "usr", "share", "applications", "tadu-cloud-ai-agent.desktop"), "w", encoding="utf-8") as f:
        f.write(desktop_content)

    # 3. Control file
    control_content = """Package: tadu-cloud-ai-agent
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Tadu Cloud Team
Description: Tadu Cloud AI Agent Control Center (GLM-5.3)
 Giao dien dieu khien Tadu Cloud AI Agent va Terminal Server.
"""
    with open(os.path.join(deb_dir, "DEBIAN", "control"), "w", encoding="utf-8") as f:
        f.write(control_content)

    deb_out = os.path.join(BASE_DIR, "dist", "tadu-cloud-ai-agent_1.0.0_amd64.deb")
    res = subprocess.run(["dpkg-deb", "--build", deb_dir, deb_out])
    if res.returncode == 0:
        return deb_out
    return None

def update_user_desktop(binary_path):
    """Cập nhật shortcut Tadu Cloud trên màn hình Desktop của User."""
    user_desktop_dir = os.path.expanduser("~/Desktop")
    icon_path = os.path.join(BASE_DIR, "templates", "icon.png")
    if os.path.exists(user_desktop_dir):
        # Xoá shortcut cũ nếu có
        old_desktop = os.path.join(user_desktop_dir, "AI-Agent-Client.desktop")
        if os.path.exists(old_desktop):
            os.remove(old_desktop)

        user_desktop_file = os.path.join(user_desktop_dir, "Tadu-Cloud-AI-Agent.desktop")
        with open(user_desktop_file, "w", encoding="utf-8") as f:
            f.write(f"""[Desktop Entry]
Version=1.0
Type=Application
Name=Tadu Cloud AI Agent Control Center
GenericName=Tadu Cloud AI Agent (GLM-5.3)
Comment=Trình điều khiển Tadu Cloud AI Agent và Terminal Server
Exec="{binary_path}"
Path={BASE_DIR}
Icon={icon_path}
Terminal=false
Categories=Development;Utility;
StartupNotify=true
""")
        os.chmod(user_desktop_file, 0o755)
        try:
            subprocess.run(["gio", "set", user_desktop_file, "metadata::trusted", "true"], check=False)
        except Exception:
            pass

def build():
    print("\n" + "="*60)
    print("📦 BẮT ĐẦU ĐÓNG GÓI: TADU CLOUD AI AGENT CONTROL CENTER")
    print(f"Hệ điều hành hiện tại: {sys.platform}")
    print("="*60 + "\n")

    sep = ";" if sys.platform.startswith("win") else ":"
    binary_name = "tadu-cloud-ai-agent.exe" if sys.platform.startswith("win") else "tadu-cloud-ai-agent"

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        f"--name={binary_name}",
        f"--add-data=templates{sep}templates",
        f"--add-data=ai_agent_service.py{sep}.",
        f"--add-data=logo.jpg{sep}.",
        "--hidden-import=uvicorn.logging",
        "--hidden-import=uvicorn.loops",
        "--hidden-import=uvicorn.loops.auto",
        "--hidden-import=uvicorn.protocols",
        "--hidden-import=uvicorn.protocols.http",
        "--hidden-import=uvicorn.protocols.http.auto",
        "--hidden-import=uvicorn.protocols.websockets",
        "--hidden-import=uvicorn.protocols.websockets.auto",
        "--hidden-import=uvicorn.lifespan",
        "--hidden-import=uvicorn.lifespan.on",
        "--hidden-import=paramiko",
        "--hidden-import=openai",
        "--hidden-import=pydantic",
        "--hidden-import=cryptography",
        "--hidden-import=cryptography.fernet",
        "client_ui.py"
    ]

    print("🚀 Thực thi PyInstaller...")
    res = subprocess.run(cmd, cwd=BASE_DIR)
    if res.returncode == 0:
        dist_bin = os.path.join(BASE_DIR, "dist", binary_name)
        print(f"\n✅ Đã build core binary: {dist_bin}")

        if not sys.platform.startswith("win") and sys.platform.startswith("linux"):
            print("🚀 Đang đóng gói AppImage & DEB package...")
            appimage_path = build_appimage(dist_bin)
            deb_path = build_deb(dist_bin)
            update_user_desktop(dist_bin)

            print("\n" + "="*60)
            print("🎉 ĐÓNG GÓI THÀNH CÔNG: TADU CLOUD AI AGENT CONTROL CENTER!")
            if appimage_path:
                print(f"📦 1. AppImage (Click đúp chạy ngay): {appimage_path}")
            if deb_path:
                print(f"📦 2. File cài đặt .deb (Cài 1-click): {deb_path}")
            print(f"🖥️  3. Shortcut trên Desktop: ~/Desktop/Tadu-Cloud-AI-Agent.desktop")
            print("="*60 + "\n")
    else:
        print("\n❌ Đóng gói thất bại với mã lỗi:", res.returncode)

if __name__ == "__main__":
    build()
