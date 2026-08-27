import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import 'encryption_service.dart';
import 'storage_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  final EncryptionService _enc = EncryptionService();
  String? _resolvedPath;
  String? _currentUserKey;

  String? get resolvedPath => _resolvedPath;
  String? get currentUserKey => _currentUserKey;

  Future<void> switchUser(String userKey) async {
    final sanitized = StorageService.sanitizeUserKey(userKey);
    if (_currentUserKey == sanitized && _db != null && _db!.isOpen) return;
    _currentUserKey = sanitized;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
    _resolvedPath = null;
    await init(userKey: _currentUserKey);
  }

  Future<void> init({String? userKey}) async {
    if (userKey != null && userKey.isNotEmpty) {
      final sanitized = StorageService.sanitizeUserKey(userKey);
      if (_currentUserKey != sanitized && _db != null && _db!.isOpen) {
        await _db!.close();
        _db = null;
      }
      _currentUserKey = sanitized;
    }

    if (_db != null && _db!.isOpen) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _resolvedPath = await _resolveDbPath(userKey: _currentUserKey);
    _db = await openDatabase(
      _resolvedPath!,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT DEFAULT 'default',
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            attachments_json TEXT,
            tool_calls_json TEXT,
            model TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
  }

  Future<String> _resolveDbPath({String? userKey}) async {
    final key = userKey ?? _currentUserKey ?? await StorageService().getUserKey();
    final dbFileName = key.isNotEmpty ? 'chat_history_$key.db' : 'chat_history.db';

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final execDir = p.dirname(Platform.resolvedExecutable);
      final currentDir = Directory.current.path;
      final candidates = [
        p.join(currentDir, dbFileName),
        p.join(currentDir, '..', dbFileName),
        p.join(currentDir, '..', '..', dbFileName),
        p.join(currentDir, '..', '..', '..', dbFileName),
        p.join(execDir, dbFileName),
        p.join(execDir, '..', dbFileName),
        p.join(execDir, '..', '..', dbFileName),
        p.join(execDir, '..', '..', '..', dbFileName),
        p.join(execDir, '..', '..', '..', '..', dbFileName),
        p.join(execDir, '..', '..', '..', '..', '..', dbFileName),
        '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/$dbFileName',
        p.join(Platform.environment['HOME'] ?? '', '.tadu_ai_agent', dbFileName),
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return p.normalize(candidate);
        }
      }

      // If user-specific DB does not exist yet, search for base chat_history.db and seed/copy it
      if (key.isNotEmpty) {
        final fallbackCandidates = [
          p.join(currentDir, 'chat_history.db'),
          p.join(currentDir, '..', 'chat_history.db'),
          p.join(currentDir, '..', '..', 'chat_history.db'),
          p.join(currentDir, '..', '..', '..', 'chat_history.db'),
          p.join(execDir, 'chat_history.db'),
          p.join(execDir, '..', 'chat_history.db'),
          p.join(execDir, '..', '..', 'chat_history.db'),
          p.join(execDir, '..', '..', '..', 'chat_history.db'),
          p.join(execDir, '..', '..', '..', '..', 'chat_history.db'),
          p.join(execDir, '..', '..', '..', '..', '..', 'chat_history.db'),
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/chat_history.db',
          p.join(Platform.environment['HOME'] ?? '', '.tadu_ai_agent', 'chat_history.db'),
        ];
        for (final fallback in fallbackCandidates) {
          if (File(fallback).existsSync()) {
            final targetDir = p.dirname(fallback);
            final newPath = p.join(targetDir, dbFileName);
            try {
              File(fallback).copySync(newPath);
              return p.normalize(newPath);
            } catch (_) {
              return p.normalize(fallback);
            }
          }
        }
      }

      final defaultDesk = p.join(currentDir, dbFileName);
      return defaultDesk;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final targetPath = p.join(appDocDir.path, dbFileName);
      if (key.isNotEmpty && !File(targetPath).existsSync()) {
        final defaultDb = p.join(appDocDir.path, 'chat_history.db');
        if (File(defaultDb).existsSync()) {
          try {
            File(defaultDb).copySync(targetPath);
          } catch (_) {}
        }
      }
      return targetPath;
    } catch (_) {
      return dbFileName;
    }
  }

  Future<Database> _getDb() async {
    await init();
    return _db!;
  }

  Future<List<ChatSessionModel>> getSessions() async {
    try {
      final db = await _getDb();
      final rows = await db.rawQuery(
        'SELECT id, title, is_pinned, created_at, updated_at FROM chat_sessions ORDER BY is_pinned DESC, updated_at DESC, id DESC',
      );

      if (rows.isEmpty) {
        final defaultId = 'default';
        final encTitle = _enc.encryptValue('Cuộc hội thoại mới');
        await db.insert('chat_sessions', {
          'id': defaultId,
          'title': encTitle,
          'is_pinned': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        return [
          ChatSessionModel(
            id: defaultId,
            title: 'Cuộc hội thoại mới',
            isPinned: false,
          ),
        ];
      }

      final result = <ChatSessionModel>[];
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final rawTitle = row['title']?.toString() ?? '';
        final decTitle = _enc.decryptValue(rawTitle);

        // Count messages
        final countRows = await db.rawQuery(
          'SELECT COUNT(*) as count FROM chat_messages WHERE session_id = ?',
          [id],
        );
        final msgCount = (countRows.isNotEmpty && countRows.first['count'] != null)
            ? int.tryParse(countRows.first['count'].toString()) ?? 0
            : 0;

        result.add(
          ChatSessionModel(
            id: id,
            title: decTitle.isNotEmpty ? decTitle : 'Cuộc hội thoại',
            isPinned: row['is_pinned'] == 1 || row['is_pinned'] == true,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
            updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
            messageCount: msgCount,
          ),
        );
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<ChatSessionModel> createSession({String? id, String title = 'Cuộc hội thoại mới'}) async {
    final db = await _getDb();
    final sessId = id ?? 's_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final encTitle = _enc.encryptValue(title);
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'chat_sessions',
      {
        'id': sessId,
        'title': encTitle,
        'is_pinned': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return ChatSessionModel(
      id: sessId,
      title: title,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<bool> updateSessionTitle(String id, String title) async {
    try {
      final db = await _getDb();
      final encTitle = _enc.encryptValue(title);
      final now = DateTime.now().toIso8601String();
      await db.update(
        'chat_sessions',
        {
          'title': encTitle,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> togglePinSession(String id, {bool? isPinned}) async {
    try {
      final db = await _getDb();
      int newPin = 1;
      if (isPinned != null) {
        newPin = isPinned ? 1 : 0;
      } else {
        final row = await db.query('chat_sessions', columns: ['is_pinned'], where: 'id = ?', whereArgs: [id]);
        if (row.isNotEmpty) {
          final current = row.first['is_pinned'];
          newPin = (current == 1) ? 0 : 1;
        }
      }
      await db.update('chat_sessions', {'is_pinned': newPin}, where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSession(String id) async {
    try {
      final db = await _getDb();
      await db.delete('chat_messages', where: 'session_id = ?', whereArgs: [id]);
      await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ChatHistoryResult> getMessages(
    String sessionId, {
    int limit = 50,
    int? beforeId,
  }) async {
    try {
      final db = await _getDb();
      String query = 'SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at FROM chat_messages WHERE session_id = ?';
      final args = <dynamic>[sessionId];

      if (beforeId != null && beforeId > 0) {
        query += ' AND id < ?';
        args.add(beforeId);
      }

      query += ' ORDER BY id DESC LIMIT ?';
      args.add(limit + 1);

      final rows = await db.rawQuery(query, args);
      final hasMore = rows.length > limit;
      final displayRows = hasMore ? rows.sublist(0, limit) : rows;

      final messages = <ChatMessageModel>[];
      int oldestId = 0;

      for (final r in displayRows.reversed) {
        final id = int.tryParse(r['id']?.toString() ?? '0') ?? 0;
        if (oldestId == 0 || (id > 0 && id < oldestId)) {
          oldestId = id;
        }

        final rawContent = r['content']?.toString() ?? '';
        final decContent = _enc.decryptValue(rawContent);

        final rawToolCalls = r['tool_calls_json']?.toString();
        List<ToolExecutionItem> toolExecs = [];
        if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
          final decTools = _enc.decryptValue(rawToolCalls);
          try {
            final parsed = jsonDecode(decTools);
            if (parsed is List) {
              toolExecs = parsed
                  .whereType<Map<String, dynamic>>()
                  .map((e) => ToolExecutionItem.fromJson(e))
                  .toList();
            }
          } catch (_) {}
        }

        final rawAttachments = r['attachments_json']?.toString();
        List<AttachmentItem> attachments = [];
        if (rawAttachments != null && rawAttachments.isNotEmpty) {
          final decAtt = _enc.decryptValue(rawAttachments);
          try {
            final parsed = jsonDecode(decAtt);
            if (parsed is List) {
              attachments = parsed
                  .whereType<Map<String, dynamic>>()
                  .map((e) => AttachmentItem.fromJson(e))
                  .toList();
            }
          } catch (_) {}
        }

        messages.add(
          ChatMessageModel(
            id: id,
            sessionId: r['session_id']?.toString() ?? sessionId,
            role: r['role']?.toString() ?? 'assistant',
            content: decContent,
            model: r['model']?.toString() ?? 'glm-5.3',
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? ''),
            toolExecutions: toolExecs,
            attachments: attachments,
          ),
        );
      }

      return ChatHistoryResult(
        messages: messages,
        hasMore: hasMore,
        oldestId: oldestId,
      );
    } catch (e) {
      return ChatHistoryResult(messages: [], hasMore: false, oldestId: 0);
    }
  }

  Future<int> insertMessage(ChatMessageModel msg) async {
    try {
      final db = await _getDb();
      final encContent = _enc.encryptValue(msg.content);
      String? encTools;
      if (msg.toolExecutions.isNotEmpty) {
        final toolsJson = jsonEncode(msg.toolExecutions.map((e) => e.toJson()).toList());
        encTools = _enc.encryptValue(toolsJson);
      }
      String? encAttachments;
      if (msg.attachments.isNotEmpty) {
        final attJson = jsonEncode(msg.attachments.map((e) => e.toJson()).toList());
        encAttachments = _enc.encryptValue(attJson);
      }

      final id = await db.insert('chat_messages', {
        'session_id': msg.sessionId,
        'role': msg.role,
        'content': encContent,
        'attachments_json': encAttachments,
        'tool_calls_json': encTools,
        'model': msg.model,
        'created_at': msg.createdAt.toIso8601String(),
      });

      // Update session updated_at
      final now = DateTime.now().toIso8601String();
      await db.update(
        'chat_sessions',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [msg.sessionId],
      );

      // Auto update title if session title is still default
      if (msg.role == 'user') {
        final sessRows = await db.query(
          'chat_sessions',
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [msg.sessionId],
        );
        if (sessRows.isNotEmpty) {
          final curTitle = _enc.decryptValue(sessRows.first['title']);
          if (curTitle == 'Cuộc hội thoại mới' || curTitle.isEmpty) {
            String smartTitle = msg.content.trim().split('\n').first.trim();
            if (smartTitle.length > 60) {
              smartTitle = '${smartTitle.substring(0, 60)}...';
            }
            if (smartTitle.isNotEmpty) {
              await updateSessionTitle(msg.sessionId, smartTitle);
            }
          }
        }
      }

      return id;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> clearChat(String sessionId) async {
    try {
      final db = await _getDb();
      await db.delete('chat_messages', where: 'session_id = ?', whereArgs: [sessionId]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
