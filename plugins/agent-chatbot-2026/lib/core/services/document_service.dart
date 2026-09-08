import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_service.dart';
import 'encryption_service.dart';
import 'local_config_service.dart';

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
    return ext == 'pdf' && (content.contains('OCR & Thị giác Vision AI') || content.contains('Trang PDF Scan') || content.contains('PDF DẠNG SCAN'));
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

  Future<List<KnowledgeDocument>> getDocuments() async {
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
      await _dbService.init();
      final db = await _dbService.getRawDatabase();
      if (db == null) return 0;
      await _ensureTable(db);

      final ext = p.extension(filePath).replaceAll('.', '').toLowerCase();
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
      }

      final encContent = _enc.encryptValue(content);
      final doc = KnowledgeDocument(
        name: name,
        extension: ext,
        size: size,
        path: filePath,
        content: encContent,
        isEnabled: true,
        createdAt: DateTime.now(),
      );

      return await db.insert('knowledge_documents', doc.toMap());
    } catch (_) {
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
    if (onProgress != null) {
      onProgress('Đang dùng AI Trí tuệ tài liệu phân tích & trích xuất $filename...');
    }

    // 1. Ưu tiên 100% dùng AI Document & Vision để trích xuất sạch sẽ, chuẩn xác cho cả Web & Online
    final aiContent = await _analyzeDocumentWithAi(bytes, 'pdf', filename);
    if (aiContent != null && aiContent.isNotEmpty) {
      return '=== [TÀI LIỆU PDF: $filename (ĐÃ ĐƯỢC AI TRÍCH XUẤT CHÍNH XÁC)] ===\n$aiContent\n=== [HẾT TÀI LIỆU PDF] ===';
    }

    // 2. Dự phòng môi trường Desktop nếu AI tạm thời mất mạng: Thử dùng công cụ hệ thống nếu có
    if (!kIsWeb && filePath != null && filePath.isNotEmpty) {
      try {
        final f = File(filePath);
        if (await f.exists()) {
          final result = await Process.run('pdftotext', [filePath, '-']);
          if (result.exitCode == 0) {
            final text = result.stdout.toString().trim();
            if (text.isNotEmpty) {
              return '=== [TÀI LIỆU PDF: $filename] ===\n$text\n=== [HẾT TÀI LIỆU PDF] ===';
            }
          }
        }
      } catch (_) {}
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
      final res = await client.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Bạn là chuyên gia thị giác AI phân tích tài liệu và OCR chính xác cao. Hãy đọc toàn bộ chữ viết, các con số, số liệu bảng biểu, tiêu đề, nội dung ghi chú và giải thích cấu trúc có trong trang/bức ảnh "$filename" này. Trình bày chi tiết, chuẩn xác bằng tiếng Việt để nạp vào cơ sở tri thức cho hệ thống.'
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
      final res = await client.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Bạn là hệ thống AI phân tích tài liệu (Document Intelligence) cao cấp. Hãy đọc toàn bộ văn bản, số liệu, bảng biểu, thông tin chi tiết và tóm tắt cấu trúc có trong tệp tài liệu "$filename" (định dạng $ext) này. Bóc tách và xuất ra toàn bộ nội dung chữ tiếng Việt chi tiết, chuẩn xác 100% để lưu vào cơ sở tri thức hệ thống.'
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
      ).timeout(const Duration(seconds: 60));

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
