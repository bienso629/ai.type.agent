# goto_first_tab.py (updated)
# CLI test: Điều hướng tab đầu tiên cho một nhóm profile đang chạy vào URL đích
# và (tuỳ chọn) CHỤP ảnh modal captcha ".captcha-verify-container" nếu phát hiện.
#
# Yêu cầu: Python 3.8+
# Không cần requests: dùng urllib chuẩn.
#
# Ví dụ:
#   python goto_first_tab.py ^
#     --api-base http://localhost:8000 ^
#     --profiles-root "D:\OperaProfiles" ^
#     --host 127.0.0.1 ^
#     --pick Profile001,Profile002 ^
#     --target-url "https://www.tiktok.com/@someuser" ^
#     --captcha-dir captchas ^
#     --captcha-wait-ms 5000
#
# Tắt tính năng chụp captcha:
#   thêm --no-capture

import json
import sys
import os
import argparse
import urllib.parse
import urllib.request
from typing import List, Dict, Any


def http_get(url: str, timeout: float = 15.0) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": "goto_cli/1.1"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        return json.loads(raw.decode("utf-8"))


def http_post(url: str, payload: Dict[str, Any], timeout: float = 60.0):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"User-Agent": "goto_cli/1.1", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        status = resp.getcode()
        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception:
            body = {"raw": raw.decode("utf-8", errors="replace")}
        return status, body


def parse_args():
    ap = argparse.ArgumentParser(
        description="Điều hướng tab đầu tiên + (tuỳ chọn) chụp captcha overlay"
    )
    ap.add_argument("--api-base", default="http://localhost:8000", help="Base URL API FastAPI")
    ap.add_argument("--profiles-root", default=r"D:\OperaProfiles", help="Thư mục gốc chứa các profile")
    ap.add_argument("--host", default="127.0.0.1", help="Host dùng để build ws từ DevToolsActivePort (API list)")
    ap.add_argument(
        "--pick",
        default="Profile001,Profile002,Profile003",
        help="Danh sách profile, phân tách bằng dấu phẩy",
    )
    ap.add_argument("--target-url", required=True, help="URL đích cần điều hướng")
    ap.add_argument("--pattern", default="Profile*", help="Glob pattern, ví dụ: Profile*")
    ap.add_argument("--max-concurrency", type=int, default=3, help="Số profile chạy song song")
    ap.add_argument("--timeout-ms", type=int, default=120_000, help="Timeout cho page.goto")
    # Tùy chọn chụp captcha
    ap.add_argument(
        "--captcha-selector",
        default=".captcha-verify-container",
        help="CSS selector của modal captcha cần chụp",
    )
    ap.add_argument(
        "--captcha-wait-ms",
        type=int,
        default=4000,
        help="Thời gian chờ selector captcha xuất hiện (ms)",
    )
    ap.add_argument("--captcha-dir", default="captchas", help="Thư mục lưu ảnh captcha")
    ap.add_argument(
        "--no-capture",
        action="store_true",
        help="Tắt tính năng chụp captcha",
    )
    return ap.parse_args()


def main():
    args = parse_args()

    api_base: str = args.api_base.rstrip("/")
    profiles_root: str = args.profiles_root
    host: str = args.host
    pattern: str = args.pattern
    pick_list: List[str] = [x.strip() for x in args.pick.split(",") if x.strip()]
    target_url: str = args.target_url
    max_concurrency: int = args.max_concurrency
    timeout_ms: int = args.timeout_ms

    capture_captcha: bool = not args.no_capture
    captcha_selector: str = args.captcha_selector
    captcha_wait_ms: int = args.captcha_wait_ms
    captcha_dir: str = args.captcha_dir

    # 1) Lấy danh sách profiles (và wsEndpoint nếu đang chạy)
    list_url = f"{api_base}/v1/opera/profiles/list?" + urllib.parse.urlencode(
        {"profiles_root": profiles_root, "host": host, "pattern": pattern}
    )

    try:
        data = http_get(list_url)
    except Exception as e:
        print(f"[ERR] Không lấy được danh sách profiles: {e}")
        sys.exit(2)

    if not data.get("ok"):
        print("[ERR] API /v1/opera/profiles/list trả về ok=false:", json.dumps(data, ensure_ascii=False))
        sys.exit(2)

    items = data.get("items", [])
    # 2) Lọc những profile trong PICK và đang chạy (có wsEndpoint)
    running = []
    for it in items:
        prof = it.get("profile")
        if prof in pick_list and it.get("wsEndpoint"):
            running.append(
                {
                    "profile": prof,
                    "dir": it.get("dir"),
                    "wsEndpoint": it.get("wsEndpoint"),
                    "json_version": it.get("json_version"),
                }
            )

    if not running:
        print("[INFO] Không tìm thấy profile nào vừa nằm trong PICK vừa đang chạy.")
        print("      PICK =", pick_list)
        sys.exit(0)

    # 3) Gọi API goto-first-tab kèm cấu hình chụp captcha
    payload = {
        "target_url": target_url,
        "profiles": pick_list,
        "running": running,  # ưu tiên dùng danh sách đang chạy có sẵn
        "max_concurrency": max_concurrency,
        "timeout_ms": timeout_ms,
        # --- mới: các tuỳ chọn chụp captcha ---
        "capture_captcha": capture_captcha,
        "captcha_selector": captcha_selector,
        "captcha_wait_ms": captcha_wait_ms,
        "captcha_dir": captcha_dir,
    }

    print("[INFO] Gọi API /v1/opera/goto-first-tab với payload:")
    print(json.dumps(payload, ensure_ascii=False, indent=2))

    try:
        status, resp = http_post(f"{api_base}/v1/opera/goto-first-tab", payload, timeout=120.0)
    except Exception as e:
        print(f"[ERR] Gọi goto-first-tab thất bại: {e}")
        sys.exit(2)

    print("HTTP Status:", status)
    print(json.dumps(resp, ensure_ascii=False, indent=2))

    # 4) Tóm tắt nhanh kết quả + in danh sách ảnh captcha (nếu có)
    try:
        results = resp[0]["results"] if isinstance(resp, list) else resp.get("results", [])
    except Exception:
        results = []

    if not results:
        return

    saved_images = []
    for r in results:
        if isinstance(r, dict) and r.get("status") == "ok":
            if r.get("captcha_detected") and r.get("captcha_image"):
                saved_images.append((r.get("profile"), r.get("captcha_image")))

    if saved_images:
        print("\n=== ẢNH CAPTCHA ĐÃ CHỤP ===")
        for prof, path in saved_images:
            print(f"- {prof}: {path}")
        # tạo thư mục nếu người dùng chưa có
        try:
            if not os.path.isdir(captcha_dir):
                os.makedirs(captcha_dir, exist_ok=True)
        except Exception:
            pass
    else:
        print("\n[INFO] Không có captcha hoặc không chụp được ảnh nào.")


if __name__ == "__main__":
    main()
