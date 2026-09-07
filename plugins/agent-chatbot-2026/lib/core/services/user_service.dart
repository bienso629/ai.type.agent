import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/user_model.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  Database? _db;
  String? _resolvedDbPath;

  String? get resolvedDbPath => _resolvedDbPath;

  Future<void> init() async {
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

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
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
}
