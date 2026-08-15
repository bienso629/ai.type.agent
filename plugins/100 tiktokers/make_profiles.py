#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_profiles.py — Cross-platform Profile Creator & Cloner for Opera (Ubuntu/Linux & Windows)

Chức năng:
1. --setup-base : Mở Profile000 chuẩn để người dùng cấu hình (đăng nhập TikTok, bật VPN, cài đặt extension...).
2. Clone Profile: Nhân bản Profile000 (gốc) thành 99 Profile mới (Profile001 -> Profile099).
3. Tự động dọn dẹp các file Lock (SingletonLock, Crashpad...) để không bị lỗi browser crashed khi mở đồng loạt.

Ví dụ sử dụng trên Ubuntu / Linux:
----------------------------------
# 1. Bật Profile 000 để cài đặt & đăng nhập mẫu:
python make_profiles.py --setup-base

# 2. Nhân bản từ Profile 000 thành 99 Profile (từ 001 đến 099):
python make_profiles.py --from 1 --to 99 --force

# 3. Mở chạy thử dải Profile từ 1 đến 5:
python open_profiles.py --from 1 --to 5
"""

import os
import sys
import shutil
import glob
import subprocess
import argparse
import platform
from pathlib import Path
from typing import List, Optional

# --- Cross-platform default paths ---
IS_WIN = platform.system() == "Windows"
DEFAULT_PROFILES_ROOT = Path("D:/OperaProfiles") if IS_WIN else Path.home() / "OperaProfiles"

# List of common Opera binary paths
OPERA_PATHS = [
    # Linux
    "/usr/bin/opera-gx",
    "/usr/bin/opera",
    "/usr/bin/opera-developer",
    "/usr/bin/opera-beta",
    "/snap/bin/opera",
    # Windows
    r"C:\Program Files\Opera GX\opera.exe",
    r"C:\Program Files\Opera\opera.exe",
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\Opera GX\opera.exe"),
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\Opera\opera.exe"),
]


def find_opera_bin(custom_path: Optional[str] = None) -> str:
    """Find installed Opera binary path."""
    if custom_path and os.path.exists(custom_path):
        return custom_path
    
    # Try shutil.which
    for name in ["opera-gx", "opera", "opera-developer", "opera-beta"]:
        w = shutil.which(name)
        if w and os.path.exists(w):
            return w

    # Try explicit paths
    for p in OPERA_PATHS:
        if os.path.exists(p):
            return p

    raise FileNotFoundError("Không tìm thấy trình duyệt Opera trên hệ thống! Vui lòng cài đặt Opera hoặc chỉ định đường dẫn qua --opera-path")


import stat

def clean_profile_locks(profile_dir: Path):
    """Remove lock files, socket pipes, and temporary crashpad files from Opera profile folder."""
    if not profile_dir.exists():
        return

    # Lock patterns
    lock_files = [
        "SingletonLock",
        "SingletonSocket",
        "SingletonCookie",
        "Lockfile",
        "Running Chrome Version",
        "oauc_pipe",
        "Default/SingletonLock",
        "Default/SingletonSocket",
        "Default/SingletonCookie",
        "Default/Lockfile",
    ]

    for lf in lock_files:
        p = profile_dir / lf
        if p.exists() or p.is_symlink():
            try:
                if p.is_dir() and not p.is_symlink():
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    p.unlink(missing_ok=True)
            except Exception as e:
                print(f"  [!] Không thể xóa lock file {p}: {e}")

    # Remove any special socket or FIFO files (like oauc_pipe)
    for root, dirs, files in os.walk(profile_dir):
        for name in files:
            fp = os.path.join(root, name)
            try:
                st = os.lstat(fp)
                if stat.S_ISFIFO(st.st_mode) or stat.S_ISSOCK(st.st_mode):
                    os.unlink(fp)
            except Exception:
                pass

    # Remove crashpad logs/temp files
    crashpad_dir = profile_dir / "Crashpad"
    if crashpad_dir.exists():
        for sub in ["completed", "pending", "new"]:
            sub_p = crashpad_dir / sub
            if sub_p.exists():
                shutil.rmtree(sub_p, ignore_errors=True)


def _ignore_special_files(dirpath, filenames):
    ignored = []
    for f in filenames:
        full_path = os.path.join(dirpath, f)
        try:
            st = os.lstat(full_path)
            if stat.S_ISFIFO(st.st_mode) or stat.S_ISSOCK(st.st_mode) or stat.S_ISCHR(st.st_mode) or stat.S_ISBLK(st.st_mode):
                ignored.append(f)
        except Exception:
            pass
    return ignored


def format_profile_name(prefix: str, index: int, zero_pad: int) -> str:
    return f"{prefix}{index:0{zero_pad}d}"


def setup_base_profile(opera_bin: str, root_dir: Path, base_name: str):
    """Launch Base Profile (Profile000) for user to set up cookies/VPN/extensions."""
    base_dir = root_dir / base_name
    base_dir.mkdir(parents=True, exist_ok=True)
    clean_profile_locks(base_dir)

    print(f"\n=======================================================")
    print(f"🚀 KHỞI CHẠY PROFILE GỐC (BASE TEMPLATE): {base_name}")
    print(f"📁 Đường dẫn: {base_dir}")
    print(f"▶ Trình duyệt: {opera_bin}")
    print(f"=======================================================")
    print("👉 Hãy thực hiện trong cửa sổ Opera mới hiện lên:")
    print("   1. Đăng nhập tài khoản TikTok / Facebook.")
    print("   2. Bật VPN Opera hoặc cài đặt các Extension cần thiết.")
    print("   3. Tùy chỉnh Cài đặt (Settings) theo nhu cầu.")
    print("👉 Sau khi cài đặt xong, HÃY ĐÓNG CỬA SỔ OPERA.")
    print("-------------------------------------------------------\n")

    cmd = [
        opera_bin,
        f"--user-data-dir={base_dir}",
        "--no-first-run",
        "https://www.tiktok.com"
    ]

    try:
        proc = subprocess.Popen(cmd)
        print("⏳ Đang chờ người dùng thiết lập và đóng Opera...")
        proc.wait()
        print("\n✅ Đã đóng Profile gốc. Tiến hành làm sạch Lock files...")
        clean_profile_locks(base_dir)
        print("🎉 Profile 000 đã sẵn sàng để nhân bản!")
    except Exception as e:
        print(f"❌ Lỗi khi khởi chạy Opera: {e}")


def clone_profiles(
    root_dir: Path,
    base_name: str,
    prefix: str,
    start_idx: int,
    end_idx: int,
    zero_pad: int,
    force: bool = False
):
    """Clone Base Profile (Profile000) to Profile001..Profile099."""
    base_dir = root_dir / base_name
    if not base_dir.exists():
        print(f"❌ Profile gốc '{base_name}' chưa tồn tại ở: {base_dir}")
        print(f"👉 Vui lòng chạy lệnh: python make_profiles.py --setup-base  trước!")
        sys.exit(1)

    # Clean base profile first
    clean_profile_locks(base_dir)

    total_to_create = (end_idx - start_idx) + 1
    print(f"\n=======================================================")
    print(f"📦 BẮT ĐẦU NHÂN BẢN {total_to_create} PROFILE")
    print(f"📂 Profile mẫu gốc: {base_dir}")
    print(f"🎯 Đích: Từ {format_profile_name(prefix, start_idx, zero_pad)} đến {format_profile_name(prefix, end_idx, zero_pad)}")
    print(f"=======================================================\n")

    success_count = 0
    skip_count = 0

    for i in range(start_idx, end_idx + 1):
        target_name = format_profile_name(prefix, i, zero_pad)
        target_dir = root_dir / target_name

        if target_dir.exists():
            if not force:
                print(f"  [⏭ BỎ QUA] {target_name} đã tồn tại (dùng --force để ghi đè)")
                skip_count += 1
                continue
            else:
                shutil.rmtree(target_dir, ignore_errors=True)

        try:
            print(f"  [📋 CLONE] {base_name} -> {target_name}...", end="", flush=True)
            shutil.copytree(base_dir, target_dir, dirs_exist_ok=True, ignore=_ignore_special_files)
            clean_profile_locks(target_dir)
            print(" [OK]")
            success_count += 1
        except Exception as e:
            print(f" [LỖI: {e}]")

    print(f"\n=======================================================")
    print(f"🎉 HOÀN THÀNH!")
    print(f"✅ Đã tạo thành công: {success_count} profile")
    if skip_count > 0:
        print(f"⏭ Bỏ qua (đã có từ trước): {skip_count} profile")
    print(f"📁 Tổng thư mục tại: {root_dir}")
    print(f"=======================================================\n")


def main():
    parser = argparse.ArgumentParser(description="Tạo và Nhân bản 100 Profile Opera trên Ubuntu/Linux & Windows")
    parser.add_argument("--root-dir", "-r", type=str, default=str(DEFAULT_PROFILES_ROOT), help="Thư mục chứa các Profile (Mặc định: ~/OperaProfiles trên Linux)")
    parser.add_argument("--base-name", "-b", type=str, default="Profile000", help="Tên Profile gốc làm chuẩn (Mặc định: Profile000)")
    parser.add_argument("--prefix", "-p", type=str, default="Profile", help="Tiền tố tên Profile (Mặc định: Profile)")
    parser.add_argument("--from", "-f", dest="start_idx", type=int, default=1, help="Chỉ số bắt đầu (Mặc định: 1)")
    parser.add_argument("--to", "-t", dest="end_idx", type=int, default=99, help="Chỉ số kết thúc (Mặc định: 99)")
    parser.add_argument("--zero-pad", "-z", type=int, default=3, help="Số chữ số (Mặc định: 3, ví dụ 001, 002...)")
    parser.add_argument("--setup-base", action="store_true", help="Bật Profile000 mẫu để người dùng đăng nhập & cấu hình trước khi clone")
    parser.add_argument("--force", action="store_true", help="Ghi đè nếu Profile đã tồn tại")
    parser.add_argument("--opera-path", type=str, default=None, help="Đường dẫn file thực thi Opera (Tùy chọn)")

    args = parser.parse_args()
    root_dir = Path(args.root_dir).resolve()
    root_dir.mkdir(parents=True, exist_ok=True)

    try:
        opera_bin = find_opera_bin(args.opera_path)
    except FileNotFoundError as e:
        print(f"❌ {e}")
        sys.exit(1)

    if args.setup_base:
        setup_base_profile(opera_bin, root_dir, args.base_name)
    else:
        clone_profiles(
            root_dir=root_dir,
            base_name=args.base_name,
            prefix=args.prefix,
            start_idx=args.start_idx,
            end_idx=args.end_idx,
            zero_pad=args.zero_pad,
            force=args.force
        )


if __name__ == "__main__":
    main()
