import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import 'encryption_service.dart';

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
    // Single local database mode
    if (_db == null || !_db!.isOpen) {
      await init();
    }
  }

  Future<void> init({String? userKey}) async {
    if (_db != null && _db!.isOpen) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _resolvedPath = await _resolveDbPath();
    _db = await openDatabase(
      _resolvedPath!,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER DEFAULT 0,
            working_dir TEXT,
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
    try {
      await _db!.execute('ALTER TABLE chat_sessions ADD COLUMN working_dir TEXT;');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE chat_sessions ADD COLUMN doc_files TEXT;');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE chat_sessions ADD COLUMN target_server TEXT;');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE chat_sessions ADD COLUMN cli_conv_id TEXT;');
    } catch (_) {}
  }

  Future<String> _resolveDbPath() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isNotEmpty) {
      final appDir = Directory(p.join(home, '.ai_type_agent'));
      if (!appDir.existsSync()) {
        try {
          appDir.createSync(recursive: true);
        } catch (_) {}
      }
      final targetPath = p.join(appDir.path, 'chat_history.db');
      final targetFile = File(targetPath);
      if (!targetFile.existsSync()) {
        final legacyDb = File(p.join(home, '.tadu_ai_agent', 'chat_history.db'));
        if (legacyDb.existsSync()) {
          try {
            legacyDb.copySync(targetPath);
          } catch (_) {}
        }
      }
      return targetPath;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return p.join(appDocDir.path, 'chat_history.db');
    } catch (_) {
      return 'chat_history.db';
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
        'SELECT id, title, is_pinned, working_dir, doc_files, target_server, created_at, updated_at FROM chat_sessions ORDER BY is_pinned DESC, updated_at DESC, id DESC',
      );

      final result = <ChatSessionModel>[];
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final rawTitle = row['title']?.toString() ?? '';
        final decTitle = _enc.decryptValue(rawTitle);
        final rawScope = row['working_dir']?.toString();
        final decScope = (rawScope != null && rawScope.isNotEmpty) ? _enc.decryptValue(rawScope) : null;
        final rawDocs = row['doc_files']?.toString();
        final decDocs = (rawDocs != null && rawDocs.isNotEmpty) ? _enc.decryptValue(rawDocs) : null;
        List<String> docList = const [];
        if (decDocs != null && decDocs.isNotEmpty) {
          try {
            final decoded = jsonDecode(decDocs);
            if (decoded is List) {
              docList = decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
            }
          } catch (_) {
            docList = decDocs.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        }
        final rawServer = row['target_server']?.toString();
        final decServer = (rawServer != null && rawServer.isNotEmpty)
            ? _enc.decryptValue(rawServer)
            : 'Local Machine';

        // Count user questions (role = 'user')
        final qCountRows = await db.rawQuery(
          "SELECT COUNT(*) as count FROM chat_messages WHERE session_id = ? AND role = 'user'",
          [id],
        );
        final qCount = (qCountRows.isNotEmpty && qCountRows.first['count'] != null)
            ? int.tryParse(qCountRows.first['count'].toString()) ?? 0
            : 0;

        // Count assistant answers (role = 'assistant')
        final aCountRows = await db.rawQuery(
          "SELECT COUNT(*) as count FROM chat_messages WHERE session_id = ? AND role = 'assistant'",
          [id],
        );
        final aCount = (aCountRows.isNotEmpty && aCountRows.first['count'] != null)
            ? int.tryParse(aCountRows.first['count'].toString()) ?? 0
            : 0;

        final totalMsgCount = qCount + aCount;

        result.add(
          ChatSessionModel(
            id: id,
            title: decTitle.isNotEmpty ? decTitle : 'Cuộc hội thoại',
            isPinned: row['is_pinned'] == 1 || row['is_pinned'] == true,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
            updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
            messageCount: totalMsgCount,
            questionCount: qCount,
            answerCount: aCount,
            workingDirScope: decScope,
            docFiles: docList,
            targetServer: decServer,
          ),
        );
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<ChatSessionModel> createSession({
    String? id,
    String title = 'Cuộc hội thoại mới',
    String? workingDir,
    String? targetServer,
  }) async {
    final db = await _getDb();
    final sessId = id ?? 's_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final encTitle = _enc.encryptValue(title);
    final encScope = (workingDir != null && workingDir.isNotEmpty) ? _enc.encryptValue(workingDir) : null;
    final finalServer = (targetServer != null && targetServer.isNotEmpty) ? targetServer : 'Local Machine';
    final encServer = _enc.encryptValue(finalServer);
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'chat_sessions',
      {
        'id': sessId,
        'title': encTitle,
        'is_pinned': 0,
        'working_dir': encScope,
        'target_server': encServer,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return ChatSessionModel(
      id: sessId,
      title: title,
      isPinned: false,
      workingDirScope: workingDir,
      targetServer: finalServer,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<bool> updateSessionServer(String id, String? targetServer) async {
    try {
      final db = await _getDb();
      final encServer = (targetServer != null && targetServer.isNotEmpty) ? _enc.encryptValue(targetServer) : null;
      final now = DateTime.now().toIso8601String();
      await db.update(
        'chat_sessions',
        {
          'target_server': encServer,
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

  Future<bool> updateSessionScope(String id, String? scope, {List<String>? docFiles}) async {
    try {
      final db = await _getDb();
      final encScope = (scope != null && scope.isNotEmpty) ? _enc.encryptValue(scope) : null;
      final encDocs = (docFiles != null && docFiles.isNotEmpty) ? _enc.encryptValue(jsonEncode(docFiles)) : null;
      final now = DateTime.now().toIso8601String();
      final Map<String, dynamic> values = {
        'working_dir': encScope,
        'updated_at': now,
      };
      if (docFiles != null) {
        values['doc_files'] = encDocs;
      }
      await db.update(
        'chat_sessions',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    } catch (_) {
      return false;
    }
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

  Future<String?> getCliConversationId(String sessionId) async {
    try {
      final db = await _getDb();
      final rows = await db.query(
        'chat_sessions',
        columns: ['cli_conv_id'],
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      if (rows.isNotEmpty && rows.first['cli_conv_id'] != null) {
        final val = rows.first['cli_conv_id']?.toString().trim() ?? '';
        return val.isNotEmpty ? val : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCliConversationId(String sessionId, String cliConvId) async {
    try {
      final db = await _getDb();
      await db.update(
        'chat_sessions',
        {'cli_conv_id': cliConvId.trim()},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (_) {}
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

  Future<bool> deleteAllSessions() async {
    try {
      final db = await _getDb();
      await db.delete('chat_messages');
      await db.delete('chat_sessions');
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

  Future<List<String>> getRecentUserQuestions(String sessionId, {int limit = 5}) async {
    try {
      final db = await _getDb();
      final rows = await db.rawQuery(
        "SELECT content FROM chat_messages WHERE session_id = ? AND role = 'user' ORDER BY id DESC LIMIT ?",
        [sessionId, limit],
      );
      final questions = <String>[];
      final systemMsgRegex = RegExp(
        r'(?:The following is a <SYSTEM_MESSAGE>[^\n]*\n+)?<SYSTEM_MESSAGE>[\s\S]*?<\/SYSTEM_MESSAGE>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final r in rows) {
        final raw = r['content']?.toString() ?? '';
        var dec = _enc.decryptValue(raw).trim();
        if (dec.contains('<SYSTEM_MESSAGE>')) {
          dec = dec.replaceAll(systemMsgRegex, '').trim();
        }
        if (dec.isNotEmpty && !questions.contains(dec)) {
          questions.add(dec);
        }
      }
      return questions;
    } catch (e) {
      return [];
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
