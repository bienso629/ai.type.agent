import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/remote_fs_entry.dart';
import 'api_service.dart';

/// Kết quả lưu một tệp (ảnh / video / tài liệu) tải từ máy App Chính về thiết bị hiện tại.
class RemoteFileSaveResult {
  final bool ok;
  final String savedPath;
  final String displayLocation;
  final String? folderToOpen;
  final int bytes;
  final String? error;

  const RemoteFileSaveResult({
    required this.ok,
    this.savedPath = '',
    this.displayLocation = '',
    this.folderToOpen,
    this.bytes = 0,
    this.error,
  });
}

/// Dịch vụ tải tệp dạng stream thẳng xuống ổ đĩa (không nhồi RAM cho video lớn)
/// và xuất đúng thư mục công khai trên từng nền tảng:
/// - Android API 29+: đẩy qua MediaStore vào Bộ sưu tập (Pictures/Movies) hoặc Download/AI Type Agent.
/// - Linux / macOS / Windows: lưu vào `~/Downloads/AI_Type_Agent/`.
/// - iOS: lưu vào `ApplicationDocuments/Downloads/`.
class RemoteFileDownloadService {
  static const MethodChannel _mediaSaverChannel = MethodChannel('ai_type_agent/media_saver');

  static const Set<String> _chatExtractableExtensions = {
    ...RemoteFsEntry.imageExtensions,
    ...RemoteFsEntry.videoExtensions,
    ...RemoteFsEntry.audioExtensions,
    'pdf',
    'zip',
    'tar',
    'gz',
    'tgz',
    '7z',
    'rar',
    'apk',
    'deb',
    'exe',
    'dmg',
    'docx',
    'xlsx',
    'pptx',
    'csv',
  };

