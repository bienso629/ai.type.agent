import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/services/database_service.dart';
import '../core/services/local_config_service.dart';
import '../core/services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final DatabaseService _db = DatabaseService();
  final LocalConfigService _localConfig = LocalConfigService();
  final http.Client _client = http.Client();

  bool _isLoading = false;
  bool _isCheckingAuth = false;
  bool _isAuthenticated = true;
  String? _userEmail = 'coder@type.ai';
  String? _userName = 'Developer';
  String? _authToken = 'native_local_token';
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isAuthenticated => _isAuthenticated;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get authToken => _authToken;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    try {
      final email = await _storage.getUserEmail();
      final name = await _storage.getUserName();
      final token = await _storage.getAuthToken();
      if (email != null && email.isNotEmpty) _userEmail = email;
      if (name != null && name.isNotEmpty) _userName = name;
      if (token != null && token.isNotEmpty) _authToken = token;

      final userKey = StorageService.sanitizeUserKey(_userEmail);
      await _db.switchUser(userKey);
      await _localConfig.switchUser(userKey);
    } catch (_) {}
    _isAuthenticated = true;
    _isCheckingAuth = false;
    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final cleanEmail = email.trim();
    final cleanPass = password;

    if (cleanEmail.isEmpty || cleanPass.isEmpty) {
      _errorMessage = 'Vui lòng nhập đầy đủ Email và Mật khẩu';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _client.post(
        Uri.parse('https://api3.tadu.cloud/api/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': cleanEmail,
          'password': cleanPass,
        }),
      ).timeout(const Duration(seconds: 12));

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?;
      } catch (_) {}

      if (res.statusCode == 200 && body != null) {
        if (body['isError'] == true || body['error'] != null) {
          final errObj = body['error'];
          if (errObj is Map) {
            final msgs = <String>[];
            for (final entry in errObj.entries) {
              msgs.add(entry.value.toString());
            }
            _errorMessage = msgs.join('\n');
          } else if (errObj is String) {
            _errorMessage = errObj;
          } else if (body['message'] != null) {
            _errorMessage = body['message'].toString();
          } else {
            _errorMessage = 'Email hoặc mật khẩu không chính xác';
          }
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // Login Succeeded
        final data = body['data'];
        String token = '';
        String name = '';
        String parsedEmail = cleanEmail;

        if (data is Map<String, dynamic>) {
          token = data['token']?.toString() ??
              data['access_token']?.toString() ??
              data['jwt']?.toString() ??
              data['accessToken']?.toString() ??
              '';
          if (data['user'] is Map) {
            final userMap = data['user'] as Map<String, dynamic>;
            parsedEmail = userMap['email']?.toString() ?? cleanEmail;
            name = userMap['name']?.toString() ?? userMap['full_name']?.toString() ?? '';
          } else {
            parsedEmail = data['email']?.toString() ?? cleanEmail;
            name = data['name']?.toString() ?? '';
          }
        } else if (data is String) {
          token = data;
        }

        await _storage.setRememberMe(rememberMe);
        await _storage.setAuthToken(token);
        await _storage.setUserEmail(parsedEmail);
        await _storage.setUserName(name);
        await _storage.setLoggedIn(true);

        _authToken = token;
        _userEmail = parsedEmail;
        _userName = name;
        _isAuthenticated = true;
        _errorMessage = null;
        _isLoading = false;

        final userKey = StorageService.sanitizeUserKey(parsedEmail);
        await _db.switchUser(userKey);
        await _localConfig.switchUser(userKey);

        notifyListeners();
        return true;
      } else {
        // Handle non-200 or custom error responses
        if (body != null && body['error'] != null) {
          final errObj = body['error'];
          if (errObj is Map) {
            _errorMessage = errObj.values.map((v) => v.toString()).join('\n');
          } else {
            _errorMessage = errObj.toString();
          }
        } else if (body != null && body['message'] != null) {
          _errorMessage = body['message'].toString();
        } else {
          _errorMessage = 'Đăng nhập thất bại (Mã lỗi: ${res.statusCode})';
        }
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ xác thực Tadu Cloud: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loginStandaloneMode() async {
    _isAuthenticated = true;
    _userEmail = 'local.admin@tadu.cloud';
    _userName = 'Local Administrator';
    _authToken = 'native_local_token';
    await _storage.setLoggedIn(true);
    await _storage.setUserEmail(_userEmail!);
    await _storage.setUserName(_userName!);
    await _storage.setAuthToken(_authToken!);
    final userKey = StorageService.sanitizeUserKey(_userEmail);
    await _db.switchUser(userKey);
    await _localConfig.switchUser(userKey);
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.clearAuth();
    _isAuthenticated = false;
    _authToken = null;
    _userEmail = null;
    _userName = null;
    _errorMessage = null;
    await _db.switchUser('');
    await _localConfig.switchUser('');
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
