import 'dart:io';
import 'package:path/path.dart' as p;
import 'persona_service.dart';

/// Service tạo và thực thi CLI Automation Tools cho Local CLI Agent (agy, claude, gemini, etc.)
class CliAutomationBridgeService {
  static final CliAutomationBridgeService _instance = CliAutomationBridgeService._internal();
  factory CliAutomationBridgeService() => _instance;
  CliAutomationBridgeService._internal();

  final PersonaService _personaService = PersonaService();

  String get _cliScriptDir {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = p.join(home, '.agent_mxh_auto', 'bin');
    if (!Directory(dir).existsSync()) {
      try {
        Directory(dir).createSync(recursive: true);
      } catch (_) {}
    }
    return dir;
  }

  /// Khởi tạo và ghi file công cụ `mxh-tool` ra thư mục ~/.agent_mxh_auto/bin/mxh-tool
  /// Giúp Local CLI Agent (agy, claude...) có thể trực tiếp chạy lệnh:
  /// `mxh-tool list-profiles`
  /// `mxh-tool open-browser --ip <ip> [--url <url>]`
  /// `mxh-tool close-browser --ip <ip>`
  /// `mxh-tool open-device --ip <ip> [--type mobile|tablet]`
  /// `mxh-tool close-device --ip <ip>`
  Future<String> ensureCliHelperInstalled() async {
    final scriptPath = p.join(_cliScriptDir, 'mxh-tool');
    final scriptFile = File(scriptPath);

    const scriptContent = '''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mxh-tool: Công cụ điều khiển tự động hóa MXH cho Local CLI Agent (Google Antigravity agy, Claude Code...)
Tương tác trực tiếp với API/Socket hoặc file dữ liệu cấu hình của ứng dụng Agent MXH Auto.
"""
import sys
import os
import json
import argparse
import subprocess
import time
import urllib.request

HOME = os.path.expanduser("~")
DATA_DIR = os.path.join(HOME, ".agent_mxh_auto") if os.path.exists(os.path.join(HOME, ".agent_mxh_auto")) else os.path.join(HOME, ".tadu_ai_agent")
PERSONAS_FILE = os.path.join(DATA_DIR, "personas.json")
CONFIG_FILE = os.path.join(DATA_DIR, "config.json")
IPC_SOCKET_PORT = 19898  # Optional IPC port if agent daemon is listening

def list_profiles():
    if not os.path.exists(PERSONAS_FILE):
        print(json.dumps([]))
        return
    try:
        with open(PERSONAS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            profiles = []
            for ip, p in data.items():
                profiles.append({
                    "ip": ip,
                    "name": p.get("name", "Unknown"),
                    "gender": p.get("gender", ""),
                    "age": p.get("age", 25),
                    "bio": p.get("bio", ""),
                    "device_type": p.get("device_type", "mobile"),
                    "avd_name": p.get("avd_name"),
                    "external_device_address": p.get("external_device_address")
                })
            print(json.dumps(profiles, ensure_ascii=False, indent=2))
    except Exception as e:
        print(f"Error reading personas: {e}", file=sys.stderr)
        sys.exit(1)

def open_browser(ips, url=None):
    if not ips:
        print("Lỗi: Cần cung cấp ít nhất một địa chỉ IP (--ip hoặc --ips)", file=sys.stderr)
        sys.exit(1)

    url_to_open = url or "https://type.vn"
    for ip in ips:
        sanitized_ip = ip.replace(".", "_").replace(":", "_")
        profile_dir = os.path.join(DATA_DIR, "browser_profiles", f"ip_{sanitized_ip}")
        os.makedirs(profile_dir, exist_ok=True)
        
        # Tìm Chrome/Chromium/Brave/Edge trên Linux
        candidates = [
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/chromium-browser",
            "/usr/bin/chromium",
            "/usr/bin/brave-browser",
            "/usr/bin/microsoft-edge"
        ]
        browser_exe = None
        for c in candidates:
            if os.path.exists(c) and os.access(c, os.X_OK):
                browser_exe = c
                break
        
        if not browser_exe:
            # Fallback xdg-open nếu không tìm thấy binary cụ thể
            subprocess.Popen(["xdg-open", url_to_open])
            print(f"Đã mở {url_to_open} qua trình duyệt mặc định hệ thống cho IP {ip}")
            continue

        cmd = [
            browser_exe,
            f"--user-data-dir={profile_dir}",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-blink-features=AutomationControlled",
            "--lang=vi",
            url_to_open
        ]
        
        env = os.environ.copy()
        if "DISPLAY" not in env or not env["DISPLAY"]:
            env["DISPLAY"] = ":0"
            
        try:
            subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            print(f"Đã khởi chạy trình duyệt profile cho IP {ip} tại URL: {url_to_open}")
        except Exception as e:
            print(f"Không thể mở trình duyệt cho IP {ip}: {e}", file=sys.stderr)

def close_browser(ips):
    for ip in ips:
        sanitized_ip = ip.replace(".", "_").replace(":", "_")
        needle = f"browser_profiles/ip_{sanitized_ip}"
        try:
            subprocess.run(["pkill", "-f", needle], check=False)
            print(f"Đã gửi tín hiệu đóng trình duyệt cho IP {ip}")
        except Exception as e:
            print(f"Lỗi đóng trình duyệt cho IP {ip}: {e}", file=sys.stderr)

def open_device(ip, device_type="mobile", avd_name=None):
    # Tìm emulator binary
    sdk_emulator = os.path.expanduser("~/Android/Sdk/emulator/emulator")
    if not os.path.exists(sdk_emulator):
        sdk_emulator = "emulator"

    target_avd = avd_name
    if not target_avd:
        # Lấy danh sách avd hiện có
        try:
            res = subprocess.run([sdk_emulator, "-list-avds"], stdout=subprocess.PIPE, text=True, check=False)
            avds = [line.strip() for line in res.stdout.splitlines() if line.strip()]
            if avds:
                target_avd = avds[0]
        except Exception:
            pass

    if not target_avd:
        print("Không tìm thấy máy ảo AVD nào trong hệ thống Android SDK!", file=sys.stderr)
        sys.exit(1)

    cmd = [sdk_emulator, "-avd", target_avd, "-netdelay", "none", "-netspeed", "full"]
    env = os.environ.copy()
    if "DISPLAY" not in env or not env["DISPLAY"]:
        env["DISPLAY"] = ":0"

    try:
        subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        print(f"Đã mở thiết bị Android máy ảo {target_avd} cho IP {ip}")
    except Exception as e:
        print(f"Lỗi khởi chạy máy ảo cho IP {ip}: {e}", file=sys.stderr)

def close_device(ip=None):
    try:
        subprocess.run(["adb", "emu", "kill"], check=False)
        print("Đã gửi lệnh tắt thiết bị Android máy ảo.")
    except Exception as e:
        print(f"Lỗi tắt máy ảo: {e}", file=sys.stderr)

def main():
    parser = argparse.ArgumentParser(description="MXH Auto CLI Tool for Local CLI Agents")
    subparsers = parser.add_subparsers(dest="command")

    # list-profiles
    subparsers.add_parser("list-profiles", help="Lấy danh sách các nhân vật nuôi nick (profiles)")

    # open-browser
    p_open = subparsers.add_parser("open-browser", help="Mở trình duyệt riêng cho nhân vật")
    p_open.add_argument("--ip", help="Địa chỉ IP nhân vật")
    p_open.add_argument("--ips", nargs="+", help="Danh sách các IP")
    p_open.add_argument("--url", help="URL cần mở (facebook, tiktok, v.v.)")

    # close-browser
    p_close = subparsers.add_parser("close-browser", help="Đóng trình duyệt nhân vật")
    p_close.add_argument("--ip", help="Địa chỉ IP nhân vật")
    p_close.add_argument("--ips", nargs="+", help="Danh sách các IP")

    # open-device
    p_dev = subparsers.add_parser("open-device", help="Khởi chạy máy ảo Android")
    p_dev.add_argument("--ip", required=True, help="IP nhân vật")
    p_dev.add_argument("--type", default="mobile", help="Loại thiết bị: mobile hoặc tablet")
    p_dev.add_argument("--avd", help="Tên máy ảo AVD")

    # close-device
    p_cdev = subparsers.add_parser("close-device", help="Tắt máy ảo Android")
    p_cdev.add_argument("--ip", help="IP nhân vật")

    args = parser.parse_args()
    if args.command == "list-profiles":
        list_profiles()
    elif args.command == "open-browser":
        ips = []
        if args.ip: ips.append(args.ip)
        if args.ips: ips.extend(args.ips)
        open_browser(ips, args.url)
    elif args.command == "close-browser":
        ips = []
        if args.ip: ips.append(args.ip)
        if args.ips: ips.extend(args.ips)
        close_browser(ips)
    elif args.command == "open-device":
        open_device(args.ip, args.type, args.avd)
    elif args.command == "close-device":
        close_device(args.ip)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
''';

    await scriptFile.writeAsString(scriptContent);
    try {
      await Process.run('chmod', ['+x', scriptPath]);
    } catch (_) {}

    return scriptPath;
  }

