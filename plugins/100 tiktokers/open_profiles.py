#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
open_profiles.py — Cross-platform Profile Opener with Remote Debugging (Linux & Windows)

Chức năng:
Mở một dải Profile Opera song song (ví dụ từ Profile 000 -> 005) với cổng Chrome DevTools Protocol (CDP) tự động gán.

Ví dụ sử dụng trên Ubuntu / Linux:
----------------------------------
# Mở Profile 000 (Base profile)
python open_profiles.py --from 0 --to 0

# Mở từ Profile 001 đến 005
python open_profiles.py --from 1 --to 5

# Tắt tất cả Opera đang mở
python open_profiles.py --kill-all
"""

import os
import sys
import time
import json
import shutil
import subprocess
import argparse
import platform
from pathlib import Path
from typing import List, Optional

IS_WIN = platform.system() == "Windows"
DEFAULT_PROFILES_ROOT = Path("D:/OperaProfiles") if IS_WIN else Path.home() / "OperaProfiles"


def _load_proxies_map(root_dir: Path) -> dict:
    fp = root_dir / "proxies.json"
    if fp.exists():
        try:
            with open(fp, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def _parse_proxy_string(proxy_str: str) -> Optional[dict]:
    s = (proxy_str or "").strip()
    if not s:
        return None
    scheme = "http"
    if "://" in s:
        scheme_part, rest = s.split("://", 1)
        scheme = scheme_part.lower()
        s = rest
    user, password = None, None
    if "@" in s:
        auth_part, host_part = s.split("@", 1)
        if ":" in auth_part:
            user, password = auth_part.split(":", 1)
        else:
            user = auth_part
        s = host_part
    parts = s.split(":")
    if len(parts) == 4:
        host, port, user, password = parts[0], int(parts[1]), parts[2], parts[3]
    elif len(parts) == 2:
        host, port = parts[0], int(parts[1])
    else:
        return None
    return {"scheme": scheme, "host": host, "port": port, "user": user, "pass": password}

OPERA_PATHS = [
    # macOS
    "/Applications/Opera GX.app/Contents/MacOS/Opera GX",
    "/Applications/Opera.app/Contents/MacOS/Opera",
    "/Applications/Opera Developer.app/Contents/MacOS/Opera Developer",
    "/Applications/Opera Beta.app/Contents/MacOS/Opera Beta",
    os.path.expanduser("~/Applications/Opera GX.app/Contents/MacOS/Opera GX"),
    os.path.expanduser("~/Applications/Opera.app/Contents/MacOS/Opera"),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    os.path.expanduser("~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    # Linux
    "/usr/bin/opera-gx",
    "/usr/bin/opera",
    "/usr/bin/opera-developer",
    "/usr/bin/opera-beta",
    "/snap/bin/opera",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium",
    # Windows
    r"C:\Program Files\Opera GX\opera.exe",
    r"C:\Program Files\Opera\opera.exe",
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\Opera GX\opera.exe"),
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\Opera\opera.exe"),
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
]


def find_opera_bin(custom_path: Optional[str] = None) -> str:
    if custom_path and os.path.exists(custom_path):
        return custom_path
    for name in [
        "opera-gx", "opera", "opera-developer", "opera-beta",
        "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"
    ]:
        w = shutil.which(name)
        if w and os.path.exists(w):
            return w
    for p in OPERA_PATHS:
        if os.path.exists(p):
            return p
    raise FileNotFoundError("Không tìm thấy Opera hoặc Chrome trên hệ thống!")


def kill_all_opera():
    """Kill running Opera or Chrome processes."""
    print("🛑 Đang tắt toàn bộ tiến trình trình duyệt...")
    if IS_WIN:
        for img in ["opera.exe", "opera_gx.exe", "chrome.exe", "chromium.exe"]:
            subprocess.run(["taskkill", "/F", "/IM", img], stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    else:
        for pat in ["opera", "google-chrome", "chrome", "chromium"]:
            subprocess.run(["pkill", "-f", pat], stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    print("✅ Đã ngắt tất cả cửa sổ trình duyệt.")


def open_profiles_range(
    root_dir: Path,
    prefix: str,
    start_idx: int,
    end_idx: int,
    zero_pad: int,
    base_port: int,
    delay_sec: float,
    opera_bin: str,
    url: Optional[str] = None,
    headless: bool = False
):
    root_dir = root_dir.resolve()
    proxies_map = _load_proxies_map(root_dir)
    print(f"\n=======================================================")
    print(f"🚀 MỞ DẢI PROFILE OPERA ({start_idx} -> {end_idx}) [Headless: {headless}]")
    print(f"📂 Thư mục: {root_dir}")
    print(f"▶ Cổng CDP bắt đầu từ: {base_port}")
    if proxies_map:
        print(f"🌐 Đã phát hiện {len(proxies_map)} Proxy cấu hình sẵn trong proxies.json")
    print(f"=======================================================\n")

    launched = []
    for i in range(start_idx, end_idx + 1):
        name = f"{prefix}{i:0{zero_pad}d}"
        profile_dir = root_dir / name

        if not profile_dir.exists():
            print(f"⚠️ Profile '{name}' chưa tồn tại tại {profile_dir}. Bỏ qua!")
            continue

        port = base_port + (i - start_idx)
        proxy_str = proxies_map.get(name)
        parsed_proxy = _parse_proxy_string(proxy_str) if proxy_str else None

        p_info = f" | Proxy: {parsed_proxy['host']}:{parsed_proxy['port']}" if parsed_proxy else ""
        print(f"▶ Launching [{name}] | CDP Port: {port}{p_info} | Headless: {headless}")

        cmd = [
            opera_bin,
            f"--user-data-dir={profile_dir}",
            f"--remote-debugging-port={port}",
            "--remote-debugging-address=127.0.0.1",
            "--remote-allow-origins=*",
            "--no-first-run",
            "--disable-background-networking",
        ]

        if parsed_proxy:
            ext_dir = profile_dir / "proxy_extension"
            if ext_dir.exists():
                cmd.append(f"--load-extension={ext_dir}")
            cmd.append(f"--proxy-server={parsed_proxy['scheme']}://{parsed_proxy['host']}:{parsed_proxy['port']}")

        if headless:
            cmd.append("--headless=new")

        if url:
            cmd.append(url)

        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        launched.append((name, port, proc.pid))

        if delay_sec > 0:
            time.sleep(delay_sec)

    print(f"\n=======================================================")
    print(f"✅ Đã mở thành công {len(launched)} profile!")
    for name, port, pid in launched:
        print(f"   • {name} -> Cổng CDP: http://127.0.0.1:{port} (PID: {pid})")
    print(f"=======================================================\n")


def main():
    parser = argparse.ArgumentParser(description="Mở dải Profile Opera trên Ubuntu/Linux & Windows")
    parser.add_argument("--root-dir", "-r", type=str, default=str(DEFAULT_PROFILES_ROOT), help="Thư mục chứa Profile")
    parser.add_argument("--prefix", "-p", type=str, default="Profile", help="Tiền tố tên Profile")
    parser.add_argument("--from", "-f", dest="start_idx", type=int, default=0, help="Chỉ số bắt đầu")
    parser.add_argument("--to", "-t", dest="end_idx", type=int, default=5, help="Chỉ số kết thúc")
    parser.add_argument("--zero-pad", "-z", type=int, default=3, help="Số chữ số zero-padding")
    parser.add_argument("--base-port", type=int, default=54900, help="Cổng CDP bắt đầu (Default: 54900)")
    parser.add_argument("--delay", type=float, default=0.5, help="Độ trễ giữa các lần mở cửa sổ (giây)")
    parser.add_argument("--url", type=str, default=None, help="Trang web mở sẵn khi bật Opera")
    parser.add_argument("--headless", action="store_true", help="Bật Opera ở chế độ chạy ẩn (Headless Mode, không hiện GUI)")
    parser.add_argument("--kill-all", action="store_true", help="Tắt toàn bộ Opera")
    parser.add_argument("--opera-path", type=str, default=None, help="Đường dẫn file thực thi Opera")

    args = parser.parse_args()

    if args.kill_all:
        kill_all_opera()
        return

    try:
        opera_bin = find_opera_bin(args.opera_path)
    except FileNotFoundError as e:
        print(f"❌ {e}")
        sys.exit(1)

    open_profiles_range(
        root_dir=Path(args.root_dir),
        prefix=args.prefix,
        start_idx=args.start_idx,
        end_idx=args.end_idx,
        zero_pad=args.zero_pad,
        base_port=args.base_port,
        delay_sec=args.delay,
        opera_bin=opera_bin,
        url=args.url,
        headless=args.headless
    )


if __name__ == "__main__":
    main()
