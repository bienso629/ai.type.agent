import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/user_model.dart';
import 'storage_service.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  Database? _db;
  String? _resolvedDbPath;
  static const String _defaultBackendUrl = 'http://localhost:8888';

  String? get resolvedDbPath => _resolvedDbPath;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_db != null && _db!.isOpen) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _resolvedDbPath = await _resolveUsersDbPath();
    _db = await openDatabase(
      _resolvedDbPath!,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
  }

  Future<Database> _getDb() async {
    await init();
    return _db!;
  }

  Future<String> _resolveUsersDbPath() async {
    const dbFileName = 'app_users.db';

    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      final currentDir = Directory.current.path;
      final appDataDir = p.join(Platform.environment['HOME'] ?? '', '.agent_chatbot_2026');
      final dir = Directory(appDataDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final candidates = [
        p.join(currentDir, dbFileName),
        p.join(appDataDir, dbFileName),
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return p.normalize(candidate);
        }
      }

      return p.join(appDataDir, dbFileName);
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return p.join(appDocDir.path, dbFileName);
    } catch (_) {
      return dbFileName;
    }
  }

  String _generateSalt([int length = 16]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$password::$salt');
    return sha256.convert(bytes).toString();
  }

  Future<String> _getBackendUrl() async {
    final gw = await StorageService().getGatewayUrl();
    if (gw.isNotEmpty && !gw.contains('mitom.ai')) {
      return gw;
    }
    return _defaultBackendUrl;
  }

  Future<UserModel> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim().isEmpty ? cleanEmail.split('@')[0] : name.trim();

    if (cleanEmail.isEmpty || password.isEmpty) {
      throw Exception('Email và mật khẩu không được để trống');
    }

    if (kIsWeb) {
      final backendUrl = await _getBackendUrl();
      try {
        final res = await http.post(
          Uri.parse('$backendUrl/api/auth/register.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'password': password,
            'name': cleanName,
          }),
        );
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode == 200 && data['success'] == true) {
          final payload = (data['data'] is Map<String, dynamic>)
              ? data['data'] as Map<String, dynamic>
              : data;
          final u = (payload['user'] is Map<String, dynamic>)
              ? payload['user'] as Map<String, dynamic>
              : payload;
          return UserModel(
            id: u['id'] is int ? u['id'] : int.tryParse(u['id']?.toString() ?? '0'),
            email: u['email'] ?? cleanEmail,
            name: u['name'] ?? cleanName,
            passwordHash: '',
            salt: '',
            createdAt: DateTime.now().toIso8601String(),
          );
        } else {
          throw Exception(data['message'] ?? 'Đăng ký thất bại trên Cloud Server');
        }
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Không thể kết nối đến Cloud Server: $e');
      }
    }

    final db = await _getDb();

    // Check existing email
    final existing = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('Email này đã được đăng ký trên hệ thống');
    }

    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);
    final now = DateTime.now().toIso8601String();

    final id = await db.insert('users', {
      'email': cleanEmail,
      'name': cleanName,
      'password_hash': hash,
      'salt': salt,
      'created_at': now,
    });

    return UserModel(
      id: id,
      email: cleanEmail,
      name: cleanName,
      passwordHash: hash,
      salt: salt,
      createdAt: now,
    );
  }

  Future<UserModel?> authenticate({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) return null;

    if (kIsWeb) {
      final backendUrl = await _getBackendUrl();
      try {
        final res = await http.post(
          Uri.parse('$backendUrl/api/auth/login.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'password': password,
          }),
        );
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode == 200 && data['success'] == true) {
          final payload = (data['data'] is Map<String, dynamic>)
              ? data['data'] as Map<String, dynamic>
              : data;
          final u = (payload['user'] is Map<String, dynamic>)
              ? payload['user'] as Map<String, dynamic>
              : payload;
          final token = payload['token']?.toString() ?? data['token']?.toString() ?? '';
          if (token.isNotEmpty) {
            await StorageService().setAuthToken(token);
          }
          return UserModel(
            id: u['id'] is int ? u['id'] : int.tryParse(u['id']?.toString() ?? '0'),
            email: u['email'] ?? cleanEmail,
            name: u['name'] ?? cleanEmail.split('@')[0],
            passwordHash: '',
            salt: '',
            createdAt: DateTime.now().toIso8601String(),
          );
        }
        return null;
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Không thể kết nối đến máy chủ xác thực: $e');
      }
    }

    final db = await _getDb();
    final rows = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final user = UserModel.fromMap(rows.first);
    final testHash = _hashPassword(password, user.salt);

    if (testHash == user.passwordHash) {
      return user;
    }
    return null;
  }

  Future<bool> userExists(String email) async {
    if (kIsWeb) return false;
    final db = await _getDb();
    final rows = await db.query(
      'users',
      columns: ['id'],
      where: 'LOWER(email) = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Kiểm tra xem email có phải là tài khoản đầu tiên (Admin tối cao) được tạo trong hệ thống không
  Future<bool> isFirstUser(String? email) async {
    if (email == null || email.trim().isEmpty) return false;
    final cleanEmail = email.trim().toLowerCase();

    // Tài khoản cục bộ mặc định cũng là admin
    if (cleanEmail == 'local.admin@agent.chatbot') return true;

    if (kIsWeb) {
      final token = await StorageService().getAuthToken();
      if (token != null && token.isNotEmpty) {
        final backendUrl = await _getBackendUrl();
        try {
          final res = await http.get(
            Uri.parse('$backendUrl/api/auth/me.php'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            if (data['success'] == true && data['data'] != null) {
              return data['data']['is_admin'] == true;
            }
          }
        } catch (_) {}
      }
      return false;
    }

    final db = await _getDb();
    final rows = await db.query(
      'users',
      columns: ['email'],
      orderBy: 'id ASC',
      limit: 1,
    );

    if (rows.isEmpty) return false;
    final firstEmail = rows.first['email']?.toString().toLowerCase();
    return firstEmail == cleanEmail;
  }

  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (currentPassword.isEmpty || newPassword.isEmpty) {
      throw Exception('Vui lòng nhập đầy đủ mật khẩu hiện tại và mật khẩu mới');
    }
    if (newPassword.length < 6) {
      throw Exception('Mật khẩu mới phải có tối thiểu 6 ký tự');
    }

    if (kIsWeb) {
      final token = await StorageService().getAuthToken();
      final backendUrl = await _getBackendUrl();
      final res = await http.post(
        Uri.parse('$backendUrl/api/auth/change_password.php'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        return;
      }
      throw Exception(data['error'] ?? data['message'] ?? 'Đổi mật khẩu thất bại trên máy chủ');
    }

    final db = await _getDb();
    final rows = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw Exception('Không tìm thấy tài khoản người dùng');
    }

    final user = UserModel.fromMap(rows.first);
    final testHash = _hashPassword(currentPassword, user.salt);

    if (testHash != user.passwordHash) {
      throw Exception('Mật khẩu hiện tại không chính xác');
    }

    final newSalt = _generateSalt();
    final newHash = _hashPassword(newPassword, newSalt);

    await db.update(
      'users',
      {
        'password_hash': newHash,
        'salt': newSalt,
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }
}
