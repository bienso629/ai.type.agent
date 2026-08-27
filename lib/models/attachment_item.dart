import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AttachmentItem {
  final String name;
  final String content;
  final int size;
  final String? path;
  final bool isImage;
  final Uint8List? rawBytes;
  final String? remotePath;
  final double uploadProgress;
  final bool isUploading;
  final bool isUploaded;
  final bool isDownloading;
  final double downloadProgress;
  final String? error;

  AttachmentItem({
    required this.name,
    required this.content,
    this.size = 0,
    this.path,
    bool? isImage,
    this.rawBytes,
    this.remotePath,
    this.uploadProgress = 0.0,
    this.isUploading = false,
    this.isUploaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.error,
  }) : isImage = isImage ?? _checkIsImage(name);

  static bool _checkIsImage(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  factory AttachmentItem.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? 'file';
    return AttachmentItem(
      name: name,
      content: json['content']?.toString() ?? '',
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      path: json['path']?.toString(),
      isImage: json['is_image'] == true || _checkIsImage(name),
      remotePath: json['remote_path']?.toString(),
      isUploaded: json['is_uploaded'] == true || (json['remote_path'] != null && json['remote_path'].toString().isNotEmpty),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'content': content,
        'size': size,
        if (path != null) 'path': path,
        'is_image': isImage,
        if (remotePath != null) 'remote_path': remotePath,
        'is_uploaded': isUploaded,
      };

  AttachmentItem copyWith({
    String? name,
    String? content,
    int? size,
    String? path,
    bool? isImage,
    Uint8List? rawBytes,
    String? remotePath,
    double? uploadProgress,
    bool? isUploading,
    bool? isUploaded,
    bool? isDownloading,
    double? downloadProgress,
    String? error,
  }) {
    return AttachmentItem(
      name: name ?? this.name,
      content: content ?? this.content,
      size: size ?? this.size,
      path: path ?? this.path,
      isImage: isImage ?? this.isImage,
      rawBytes: rawBytes ?? this.rawBytes,
      remotePath: remotePath ?? this.remotePath,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      isUploading: isUploading ?? this.isUploading,
      isUploaded: isUploaded ?? this.isUploaded,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      error: error ?? this.error,
    );
  }

  static Future<AttachmentItem?> fromFile(File file, {Uint8List? fileBytes, String? fileName}) async {
    try {
      final name = fileName ?? file.path.split(Platform.pathSeparator).last;
      final isImg = _checkIsImage(name);
      final bytes = fileBytes ?? await file.readAsBytes();
      final size = bytes.length;

      String content;
      if (isImg) {
        final ext = name.split('.').last.toLowerCase();
        final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
        final b64 = base64Encode(bytes);
        content = 'data:$mime;base64,$b64';
      } else {
        try {
          content = utf8.decode(bytes);
        } catch (_) {
          content = base64Encode(bytes);
        }
      }

      return AttachmentItem(
        name: name,
        content: content,
        size: size,
        path: file.path,
        isImage: isImg,
        rawBytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  static AttachmentItem fromBytes({
    required String name,
    required Uint8List bytes,
    String? path,
  }) {
    final isImg = _checkIsImage(name);
    final size = bytes.length;
    String content;
    if (isImg) {
      final ext = name.split('.').last.toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
      final b64 = base64Encode(bytes);
      content = 'data:$mime;base64,$b64';
    } else {
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = base64Encode(bytes);
      }
    }

    return AttachmentItem(
      name: name,
      content: content,
      size: size,
      path: path,
      isImage: isImg,
      rawBytes: bytes,
    );
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
