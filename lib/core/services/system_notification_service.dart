import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/app_toast.dart';

class SystemNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Tìm đường dẫn icon của ứng dụng trên hệ thống Linux
  static String _resolveAppIcon() {
    // 1. Icon khi cài đặt qua gói .deb
    const installedIcon = '/usr/share/icons/hicolor/512x512/apps/ai-type-agent.png';
    if (File(installedIcon).existsSync()) return installedIcon;

    // 2. Icon trong bundle /opt
    const optIcon = '/opt/ai-type-agent/data/flutter_assets/assets/app_icon.png';
    if (File(optIcon).existsSync()) return optIcon;

    // 3. Icon trong thư mục assets dự án (môi trường dev)
    final cwdIcon = '${Directory.current.path}/assets/app_icon.png';
    if (File(cwdIcon).existsSync()) return cwdIcon;

    return 'ai-type-agent';
  }

  /// Phát thông báo hệ điều hành (Ubuntu/Linux qua notify-send hoặc macOS/Windows)
  /// và hiển thị In-App Toast nếu người dùng đang trong app.
  static Future<void> notifyReplyFinished({
    String title = 'AI Type Agent',
    String message = 'Bot đã hoàn tất câu trả lời!',
  }) async {
    // 1. Hiển thị In-App Toast nếu app đang mở
    try {
      final context = navigatorKey.currentContext;
      if (context != null) {
        AppToast.info(context, message);
      }
    } catch (_) {}

    // 2. Gửi System Notification tới OS (Ubuntu GNOME / Linux Desktop)
    try {
      if (Platform.isLinux) {
        final iconPath = _resolveAppIcon();
        await Process.run('notify-send', [
          '-a',
          'AI Type Agent',
          '-i',
          iconPath,
          '-h',
          'string:desktop-entry:ai-type-agent',
          '-h',
          'string:category:im.received',
          title,
          message,
        ]);
      } else if (Platform.isMacOS) {
        final script = 'display notification "$message" with title "$title"';
        await Process.run('osascript', ['-e', script]);
      } else if (Platform.isWindows) {
        final psCommand =
            '[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null; \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02); \$xml = [xml]\$template.GetXml(); (\$xml.GetElementsByTagName("text"))[0].AppendChild(\$xml.CreateTextNode("$title")) > \$null; (\$xml.GetElementsByTagName("text"))[1].AppendChild(\$xml.CreateTextNode("$message")) > \$null; \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml); [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("AI Type Agent").Show(\$toast);';
        await Process.run('powershell', ['-Command', psCommand]);
      }
    } catch (_) {}
  }

  /// Đưa cửa sổ ứng dụng lên trên cùng và focus
  static Future<void> focusAppWindow() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
        }
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
  }
}
