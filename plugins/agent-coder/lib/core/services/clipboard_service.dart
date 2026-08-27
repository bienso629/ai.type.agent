import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/attachment_item.dart';

class ClipboardService {
  static Future<AttachmentItem?> getClipboardImage() async {
    try {
      // 1. Try Pasteboard plugin
      Uint8List? imageBytes;
      try {
        imageBytes = await Pasteboard.image;
      } catch (e) {
        debugPrint('Pasteboard.image error: $e');
      }

      // 2. Linux Fallback (Wayland / X11)
      if (imageBytes == null && Platform.isLinux) {
        imageBytes = await _getLinuxClipboardImage();
      }

      // 3. macOS Fallback
      if (imageBytes == null && Platform.isMacOS) {
        imageBytes = await _getMacClipboardImage();
      }

      // 4. Windows Fallback
      if (imageBytes == null && Platform.isWindows) {
        imageBytes = await _getWindowsClipboardImage();
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'screenshot_$timestamp.png';

        // Save to cache dir for persistence & path preview
        String? savedPath;
        try {
          final tempDir = await getTemporaryDirectory();
          final targetFile = File('${tempDir.path}/$fileName');
          await targetFile.writeAsBytes(imageBytes);
          savedPath = targetFile.path;
        } catch (_) {}

        return AttachmentItem.fromBytes(
          name: fileName,
          bytes: imageBytes,
          path: savedPath,
        );
      }
    } catch (e) {
      debugPrint('Error getting clipboard image: $e');
    }
    return null;
  }

  static Future<Uint8List?> _getLinuxClipboardImage() async {
    // 1. Try wl-paste (Wayland)
    try {
      final res = await Process.run('wl-paste', ['-t', 'image/png'], stdoutEncoding: null);
      if (res.exitCode == 0 && res.stdout is List<int> && (res.stdout as List<int>).isNotEmpty) {
        return Uint8List.fromList(res.stdout as List<int>);
      }
    } catch (_) {}

    // 2. Try xclip (X11)
    try {
      final res = await Process.run('xclip', ['-selection', 'clipboard', '-t', 'image/png', '-o'], stdoutEncoding: null);
      if (res.exitCode == 0 && res.stdout is List<int> && (res.stdout as List<int>).isNotEmpty) {
        return Uint8List.fromList(res.stdout as List<int>);
      }
    } catch (_) {}

    return null;
  }

  static Future<Uint8List?> _getMacClipboardImage() async {
    try {
      final res = await Process.run('pngpaste', ['-'], stdoutEncoding: null);
      if (res.exitCode == 0 && res.stdout is List<int> && (res.stdout as List<int>).isNotEmpty) {
        return Uint8List.fromList(res.stdout as List<int>);
      }
    } catch (_) {}
    return null;
  }

  static Future<Uint8List?> _getWindowsClipboardImage() async {
    try {
      final tempDir = Directory.systemTemp;
      final tempFile = '${tempDir.path}\\cb_image_${DateTime.now().millisecondsSinceEpoch}.png';
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$img = [System.Windows.Forms.Clipboard]::GetImage()
if (\$img -ne \$null) {
    \$img.Save('$tempFile', [System.Drawing.Imaging.ImageFormat]::Png)
    exit 0
}
exit 1
''';
      final res = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      if (res.exitCode == 0) {
        final f = File(tempFile);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          await f.delete();
          return bytes;
        }
      }
    } catch (_) {}
    return null;
  }
}