  /// Trích xuất danh sách đường dẫn ảnh/video/tệp mà Agent nhắc tới trong tin nhắn trả lời.
  static List<String> extractDownloadablePathsFromText(String text) {
    if (text.trim().isEmpty) return const [];
    final results = <String>[];
    final seen = <String>{};

    void tryAdd(String raw) {
      var clean = raw.trim();
      if (clean.isEmpty) return;
      if (clean.startsWith('file://')) {
        clean = Uri.decodeFull(clean.substring('file://'.length));
      }
      // Loại bỏ dấu bao quanh markdown/câu chữ phổ biến
      clean = clean.replaceAll(RegExp(r'^[`"\x27(\[<]+'), '');
      clean = clean.replaceAll(RegExp(r'[`"\x27)\]>.,;:!?]+$'), '');
      // Loại bỏ anchor dòng như #L10-L20
      final hashIdx = clean.indexOf('#');
      if (hashIdx != -1) {
        clean = clean.substring(0, hashIdx);
      }
      if (clean.isEmpty) return;
      if (clean.startsWith('http://') || clean.startsWith('https://')) return;
      final isAbsoluteUnix = clean.startsWith('/') && clean.length > 3;
      final isAbsoluteWin = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(clean);
      if (!isAbsoluteUnix && !isAbsoluteWin) return;

      final ext = p.extension(clean).toLowerCase().replaceFirst('.', '');
      if (!_chatExtractableExtensions.contains(ext)) return;
      if (seen.add(clean)) {
        results.add(clean);
      }
    }

    // 1. Link file:// trong Markdown [name](file:///path/to/file.mp4)
    final fileUriRegex = RegExp(r'file:///[^\s\)\]`"<>]+', caseSensitive: false);
    for (final m in fileUriRegex.allMatches(text)) {
      tryAdd(m.group(0) ?? '');
      if (results.length >= 12) return results;
    }

    // 2. Đường dẫn tuyệt đối Unix (/home/..., /tmp/..., /opt/...) hoặc Windows (C:\...)
    final pathRegex = RegExp(
      r'(?:(?<![A-Za-z0-9_:/])(?:/[A-Za-z0-9._\-\+\~\(\)@ ]+)+|(?:[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]+))\.(?:png|jpe?g|gif|webp|bmp|svg|heic|mp4|mov|mkv|webm|avi|m4v|3gp|mp3|wav|m4a|ogg|flac|pdf|zip|tar|gz|tgz|7z|rar|apk|deb|exe|dmg|docx|xlsx|pptx|csv)\b',
      caseSensitive: false,
    );
    for (final m in pathRegex.allMatches(text)) {
      tryAdd(m.group(0) ?? '');
      if (results.length >= 12) return results;
    }

    return results;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _sanitizeFileName(String raw) {
    final base = p.basename(raw.trim());
    if (base.isEmpty || base == '.' || base == '..') return 'download.bin';
    return base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static String _uniqueFilePath(Directory dir, String fileName) {
    final safe = _sanitizeFileName(fileName);
    var candidate = p.join(dir.path, safe);
    if (!File(candidate).existsSync()) return candidate;
    final stem = p.basenameWithoutExtension(safe);
    final ext = p.extension(safe);
    for (var i = 1; i < 1000; i++) {
      candidate = p.join(dir.path, '$stem ($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    return p.join(dir.path, '${stem}_${DateTime.now().millisecondsSinceEpoch}$ext');
  }

  static Future<Directory> _resolveDesktopDownloadsDir() async {
    Directory? baseDir;
    try {
      baseDir = await getDownloadsDirectory();
    } catch (_) {}
    if (baseDir == null) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path;
      baseDir = Directory(p.join(home, 'Downloads'));
    }
    final target = Directory(p.join(baseDir.path, 'AI_Type_Agent'));
    if (!target.existsSync()) {
      target.createSync(recursive: true);
    }
    return target;
  }

  /// Tải tệp từ máy App Chính bằng stream thẳng xuống ổ đĩa và lưu vào vị trí phù hợp với nền tảng.
  static Future<RemoteFileSaveResult> downloadAndSave({
    required ApiService api,
    required String remotePath,
    String? fileName,
    String? customSaveDirectory,
    void Function(int receivedBytes, int totalBytes, double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final safeName = _sanitizeFileName(fileName?.trim().isNotEmpty == true ? fileName! : p.basename(remotePath));
    final kind = RemoteFsEntry.detectKind(safeName);
    final mimeType = RemoteFsEntry.detectMimeType(safeName);

    // 1. Nếu có thư mục lưu tùy chỉnh (hoặc Desktop / iOS) -> stream thẳng tới file đích
    if (customSaveDirectory != null && customSaveDirectory.trim().isNotEmpty) {
      final dir = Directory(customSaveDirectory.trim());
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final destPath = _uniqueFilePath(dir, safeName);
      final file = await api.downloadFileToPath(
        remotePath: remotePath,
        savePath: destPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      if (file == null || !file.existsSync()) {
        return RemoteFileSaveResult(
          ok: false,
          error: isCancelled?.call() == true ? 'Đã hủy tải xuống.' : 'Không thể tải tệp từ App Chính.',
        );
      }
      final len = await file.length();
      return RemoteFileSaveResult(
        ok: true,
        savedPath: file.path,
        displayLocation: file.path,
        folderToOpen: dir.path,
        bytes: len,
      );
    }

    if (Platform.isAndroid) {
      // Stream vào tệp tạm trước (0 tốn RAM) rồi chuyển qua Android MediaStore vào Gallery / Downloads
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = p.join(
        tempDir.path,
        'dl_${DateTime.now().millisecondsSinceEpoch}_$safeName',
      );
      File? downloaded;
      try {
        downloaded = await api.downloadFileToPath(
          remotePath: remotePath,
          savePath: tempFilePath,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        if (downloaded == null || !downloaded.existsSync()) {
          return RemoteFileSaveResult(
            ok: false,
            error: isCancelled?.call() == true ? 'Đã hủy tải xuống.' : 'Không thể tải tệp từ App Chính.',
          );
        }
        final len = await downloaded.length();
        try {
          final res = await _mediaSaverChannel.invokeMethod<dynamic>('saveFileToPublicStorage', {
            'sourcePath': downloaded.path,
            'fileName': safeName,
            'mimeType': mimeType,
            'kind': kind,
          });
          if (res is Map && res['ok'] == true) {
            try {
              await downloaded.delete();
            } catch (_) {}
            final display = res['displayPath']?.toString().trim().isNotEmpty == true
                ? res['displayPath'].toString().trim()
                : (kind == 'image'
                    ? 'Pictures/AI Type Agent/$safeName'
                    : (kind == 'video'
                        ? 'Movies/AI Type Agent/$safeName'
                        : 'Download/AI Type Agent/$safeName'));
            return RemoteFileSaveResult(
              ok: true,
              savedPath: res['uri']?.toString() ?? display,
              displayLocation: display,
              bytes: len,
            );
          }
        } catch (_) {
          // Fallback nếu chạy ngoài Android Activity (hoặc thiết bị cũ chặn MediaStore)
        }

        // Fallback về thư mục Download riêng của app trên bộ nhớ ngoài
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        final fallbackBase = (extDirs != null && extDirs.isNotEmpty)
            ? extDirs.first
            : await getApplicationDocumentsDirectory();
        final fallbackDir = Directory(p.join(fallbackBase.path, 'AI_Type_Agent'));
        if (!fallbackDir.existsSync()) fallbackDir.createSync(recursive: true);
        final finalPath = _uniqueFilePath(fallbackDir, safeName);
        await downloaded.copy(finalPath);
        try {
          await downloaded.delete();
        } catch (_) {}
        return RemoteFileSaveResult(
          ok: true,
          savedPath: finalPath,
          displayLocation: finalPath,
          folderToOpen: fallbackDir.path,
          bytes: len,
        );
      } catch (e) {
        try {
          if (downloaded != null && downloaded.existsSync()) {
            await downloaded.delete();
          }
        } catch (_) {}
        return RemoteFileSaveResult(ok: false, error: 'Lỗi tải xuống: $e');
      }
    }

    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'Downloads'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final destPath = _uniqueFilePath(dir, safeName);
      final file = await api.downloadFileToPath(
        remotePath: remotePath,
        savePath: destPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      if (file == null || !file.existsSync()) {
        return RemoteFileSaveResult(
          ok: false,
          error: isCancelled?.call() == true ? 'Đã hủy tải xuống.' : 'Không thể tải tệp từ App Chính.',
        );
      }
      return RemoteFileSaveResult(
        ok: true,
        savedPath: file.path,
        displayLocation: 'Tệp trên iPhone/iPad -> Downloads/$safeName',
        folderToOpen: dir.path,
        bytes: await file.length(),
      );
    }

    // Desktop (Linux / macOS / Windows)
    final downloadsDir = await _resolveDesktopDownloadsDir();
    final destPath = _uniqueFilePath(downloadsDir, safeName);
    final file = await api.downloadFileToPath(
      remotePath: remotePath,
      savePath: destPath,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (file == null || !file.existsSync()) {
      return RemoteFileSaveResult(
        ok: false,
        error: isCancelled?.call() == true ? 'Đã hủy tải xuống.' : 'Không thể tải tệp từ App Chính.',
      );
    }
    return RemoteFileSaveResult(
      ok: true,
      savedPath: file.path,
      displayLocation: file.path,
      folderToOpen: downloadsDir.path,
      bytes: await file.length(),
    );
  }

  /// Mở thư mục đích trên trình quản lý tệp của hệ điều hành Desktop.
  static Future<void> openLocalFolder(String dirPath) async {
    final clean = dirPath.trim();
    if (clean.isEmpty) return;
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [clean], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [clean], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('explorer.exe', [clean], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }
}