  /// Xây dựng Full System Instructions kèm hướng dẫn thực thi công cụ terminal
  /// và thông tin danh sách nhân vật cho Local CLI Agent (agy, claude, gemini...)
  Future<String> buildCliSystemContext({String? workingDir}) async {
    final helperPath = await ensureCliHelperInstalled();
    final personas = await _personaService.loadSavedPersonas();

    final buffer = StringBuffer();
    buffer.writeln('=== QUY TẮC BẮT BUỘC DÀNH CHO LOCAL CLI AI AGENT ===');
    buffer.writeln('Bạn là AI Agent tự động hóa mạng xã hội (MXH) chạy trực tiếp trên máy local của người dùng.');
    buffer.writeln('Bạn có toàn quyền sử dụng terminal để khởi chạy trình duyệt, tương tác với tài khoản và điều khiển thiết bị.');
    buffer.writeln('');
    buffer.writeln('BỘ CÔNG CỤ ĐIỀU KHIỂN ĐƯỢC CẤP SẴN TRÊN MÁY:');
    buffer.writeln('Đường dẫn công cụ helper: `$helperPath` (hoặc lệnh `mxh-tool`)');
    buffer.writeln('1. Mở trình duyệt nuôi nick cho nhân vật theo IP:');
    buffer.writeln('   $helperPath open-browser --ip <IP> --url <URL_TRANG_WEB>');
    buffer.writeln('   (Ví dụ mở Facebook xem video reel: `$helperPath open-browser --ip 103.74.117.46 --url https://www.facebook.com/reel/990771153520030`)');
    buffer.writeln('2. Đóng trình duyệt của nhân vật:');
    buffer.writeln('   $helperPath close-browser --ip <IP>');
    buffer.writeln('3. Mở thiết bị máy ảo Android cho nhân vật:');
    buffer.writeln('   $helperPath open-device --ip <IP>');
    buffer.writeln('4. Đóng thiết bị máy ảo Android:');
    buffer.writeln('   $helperPath close-device --ip <IP>');
    buffer.writeln('5. Tra cứu danh sách nhân vật:');
    buffer.writeln('   $helperPath list-profiles');
    buffer.writeln('');

    if (personas.isNotEmpty) {
      buffer.writeln('DANH SÁCH NHÂN VẬT & IP HIỆN CÓ TRÊN HỆ THỐNG:');
      for (final p in personas.values) {
        buffer.writeln('- IP: ${p.ip} | Tên: ${p.name} | Giới tính: ${p.gender} | Tuổi: ${p.age}');
        if (p.bio.isNotEmpty) {
          buffer.writeln('  Tiểu sử: ${p.bio}');
        }
      }
      buffer.writeln('');
    }

    if (workingDir != null && workingDir.isNotEmpty) {
      buffer.writeln('PHẠM VI (SCOPE) CHỈ ĐỊNH CHO PHIÊN NÀY:');
      buffer.writeln(workingDir);
      buffer.writeln('');
    }

    buffer.writeln('NGUYÊN TẮC HÀNH ĐỘNG:');
    buffer.writeln('- Khi người dùng yêu cầu mở trình duyệt, xem link hoặc auto tương tác, BẮT BUỘC phải chạy lệnh `$helperPath open-browser` bằng terminal để mở cửa sổ trình duyệt thực tế trên màn hình.');
    buffer.writeln('- TUYỆT ĐỐI KHÔNG giải thích vòng vo về headless mode hay khuyên người dùng tự mở lệnh.');
    buffer.writeln('- Sau khi thực thi lệnh, hãy báo cáo kết quả rõ ràng về IP và URL đã được mở.');

    return buffer.toString();
  }
}
