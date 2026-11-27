import 'package:path/path.dart' as p;

/// Thông tin một thư mục hoặc tệp (ảnh, video, âm thanh, tài liệu) trên máy App Chính.
class RemoteFsEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modifiedAt;
  final String kind; // 'dir' | 'image' | 'video' | 'audio' | 'file'
  final String mimeType;

  const RemoteFsEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.modifiedAt,
    required this.kind,
    this.mimeType = 'application/octet-stream',
  });

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';
  bool get isAudio => kind == 'audio';

  String get extension => p.extension(name).toLowerCase().replaceFirst('.', '');

  String get formattedSize {
    if (isDir) return 'Thư mục';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'is_dir': isDir,
        'size': size,
        if (modifiedAt != null) 'modified_at': modifiedAt!.toIso8601String(),
        'kind': kind,
        'mime_type': mimeType,
      };

  factory RemoteFsEntry.fromJson(Map<String, dynamic> json) {
    final isDir = json['is_dir'] == true;
    final path = json['path']?.toString() ?? '';
    final name = json['name']?.toString() ?? p.basename(path);
    final kind = json['kind']?.toString().trim().isNotEmpty == true
        ? json['kind'].toString().trim()
        : (isDir ? 'dir' : detectKind(path));
    final mime = json['mime_type']?.toString().trim().isNotEmpty == true
        ? json['mime_type'].toString().trim()
        : (isDir ? 'inode/directory' : detectMimeType(path));
    return RemoteFsEntry(
      name: name,
      path: path,
      isDir: isDir,
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      modifiedAt: json['modified_at'] != null
          ? DateTime.tryParse(json['modified_at'].toString())
          : null,
      kind: kind,
      mimeType: mime,
    );
  }

  static const Set<String> imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'ico',
    'svg',
  };

  static const Set<String> videoExtensions = {
    'mp4',
    'mov',
    'mkv',
    'webm',
    'avi',
    'm4v',
    '3gp',
    'flv',
    'wmv',
    'ts',
  };

  static const Set<String> audioExtensions = {
    'mp3',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'flac',
    'opus',
    'wma',
  };

  static String detectKind(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    if (imageExtensions.contains(ext)) return 'image';
    if (videoExtensions.contains(ext)) return 'video';
    if (audioExtensions.contains(ext)) return 'audio';
    return 'file';
  }

  static String detectMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'heic':
        return 'image/heic';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case '3gp':
        return 'video/3gpp';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'gz':
      case 'tgz':
        return 'application/gzip';
      case 'tar':
        return 'application/x-tar';
      case 'apk':
        return 'application/vnd.android.package-archive';
      case 'deb':
        return 'application/vnd.debian.binary-package';
      case 'json':
        return 'application/json';
      case 'txt':
      case 'md':
      case 'log':
      case 'csv':
        return 'text/plain; charset=utf-8';
      case 'html':
      case 'htm':
        return 'text/html; charset=utf-8';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Kết quả liệt kê thư mục và tệp từ máy App Chính.
class RemoteFsListResult {
  final String currentPath;
  final String? parentPath;
  final String workspaceRoot;
  final List<RemoteFsEntry> entries;
  final String? error;

  const RemoteFsListResult({
    required this.currentPath,
    this.parentPath,
    this.workspaceRoot = '',
    this.entries = const [],
    this.error,
  });

  bool get hasError => error != null && error!.isNotEmpty;
}
