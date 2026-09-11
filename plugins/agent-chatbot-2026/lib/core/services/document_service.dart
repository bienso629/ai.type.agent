import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'database_service.dart';
import 'encryption_service.dart';
import 'local_config_service.dart';
import 'storage_service.dart';

class KnowledgeDocument {
  final int? id;
  final String name;
  final String extension;
  final int size;
  final String path;
  final String content;
  final bool isEnabled;
  final DateTime createdAt;

  KnowledgeDocument({
    this.id,
    required this.name,
    required this.extension,
    required this.size,
    required this.path,
    required this.content,
    this.isEnabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isImage {
    final ext = extension.toLowerCase();
    return ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp' || ext == 'gif' || ext == 'bmp';
  }

  bool get isScannedPdf {
    final ext = extension.toLowerCase();
    return ext == 'pdf' && (content.contains('OCR & Thị giác Vision AI') || content.contains('Trang PDF Scan') || content.contains('PDF DẠNG SCAN') || content.contains('TÀI LIỆU PDF SCAN'));
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'extension': extension,
      'size': size,
      'path': path,
      'content': content,
      'is_enabled': isEnabled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory KnowledgeDocument.fromMap(Map<String, dynamic> map) {
    return KnowledgeDocument(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      extension: map['extension']?.toString() ?? '',
      size: int.tryParse(map['size']?.toString() ?? '0') ?? 0,
      path: map['path']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      isEnabled: (map['is_enabled'] as int?) != 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class DocumentService {
  static final DocumentService _instance = DocumentService._internal();
  factory DocumentService() => _instance;
  DocumentService._internal();

  final DatabaseService _dbService = DatabaseService();
  final LocalConfigService _configService = LocalConfigService();
  final EncryptionService _enc = EncryptionService();

  final StorageService _storage = StorageService();

  String? lastError;

  Future<Map<String, String>> _getWebHeaders() async {
    final authToken = await _storage.getAuthToken();
    final secretToken = await _storage.getSecretToken();
    final token = (authToken != null && authToken.isNotEmpty) ? authToken : secretToken;
    final userEmail = await _storage.getUserEmail();
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (token.isNotEmpty) 'X-Secret-Token': token,
      if (userEmail != null && userEmail.isNotEmpty) 'X-User-Email': userEmail,
      if (userEmail != null && userEmail.isNotEmpty) 'X-User-Name': userEmail.split('@')[0],
    };
  }

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        extension TEXT NOT NULL,
        size INTEGER DEFAULT 0,
        path TEXT NOT NULL,
        content TEXT NOT NULL,
        is_enabled INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Uri _resolveUri(String endpoint) {
    if (kIsWeb) {
      return Uri.base.resolve(endpoint);
    }
    return Uri.parse(endpoint);
  }

  Future<List<KnowledgeDocument>> getDocuments() async {
    if (kIsWeb) {
      try {
        final gateway = await _storage.getGatewayUrl();
        final uri = gateway.isNotEmpty ? Uri.parse('$gateway/api/docs.php') : _resolveUri('/api/docs.php');
        final res = await http.get(uri, headers: await _getWebHeaders()).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final body = jsonDecode(utf8.decode(res.bodyBytes));
          if (body['success'] == true && body['data']?['documents'] is List) {
            final list = body['data']['documents'] as List;
            return list.map((m) {
              final doc = KnowledgeDocument.fromMap(m as Map<String, dynamic>);
              final dec = _enc.decryptValue(doc.content);
              return KnowledgeDocument(
                id: doc.id,
                name: doc.name,
                extension: doc.extension,
                size: doc.size,
                path: doc.path,
                content: dec,
                isEnabled: doc.isEnabled,
                createdAt: doc.createdAt,
              );
            }).toList();
          }
        }
      } catch (_) {}
      return [];
    }
    try {
      await _dbService.init();
      final db = await _dbService.getRawDatabase();
      if (db == null) return [];
      await _ensureTable(db);
      final rows = await db.query(
        'knowledge_documents',
        orderBy: 'id DESC',
      );
      return rows.map((r) {
        final doc = KnowledgeDocument.fromMap(r);
        final decContent = _enc.decryptValue(doc.content);
        return KnowledgeDocument(
          id: doc.id,
          name: doc.name,
          extension: doc.extension,
          size: doc.size,
          path: doc.path,
          content: decContent,
          isEnabled: doc.isEnabled,
          createdAt: doc.createdAt,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Tải lên và index toàn bộ nội dung tài liệu
  Future<int> addDocument({
    required String name,
    required String filePath,
    Uint8List? bytes,
    void Function(String status)? onProgress,
  }) async {
    try {
      final ext = p.extension(filePath.isNotEmpty ? filePath : name).replaceAll('.', '').toLowerCase();
      int size = 0;
      String content = '';

      if (onProgress != null) {
        onProgress('Đang đọc tệp $name...');
      }

      if (bytes != null && bytes.isNotEmpty) {
        size = bytes.length;
        content = await _extractContent(bytes, ext, name, filePath: filePath, onProgress: onProgress);
      } else if (!kIsWeb && filePath.isNotEmpty) {
        final f = File(filePath);
        if (await f.exists()) {
          size = await f.length();
          final fileBytes = await f.readAsBytes();
          content = await _extractContent(fileBytes, ext, name, filePath: filePath, onProgress: onProgress);
        }
      } else if (kIsWeb && (bytes == null || bytes.isEmpty)) {
        lastError = 'Trình duyệt không đọc được dữ liệu byte của tệp';
        return 0;
      }

      final encContent = _enc.encryptValue(content);

      if (kIsWeb) {
        final gateway = await _storage.getGatewayUrl();
        final uri = gateway.isNotEmpty ? Uri.parse('$gateway/api/docs.php') : _resolveUri('/api/docs.php');
        final payload = {
          'name': name,
          'extension': ext,
          'size': size,
          'path': filePath,
          'content': encContent,
          'is_enabled': 1,
        };
        final res = await http.post(
          uri,
          headers: await _getWebHeaders(),
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 120));
        if (res.statusCode == 200) {
          final body = jsonDecode(utf8.decode(res.bodyBytes));
          if (body['success'] == true && body['data']?['id'] != null) {
            lastError = null;
            return (body['data']['id'] as num).toInt();
          }
          lastError = body['message']?.toString() ?? 'Máy chủ trả về phản hồi không hợp lệ';
          return 0;
        }
        lastError = 'Máy chủ HTTP ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}';
        return 0;
      }

      await _dbService.init();
      final db = await _dbService.getRawDatabase();
      if (db == null) {
        lastError = 'Không thể khởi tạo cơ sở dữ liệu cục bộ';
        return 0;
      }
      await _ensureTable(db);

      final doc = KnowledgeDocument(
        name: name,
        extension: ext,
        size: size,
        path: filePath,
        content: encContent,
        isEnabled: true,
        createdAt: DateTime.now(),
      );

      final insertId = await db.insert('knowledge_documents', doc.toMap());
      lastError = null;
      return insertId;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[DocumentService] Lỗi addDocument: $e');
      return 0;
    }
  }

  Future<String> _extractContent(
    Uint8List bytes,
    String ext,
    String filename, {
    String? filePath,
    void Function(String status)? onProgress,
  }) async {
    final isImg = ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp' || ext == 'gif' || ext == 'bmp';
    if (isImg) {
      if (onProgress != null) {
        onProgress('Đang dùng Thị giác AI phân tích & OCR ảnh: $filename');
      }
      final visionSummary = await _analyzeImageWithVision(bytes, ext, filename);
      if (visionSummary != null && visionSummary.isNotEmpty) {
        return visionSummary;
      }
      final b64 = base64Encode(bytes);
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
      return '[Hình ảnh: $filename (Dung lượng: ${bytes.length} bytes)]\nData-URI: data:$mime;base64,$b64';
    }

    if (ext == 'txt' || ext == 'md' || ext == 'json' || ext == 'csv' || ext == 'yaml' || ext == 'yml' || ext == 'xml' || ext == 'html' || ext == 'dart' || ext == 'py' || ext == 'js' || ext == 'sh') {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }

    if (ext == 'pdf') {
      final pdfContent = await _extractPdfWithFallbackToVision(bytes, filename, filePath: filePath, onProgress: onProgress);
      if (pdfContent.isNotEmpty) {
        return pdfContent;
      }
    }

    // Nếu là các định dạng tài liệu khác hoặc nhị phân chưa được parse: Gửi cho AI giải mã
    if (onProgress != null) {
      onProgress('Đang gửi tài liệu $filename cho AI trích xuất nội dung...');
    }
    final aiExtracted = await _analyzeDocumentWithAi(bytes, ext, filename);
    if (aiExtracted != null && aiExtracted.isNotEmpty) {
      return aiExtracted;
    }

    try {
      final latin = latin1.decode(bytes);
      final buffer = StringBuffer();
      final regex = RegExp(r'[\w\d\s\.,;:!\?\-\(\)\[\]\/\\@#%&*+=<>\^_\{\}\|~]{4,}');
      final matches = regex.allMatches(latin);
      for (final m in matches) {
        final piece = m.group(0)!.trim();
        if (piece.length > 5 && !piece.startsWith('Obj') && !piece.startsWith('stream')) {
          buffer.writeln(piece);
        }
        if (buffer.length > 50000) break;
      }
      final extracted = buffer.toString().trim();
      if (extracted.isNotEmpty) {
        return extracted;
      }
    } catch (_) {}

    return '[Nội dung tệp định dạng $ext - Dung lượng: ${bytes.length} bytes]';
  }

  Future<String> _extractPdfWithFallbackToVision(
    Uint8List bytes,
    String filename, {
    String? filePath,
    void Function(String status)? onProgress,
  }) async {
    int pageCount = 1;
    String pureDartText = '';

    // 1. Thử trích xuất văn bản kỹ thuật số bằng Syncfusion PDF (Pure Dart - Chạy mọi nền tảng)
    try {
      final doc = sf_pdf.PdfDocument(inputBytes: bytes);
      pageCount = max(1, doc.pages.count);
      final extractor = sf_pdf.PdfTextExtractor(doc);
      pureDartText = extractor.extractText().trim();
      doc.dispose();
    } catch (_) {}

    // 2. Dự phòng bằng pdftotext trên Desktop nếu Syncfusion chưa bóc tách được
    String systemText = '';
    if (!kIsWeb && pureDartText.isEmpty) {
      String? tempFilePath;
      try {
        String targetPath = filePath ?? '';
        if (targetPath.isEmpty || !await File(targetPath).exists()) {
          final tempFile = File('${Directory.systemTemp.path}/doc_${DateTime.now().millisecondsSinceEpoch}_$filename');
          await tempFile.writeAsBytes(bytes);
          tempFilePath = tempFile.path;
          targetPath = tempFilePath;
        }

        final result = await Process.run('pdftotext', ['-layout', targetPath, '-']);
        if (result.exitCode == 0) {
          systemText = result.stdout.toString().trim();
        }
      } catch (_) {
      } finally {
        if (tempFilePath != null) {
          try {
            await File(tempFilePath).delete();
          } catch (_) {}
        }
      }
    }

    final rawBestText = pureDartText.length >= systemText.length ? pureDartText : systemText;

    // 3. KIỂM TRA ĐIỀU KIỆN PDF SCAN / ẢNH CHỤP:
    // Tài liệu PDF thông thường có văn bản đầy đủ luôn đạt ít nhất 80-150 ký tự mỗi trang.
    // Nếu tổng số ký tự trích xuất < pageCount * 60 ký tự (ví dụ: file 14 trang mà chỉ có 100 ký tự chữ ký số):
    // RÕ RÀNG ĐÂY LÀ PDF DẠNG SCAN (các trang chính là hình ảnh chụp, không có text layer).
    final minExpectedChars = max(150, pageCount * 60);
    final isScannedDocument = rawBestText.length < minExpectedChars;

    if (!isScannedDocument) {
      // Đây là tài liệu PDF có text layer đầy đủ 100%
      return '=== [TÀI LIỆU PDF: $filename (TRÍCH XUẤT ĐẦY ĐỦ NGUYÊN VĂN TẤT CẢ CÁC TRANG)] ===\n$rawBestText\n=== [HẾT TÀI LIỆU PDF] ===';
    }

    // 4. XỬ LÝ PDF SCAN: Render từng trang thành ảnh sắc nét và chạy Vision OCR
    if (onProgress != null) {
      onProgress('Phát hiện PDF dạng Scan ($pageCount trang). Đang trích xuất ảnh từng trang để OCR...');
    }

    List<Uint8List> pageImages = [];
    if (!kIsWeb) {
      String targetPath = filePath ?? '';
      String? tempPdfPath;
      Directory? tempImgDir;
      try {
        if (targetPath.isEmpty || !await File(targetPath).exists()) {
          final tempFile = File('${Directory.systemTemp.path}/scan_${DateTime.now().millisecondsSinceEpoch}_$filename');
          await tempFile.writeAsBytes(bytes);
          tempPdfPath = tempFile.path;
          targetPath = tempPdfPath;
        }

        tempImgDir = await Directory.systemTemp.createTemp('pdf_pages_');
        final ppmResult = await Process.run('pdftoppm', [
          '-jpeg',
          '-r',
          '150',
          targetPath,
          p.join(tempImgDir.path, 'page'),
        ]);

        if (ppmResult.exitCode == 0) {
          final files = tempImgDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'))
              .toList();
          files.sort((a, b) => a.path.compareTo(b.path));
          for (final f in files) {
            pageImages.add(await f.readAsBytes());
          }
        }
      } catch (_) {
      } finally {
        if (tempPdfPath != null) {
          try {
            await File(tempPdfPath).delete();
          } catch (_) {}
        }
        if (tempImgDir != null) {
          try {
            await tempImgDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    }

    // 4.1. OCR từng trang ảnh qua AI Vision (hỗ trợ Concurrency pool 2 trang cùng lúc để xử lý nhanh)
    if (pageImages.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('=== [TÀI LIỆU PDF SCAN: $filename (ĐÃ ĐƯỢC THỊ GIÁC AI OCR CHI TIẾT TOÀN BỘ ${pageImages.length} TRANG)] ===\n');

      if (rawBestText.isNotEmpty) {
        buffer.writeln('--- [THÔNG TIN CHỮ KÝ SỐ / LỚP TEXT GỐC] ---');
        buffer.writeln(rawBestText);
        buffer.writeln();
      }

      final pageResults = List<String?>.filled(pageImages.length, null);
      int completed = 0;
      const concurrency = 2;

      for (int i = 0; i < pageImages.length; i += concurrency) {
        final end = min(i + concurrency, pageImages.length);
        final batchFutures = <Future<void>>[];

        for (int j = i; j < end; j++) {
          final pageNum = j + 1;
          batchFutures.add(() async {
            if (onProgress != null) {
              onProgress('Đang OCR trang $pageNum/${pageImages.length}: $filename...');
            }
            final pageOcr = await _analyzeImageWithVision(
              pageImages[j],
              'jpg',
              '$filename (Trang $pageNum/${pageImages.length})',
            );
            pageResults[j] = pageOcr;
            completed++;
            if (onProgress != null) {
              onProgress('Đã OCR xong $completed/${pageImages.length} trang: $filename');
            }
          }());
        }

        await Future.wait(batchFutures);
      }

      int successCount = 0;
      for (int i = 0; i < pageResults.length; i++) {
        final pageNum = i + 1;
        buffer.writeln('--- [TRANG $pageNum/${pageResults.length}] ---');
        final text = pageResults[i];
        if (text != null && text.trim().isNotEmpty) {
          buffer.writeln(text.trim());
          successCount++;
        } else {
          buffer.writeln('[Không nhận diện được nội dung chữ trên trang này]');
        }
        buffer.writeln();
      }

      buffer.writeln('=== [HẾT TÀI LIỆU PDF SCAN: $filename] ===');

      if (successCount > 0) {
        return buffer.toString();
      }
    }

    // 4.2. Dự phòng môi trường Web: Gửi toàn bộ PDF cho AI giải mã
    if (onProgress != null) {
      onProgress('Đang gửi toàn bộ tệp PDF $filename cho AI bóc tách...');
    }

    final aiContent = await _analyzeDocumentWithAi(bytes, 'pdf', filename);
    if (aiContent != null && aiContent.isNotEmpty) {
      return '=== [TÀI LIỆU PDF: $filename (ĐÃ ĐƯỢC AI OCR TRÍCH XUẤT ĐẦY ĐỦ)] ===\n$aiContent\n=== [HẾT TÀI LIỆU PDF] ===';
    }

    if (rawBestText.isNotEmpty) {
      return '=== [TÀI LIỆU PDF: $filename] ===\n$rawBestText\n=== [HẾT TÀI LIỆU PDF] ===';
    }

    return '[Tài liệu PDF: $filename (Đã nạp vào hệ thống)]';
  }

  Future<String?> _analyzeImageWithVision(Uint8List bytes, String ext, String filename) async {
    try {
      final cfg = await _configService.loadConfig();
      var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api-vn-sg.mitom.ai/v1';
      final apiKey = cfg['proxy_api_key']?.toString() ?? '';
      final model = cfg['ai_model']?.toString() ?? 'gemini-2.5-flash';

      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      final b64 = base64Encode(bytes);
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
      final dataUri = 'data:$mime;base64,$b64';

      final client = http.Client();
      final targetUri = kIsWeb
          ? (await _storage.getGatewayUrl()).isNotEmpty
              ? Uri.parse('${await _storage.getGatewayUrl()}/api/completions.php')
              : _resolveUri('/api/completions.php')
          : Uri.parse('$baseUrl/chat/completions');

      if (apiKey.isEmpty) {
        return null;
      }

      final res = await client.post(
        targetUri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Bạn là chuyên gia thị giác AI phân tích tài liệu và OCR chính xác cao. Hãy đọc toàn bộ chữ viết, các con số, số liệu bảng biểu, tiêu đề, nội dung ghi chú có trong trang/bức ảnh "$filename" này. TUYỆT ĐỐI KHÔNG TÓM TẮT, hãy chép lại đầy đủ, chuẩn xác bằng tiếng Việt để nạp vào cơ sở tri thức cho hệ thống.'
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': dataUri}
                }
              ]
            }
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 45));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final reply = data['choices']?[0]?['message']?['content']?.toString().trim();
        if (reply != null && reply.isNotEmpty) {
          return reply;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _analyzeDocumentWithAi(Uint8List bytes, String ext, String filename) async {
    try {
      final cfg = await _configService.loadConfig();
      var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api-vn-sg.mitom.ai/v1';
      final apiKey = cfg['proxy_api_key']?.toString() ?? '';
      final model = cfg['ai_model']?.toString() ?? 'gemini-2.5-flash';

      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      if (apiKey.isEmpty) {
        return null;
      }

      final b64 = base64Encode(bytes);
      String mime = 'application/pdf';
      if (ext == 'pdf') {
        mime = 'application/pdf';
      } else if (ext == 'doc' || ext == 'docx') {
        mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      } else if (ext == 'xls' || ext == 'xlsx') {
        mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      } else if (ext == 'csv') {
        mime = 'text/csv';
      }

      final dataUri = 'data:$mime;base64,$b64';

      final client = http.Client();
      final targetUri = kIsWeb
          ? (await _storage.getGatewayUrl()).isNotEmpty
              ? Uri.parse('${await _storage.getGatewayUrl()}/api/completions.php')
              : _resolveUri('/api/completions.php')
          : Uri.parse('$baseUrl/chat/completions');

      final res = await client.post(
        targetUri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Bạn là hệ thống AI phân tích tài liệu (Document Intelligence) cao cấp. Hãy đọc và chép lại nguyên văn 100% toàn bộ văn bản, số liệu, bảng biểu, danh sách, từng trang có trong tệp tài liệu "$filename" (định dạng $ext). TUYỆT ĐỐI KHÔNG ĐƯỢC TÓM TẮT, KHÔNG RÚT GỌN, KHÔNG BỎ QUA BẤT KỲ DÒNG NÀO. Xuất ra toàn bộ nội dung chữ tiếng Việt chi tiết, chuẩn xác 100% để lưu vào cơ sở tri thức hệ thống.'
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': dataUri}
                }
              ]
            }
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final reply = data['choices']?[0]?['message']?['content']?.toString().trim();
        if (reply != null && reply.isNotEmpty) {
          return reply;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Học lại chỉ 1 tài liệu/ảnh cụ thể
  Future<bool> relearnSingleDocument(KnowledgeDocument doc, {void Function(String status)? onProgress}) async {
    try {
      if (onProgress != null) {
        onProgress('Đang quét lại tài liệu ${doc.name}...');
      }

      Uint8List? fileBytes;
      if (!kIsWeb && doc.path.isNotEmpty) {
        final f = File(doc.path);
        if (await f.exists()) {
          fileBytes = await f.readAsBytes();
        }
      }

      String newContent = '';
      if (fileBytes != null && fileBytes.isNotEmpty) {
        newContent = await _extractContent(fileBytes, doc.extension, doc.name, filePath: doc.path, onProgress: onProgress);
      } else if (doc.isImage && doc.content.contains('data:image')) {
        final regex = RegExp(r'data:image\/[a-zA-Z]+;base64,([a-zA-Z0-9+/=]+)');
        final match = regex.firstMatch(doc.content);
        if (match != null) {
          final rawB64 = match.group(1);
          if (rawB64 != null) {
            fileBytes = base64Decode(rawB64);
            newContent = await _extractContent(fileBytes, doc.extension, doc.name, filePath: doc.path, onProgress: onProgress);
          }
        }
      }

      if (newContent.isNotEmpty) {
        if (kIsWeb) {
          try {
            final gateway = await _storage.getGatewayUrl();
            final uri = gateway.isNotEmpty
                ? Uri.parse('$gateway/api/docs.php?action=update')
                : _resolveUri('/api/docs.php?action=update');
            final encContent = _enc.encryptValue(newContent);
            final res = await http.post(
              uri,
              headers: await _getWebHeaders(),
              body: jsonEncode({'id': doc.id, 'content': encContent}),
            ).timeout(const Duration(seconds: 30));
            return res.statusCode == 200;
          } catch (_) {
            return false;
          }
        }
        final db = await _dbService.getRawDatabase();
        if (db != null) {
          final encContent = _enc.encryptValue(newContent);
          await db.update(
            'knowledge_documents',
            {'content': encContent},
            where: 'id = ?',
            whereArgs: [doc.id],
          );
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Nút "Học lại toàn bộ tài liệu & hình ảnh" (Re-indexing / Re-learning)
  Future<Map<String, dynamic>> relearnAllDocuments({
    void Function(String currentDoc, int current, int total)? onProgress,
  }) async {
    final docs = await getDocuments();
    if (docs.isEmpty) {
      return {'success': true, 'total': 0, 'updated': 0};
    }

    int updatedCount = 0;
    final total = docs.length;

    for (int i = 0; i < total; i++) {
      final doc = docs[i];
      if (onProgress != null) {
        onProgress(doc.name, i + 1, total);
      }

      final success = await relearnSingleDocument(doc, onProgress: (status) {
        if (onProgress != null) {
          onProgress('${doc.name} ($status)', i + 1, total);
        }
      });

      if (success) updatedCount++;
    }

    return {'success': true, 'total': total, 'updated': updatedCount};
  }

  Future<bool> toggleDocument(int id, bool isEnabled) async {
    if (kIsWeb) {
      try {
        final gateway = await _storage.getGatewayUrl();
        final uri = gateway.isNotEmpty
            ? Uri.parse('$gateway/api/docs.php?action=toggle')
            : _resolveUri('/api/docs.php?action=toggle');
        final res = await http.post(
          uri,
          headers: await _getWebHeaders(),
          body: jsonEncode({'id': id, 'is_enabled': isEnabled ? 1 : 0}),
        ).timeout(const Duration(seconds: 15));
        return res.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
    try {
      final db = await _dbService.getRawDatabase();
      if (db == null) return false;
      await db.update(
        'knowledge_documents',
        {'is_enabled': isEnabled ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteDocument(int id) async {
    if (kIsWeb) {
      try {
        final gateway = await _storage.getGatewayUrl();
        final uri = gateway.isNotEmpty
            ? Uri.parse('$gateway/api/docs.php?id=$id')
            : _resolveUri('/api/docs.php?id=$id');
        final res = await http.delete(
          uri,
          headers: await _getWebHeaders(),
        ).timeout(const Duration(seconds: 15));
        return res.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
    try {
      final db = await _dbService.getRawDatabase();
      if (db == null) return false;
      await db.delete(
        'knowledge_documents',
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Trích xuất TẤT CẢ các đoạn văn bản & phân tích hình ảnh từ các tài liệu đang kích hoạt
  Future<String> getRelevantKnowledgeContext(String userQuery) async {
    final docs = await getDocuments();
    final enabledDocs = docs.where((d) => d.isEnabled && d.content.isNotEmpty).toList();
    if (enabledDocs.isEmpty) return '';

    final queryTokens = _tokenize(userQuery);
    if (queryTokens.isEmpty) {
      return getEnabledKnowledgeContext();
    }

    final matchedSections = <Map<String, dynamic>>[];

    for (final doc in enabledDocs) {
      final chunks = _splitIntoChunks(doc.content, chunkSize: 500, overlap: 80);
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final score = _calculateRelevanceScore(chunk, queryTokens, userQuery);
        if (score > 0) {
          matchedSections.add({
            'docName': doc.name,
            'isImage': doc.isImage,
            'isScannedPdf': doc.isScannedPdf,
            'chunkIndex': i + 1,
            'content': chunk,
            'score': score,
          });
        }
      }
    }

    if (matchedSections.isEmpty) {
      // Câu hỏi không liên quan đến tài liệu -> Không đính kèm tài liệu vào prompt
      // để AI tự do dùng kiến thức tổng quát và tư duy của chính nó trả lời.
      return '';
    }

    matchedSections.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    final sb = StringBuffer();
    sb.writeln('\n\n=== NỘI DUNG TÀI LIỆU THAM KHẢO & NGHIÊN CỨU THÊM (REFERENCE ONLY) ===');
    sb.writeln('Người dùng cung cấp một số đoạn trích xuất liên quan dưới đây CHỈ ĐỂ BẠN THAM KHẢO, NGHIÊN CỨU BỔ SUNG THÔNG TIN CHO ĐẦY ĐỦ HƠN:');
    sb.writeln('- Đây KHÔNG PHẢI là nguồn giới hạn hoặc duy nhất mà bạn bắt buộc phải dựa vào.');
    sb.writeln('- Hãy kết hợp với kiến thức chuyên môn, suy luận logic tự nhiên của bạn để đưa ra câu trả lời toàn diện, sâu sắc và hữu ích nhất:');

    int totalChars = 0;
    const maxContextChars = 120000;

    for (int i = 0; i < matchedSections.length; i++) {
      final item = matchedSections[i];
      final chunkContent = item['content'] as String;
      final docName = item['docName'] as String;
      final isImg = item['isImage'] as bool? ?? false;
      final isScan = item['isScannedPdf'] as bool? ?? false;
      final chunkIdx = item['chunkIndex'] as int;

      if (totalChars + chunkContent.length > maxContextChars) {
        sb.writeln('\n... [Đã lấy đủ toàn bộ các đoạn có độ khớp cao nhất để đảm bảo an toàn bộ nhớ] ...');
        break;
      }

      final prefix = isImg ? '[Hình ảnh' : (isScan ? '[PDF Scan' : '[Đoạn');
      sb.writeln('\n--- $prefix $chunkIdx - Nguồn: $docName] ---');
      sb.writeln(chunkContent.trim());
      totalChars += chunkContent.length;
    }

    sb.writeln('\n=== HẾT PHẦN ĐOẠN VĂN TRI THỨC LIÊN QUAN ===\n');
    return sb.toString();
  }

  List<String> _splitIntoChunks(String text, {int chunkSize = 500, int overlap = 80}) {
    final cleanText = text.replaceAll('\r\n', '\n');
    final paragraphs = cleanText.split(RegExp(r'\n\s*\n'));
    final result = <String>[];

    String currentChunk = '';

    for (final p in paragraphs) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.length > chunkSize) {
        final sentences = trimmed.split(RegExp(r'(?<=[.!?\n])\s+'));
        for (final s in sentences) {
          if ((currentChunk.length + s.length) <= chunkSize) {
            currentChunk = currentChunk.isEmpty ? s : '$currentChunk\n$s';
          } else {
            if (currentChunk.isNotEmpty) {
              result.add(currentChunk.trim());
              final overlapStart = max(0, currentChunk.length - overlap);
              currentChunk = '${currentChunk.substring(overlapStart)}\n$s';
            } else {
              result.add(s.trim());
              currentChunk = '';
            }
          }
        }
      } else {
        if ((currentChunk.length + trimmed.length) <= chunkSize) {
          currentChunk = currentChunk.isEmpty ? trimmed : '$currentChunk\n\n$trimmed';
        } else {
          if (currentChunk.isNotEmpty) {
            result.add(currentChunk.trim());
            final overlapStart = max(0, currentChunk.length - overlap);
            currentChunk = '${currentChunk.substring(overlapStart)}\n\n$trimmed';
          } else {
            currentChunk = trimmed;
          }
        }
      }
    }

    if (currentChunk.trim().isNotEmpty) {
      result.add(currentChunk.trim());
    }

    return result;
  }

  double _calculateRelevanceScore(String chunk, Set<String> queryTokens, String fullQuery) {
    final lowerChunk = chunk.toLowerCase();
    final lowerQuery = fullQuery.toLowerCase().trim();

    double score = 0.0;

    if (lowerChunk.contains(lowerQuery) && lowerQuery.length > 3) {
      score += 50.0;
    }

    int matchedCount = 0;
    for (final token in queryTokens) {
      if (lowerChunk.contains(token)) {
        matchedCount++;
        score += (token.length > 4 ? 2.5 : 1.0);
      }
    }

    if (matchedCount > 0) {
      final ratio = matchedCount / queryTokens.length;
      score += ratio * 20.0;
    }

    return score;
  }

  Set<String> _tokenize(String query) {
    final clean = query.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s_]', unicode: true), ' ');
    final rawTokens = clean.split(RegExp(r'\s+'));
    const stopWords = {
      'là', 'gì', 'thế', 'nào', 'sao', 'và', 'hoặc', 'của', 'ở', 'tại',
      'cho', 'với', 'trong', 'được', 'có', 'không', 'như', 'đã', 'sẽ',
      'đang', 'các', 'những', 'cái', 'con', 'người', 'hãy', 'giúp', 'tôi',
      'tao', 'mày', 'em', 'anh', 'chị', 'bạn', 'về', 'này', 'đó', 'kia'
    };

    final result = <String>{};
    for (final t in rawTokens) {
      final trimmed = t.trim();
      if (trimmed.length >= 2 && !stopWords.contains(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  Future<String> getEnabledKnowledgeContext() async {
    final docs = await getDocuments();
    final enabledDocs = docs.where((d) => d.isEnabled && d.content.isNotEmpty).toList();
    if (enabledDocs.isEmpty) return '';

    final sb = StringBuffer();
    sb.writeln('\n\n=== TÀI LIỆU THAM KHẢO & NGHIÊN CỨU THÊM (REFERENCE ONLY) ===');
    sb.writeln('Sau đây là tài liệu người dùng nạp vào CHỈ ĐỂ BẠN THAM KHẢO VÀ NGHIÊN CỨU BỔ TRỢ (không phải nguồn duy nhất để lấy trả lời):');
    for (final d in enabledDocs) {
      final typeLabel = d.isImage ? 'Hình ảnh' : (d.isScannedPdf ? 'PDF Scan OCR' : 'Tài liệu');
      sb.writeln('\n--- [$typeLabel: ${d.name} (${d.formattedSize})] ---');
      final contentSnippet = d.content.length > 15000 ? '${d.content.substring(0, 15000)}\n...[Cắt ngắn bớt do độ dài]...' : d.content;
      sb.writeln(contentSnippet);
    }
    sb.writeln('=== HẾT PHẦN TÀI LIỆU TRI THỨC ===\n');
    return sb.toString();
  }
}
