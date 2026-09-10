import 'package:flutter/foundation.dart';
import '../core/services/database_service.dart';
import '../core/services/local_config_service.dart';
import '../core/services/storage_service.dart';
import '../core/services/user_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final DatabaseService _db = DatabaseService();
  final LocalConfigService _localConfig = LocalConfigService();
  final UserService _userService = UserService();

  bool _isLoading = false;
  bool _isCheckingAuth = true;
  bool _isAuthenticated = false;
  bool _isAdmin = false;
  String? _userEmail;
  String? _userName;
  String? _authToken;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get authToken => _authToken;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    _isCheckingAuth = true;
    notifyListeners();

    try {
      await _userService.init();
      final loggedIn = await _storage.isLoggedIn();
      if (loggedIn) {
        _userEmail = await _storage.getUserEmail();
        _userName = await _storage.getUserName();
        _authToken = await _storage.getAuthToken();

        // Trên nền tảng Web, nếu token là session cũ không hợp lệ hoặc đã hỏng định dạng thì đăng xuất
        if (kIsWeb && (_authToken == null || _authToken!.isEmpty || !_authToken!.contains('.'))) {
          await _storage.clearAuth();
          _isAuthenticated = false;
          _isAdmin = false;
          _authToken = null;
          _userEmail = null;
          _userName = null;
        } else {
          _isAuthenticated = true;
          _isAdmin = await _userService.isFirstUser(_userEmail);
          final userKey = await _storage.getUserKey();
          await _db.switchUser(userKey);
          await _localConfig.switchUser(userKey);
        }
      } else {
        _isAuthenticated = false;
        _isAdmin = false;
      }
    } catch (_) {
      _isAuthenticated = false;
      _isAdmin = false;
    } finally {
      _isCheckingAuth = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    bool rememberMe = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPass = password;
    final cleanName = name.trim();

    if (cleanEmail.isEmpty || cleanPass.isEmpty) {
      _errorMessage = 'Vui lòng nhập đầy đủ Email và Mật khẩu';
      notifyListeners();
      return false;
    }

    if (cleanPass.length < 6) {
      _errorMessage = 'Mật khẩu phải từ 6 ký tự trở lên';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _userService.register(
        email: cleanEmail,
        password: cleanPass,
        name: cleanName,
      );

      String? token = await _storage.getAuthToken();
      if (token == null || token.isEmpty) {
        token = 'local_session_${DateTime.now().millisecondsSinceEpoch}_${user.id}';
        await _storage.setAuthToken(token);
      }

      await _storage.setRememberMe(rememberMe);
      await _storage.setUserEmail(user.email);
      await _storage.setUserName(user.name);
      await _storage.setLoggedIn(true);

      _authToken = token;
      _userEmail = user.email;
      _userName = user.name;
      _isAuthenticated = true;
      _isAdmin = await _userService.isFirstUser(user.email);
      _errorMessage = null;
      _isLoading = false;

      final userKey = StorageService.sanitizeUserKey(user.email);
      await _db.switchUser(userKey);
      await _localConfig.switchUser(userKey);

      notifyListeners();
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _errorMessage = msg;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
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
      final user = await _userService.authenticate(
        email: cleanEmail,
        password: cleanPass,
      );

      if (user == null) {
        _errorMessage = 'Email hoặc mật khẩu không chính xác';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      String? token = await _storage.getAuthToken();
      if (token == null || token.isEmpty) {
        token = 'local_session_${DateTime.now().millisecondsSinceEpoch}_${user.id}';
        await _storage.setAuthToken(token);
      }

      await _storage.setRememberMe(rememberMe);
      await _storage.setUserEmail(user.email);
      await _storage.setUserName(user.name);
      await _storage.setLoggedIn(true);

      _authToken = token;
      _userEmail = user.email;
      _userName = user.name;
      _isAuthenticated = true;
      _isAdmin = await _userService.isFirstUser(user.email);
      _errorMessage = null;
      _isLoading = false;

      final userKey = StorageService.sanitizeUserKey(user.email);
      await _db.switchUser(userKey);
      await _localConfig.switchUser(userKey);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Lỗi xác thực hệ thống: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loginStandaloneMode() async {
    _isAuthenticated = true;
    _isAdmin = true;
    _userEmail = 'local.admin@agent.chatbot';
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
    _isAdmin = false;
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
