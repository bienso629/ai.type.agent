import 'dart:io';
import 'package:flutter/material.dart';

class SystemNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Phát thông báo hệ điều hành (Ubuntu/Linux qua notify-send hoặc macOS/Windows)
  static Future<void> notifyReplyFinished({
    String title = 'AI Type Agent',
    String message = 'Bot đã hoàn tất câu trả lời!',
  }) async {
    try {
      if (Platform.isLinux) {
        await Process.run('notify-send', [
          '-a',
          'AI Type Agent',
          '-i',
          'dialog-information',
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
}
