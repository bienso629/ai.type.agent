import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

/// Vai trò hoạt động của ứng dụng trong mô hình App Chính <-> App Phụ.
enum AppRole {
  /// App Chính: chạy cục bộ đầy đủ và có thể mở máy chủ điều khiển từ xa cho App Phụ kết nối.
  primary,

  /// App Phụ: kết nối từ xa tới App Chính để điều khiển toàn bộ hội thoại, AI Agent, lịch việc, máy chủ và terminal.
  secondary,
}

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  static const String _keyGatewayUrl = 'gateway_url';
  static const String _keySecretToken = 'secret_token';
  static const String _keyAppRole = 'app_role';
  static const String _keyPrimaryHostEnabled = 'primary_host_enabled';
  static const String _keyPrimaryHostPort = 'primary_host_port';
  static const String _keyPrimaryHostToken = 'primary_host_token';
  static const String _keyPrimaryHostName = 'primary_host_name';
  static const String _keyPrimarySecondaryWorkspacesRoot = 'primary_secondary_workspaces_root';
  static const String _keyPrimaryTunnelMode = 'primary_tunnel_mode';
  static const String _keyPrimaryTunnelNamedToken = 'primary_tunnel_named_token';
  static const String _keyPrimaryTunnelCustomUrl = 'primary_tunnel_custom_url';
  static const String _keyClientDeviceId = 'remote_client_device_id';
  static const String _keyRevokedClientIds = 'primary_revoked_client_ids';
  static const String _keyActiveServerId = 'active_server_id';
  static const String _keyDefaultModel = 'default_ai_model';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserName = 'user_name';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyRememberMe = 'remember_me';
  static const String _keyAiTypeAdminApiUrl = 'aitype_admin_api_url';
  static const String _keyAiTypeAdminAuthMode = 'aitype_admin_auth_mode';
  static const String _keyAiTypeAdminToken = 'aitype_admin_token';
  static const String _keyAiTypeAdminUser = 'aitype_admin_user';

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  // App Role (Primary / Secondary)
  Future<AppRole> getAppRole() async {
    await init();
    final raw = _prefs.getString(_keyAppRole);
    if (raw == 'secondary') return AppRole.secondary;
    return AppRole.primary;
  }

  Future<void> setAppRole(AppRole role) async {
    await init();
    await _prefs.setString(_keyAppRole, role == AppRole.secondary ? 'secondary' : 'primary');
  }

  // Primary Host Remote Control Server Settings
  Future<bool> getPrimaryHostEnabled() async {
    await init();
    return _prefs.getBool(_keyPrimaryHostEnabled) ?? false;
  }

  Future<void> setPrimaryHostEnabled(bool enabled) async {
    await init();
    await _prefs.setBool(_keyPrimaryHostEnabled, enabled);
  }

  Future<int> getPrimaryHostPort() async {
    await init();
    final p = _prefs.getInt(_keyPrimaryHostPort) ?? ApiConstants.defaultPrimaryHostPort;
    return (p >= 1024 && p <= 65535) ? p : ApiConstants.defaultPrimaryHostPort;
  }

  Future<void> setPrimaryHostPort(int port) async {
    await init();
    final safePort = (port >= 1024 && port <= 65535) ? port : ApiConstants.defaultPrimaryHostPort;
    await _prefs.setInt(_keyPrimaryHostPort, safePort);
  }

  static String generateSecureToken({int bytes = 16}) {
    final rng = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buf.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  Future<String> getPrimaryHostToken() async {
    await init();
    var token = _prefs.getString(_keyPrimaryHostToken)?.trim() ?? '';
    if (token.isEmpty) {
      token = generateSecureToken();
      await _prefs.setString(_keyPrimaryHostToken, token);
    }
    return token;
  }

  Future<void> setPrimaryHostToken(String token) async {
    await init();
    final clean = token.trim();
    if (clean.isEmpty) return;
    await _prefs.setString(_keyPrimaryHostToken, clean);
  }

  Future<String> regeneratePrimaryHostToken() async {
    final next = generateSecureToken();
    await setPrimaryHostToken(next);
    return next;
  }

  Future<String> getPrimaryHostName() async {
    await init();
    final saved = _prefs.getString(_keyPrimaryHostName)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'AI Type Agent (${Platform.operatingSystem.toUpperCase()})';
  }

  Future<void> setPrimaryHostName(String name) async {
    await init();
    final clean = name.trim();
    if (clean.isEmpty) {
      await _prefs.remove(_keyPrimaryHostName);
    } else {
      await _prefs.setString(_keyPrimaryHostName, clean);
    }
  }

  /// Thư mục gốc mặc định trên máy App Chính chứa các thư mục làm việc riêng cho từng thiết bị App Phụ.
  static String defaultSecondaryWorkspacesRoot() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.trim().isNotEmpty) {
      return p.join(home.trim(), 'AI_Type_Workspaces');
    }
    return p.join(Directory.current.path, 'AI_Type_Workspaces');
  }

  /// Đọc đường dẫn thư mục gốc chứa workspace cho các App Phụ đã cấu hình trên App Chính.
  Future<String> getSecondaryWorkspacesRoot() async {
    await init();
    final saved = _prefs.getString(_keyPrimarySecondaryWorkspacesRoot)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return defaultSecondaryWorkspacesRoot();
  }

  /// Lưu đường dẫn thư mục gốc chứa workspace cho các App Phụ trên App Chính.
  Future<void> setSecondaryWorkspacesRoot(String path) async {
    await init();
    final clean = path.trim();
    if (clean.isEmpty) {
      await _prefs.remove(_keyPrimarySecondaryWorkspacesRoot);
    } else {
      await _prefs.setString(_keyPrimarySecondaryWorkspacesRoot, clean);
    }
  }

  /// Định danh duy nhất và ổn định của thiết bị hiện tại khi đóng vai trò App Phụ.
  Future<String> getClientDeviceId() async {
    await init();
    var id = _prefs.getString(_keyClientDeviceId)?.trim() ?? '';
    if (id.isEmpty) {
      id = 'dev_${generateSecureToken(bytes: 8)}';
      await _prefs.setString(_keyClientDeviceId, id);
    }
    return id;
  }

  Future<void> setClientDeviceId(String id) async {
    await init();
    final clean = id.trim();
    if (clean.isEmpty) return;
    await _prefs.setString(_keyClientDeviceId, clean);
  }

  /// Tên hiển thị thân thiện của thiết bị App Phụ gửi lên App Chính.
  Future<String> getClientDeviceName() async {
    await init();
    final saved = _prefs.getString(_keyPrimaryHostName)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    } catch (_) {}
    if (Platform.isAndroid) return 'Điện thoại Android';
    if (Platform.isIOS) return 'iPhone / iPad';
    return 'AI Type (${Platform.operatingSystem.toUpperCase()})';
  }

  /// Danh sách client_id của các App Phụ đã bị App Chính ngắt kết nối/thu hồi quyền truy cập.
  Future<List<String>> getRevokedClientIds() async {
    await init();
    return List<String>.from(_prefs.getStringList(_keyRevokedClientIds) ?? const <String>[]);
  }

  Future<void> setRevokedClientIds(List<String> ids) async {
    await init();
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    await _prefs.setStringList(_keyRevokedClientIds, clean);
  }

  // Primary Internet Tunnel Settings (Truy cập từ bất kỳ đâu qua Internet)
  Future<String> getPrimaryTunnelMode() async {
    await init();
    return _prefs.getString(_keyPrimaryTunnelMode) ?? 'off';
  }

  Future<void> setPrimaryTunnelMode(String mode) async {
    await init();
    await _prefs.setString(_keyPrimaryTunnelMode, mode.trim());
  }

  Future<String> getPrimaryTunnelNamedToken() async {
    await init();
    return _prefs.getString(_keyPrimaryTunnelNamedToken) ?? '';
  }

  Future<void> setPrimaryTunnelNamedToken(String token) async {
    await init();
    final clean = token.trim();
    if (clean.isEmpty) {
      await _prefs.remove(_keyPrimaryTunnelNamedToken);
    } else {
      await _prefs.setString(_keyPrimaryTunnelNamedToken, clean);
    }
  }

  Future<String> getPrimaryTunnelCustomUrl() async {
    await init();
    return _prefs.getString(_keyPrimaryTunnelCustomUrl) ?? '';
  }

  Future<void> setPrimaryTunnelCustomUrl(String url) async {
    await init();
    final clean = url.trim();
    if (clean.isEmpty) {
      await _prefs.remove(_keyPrimaryTunnelCustomUrl);
    } else {
      await _prefs.setString(_keyPrimaryTunnelCustomUrl, clean);
    }
  }

  /// Tách chuỗi ghép nối nhanh dạng `http://192.168.1.10:8765#<token>`,
  /// `https://xxx.trycloudflare.com#<token>&lan=http://192.168.1.10:8765` hoặc `aitype://...`.
  static ({String url, String token, List<String> fallbackUrls}) parsePairingString(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return (url: '', token: '', fallbackUrls: const []);
    if (text.startsWith('aitype://')) {
      text = 'http://${text.substring('aitype://'.length)}';
    }
    String urlPart = text;
    String tokenPart = '';
    final fallbacks = <String>[];

    String normalizeUrl(String u) {
      var clean = u.trim();
      if (clean.isEmpty) return '';
      if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
        clean = 'http://$clean';
      }
      while (clean.endsWith('/')) {
        clean = clean.substring(0, clean.length - 1);
      }
      return clean;
    }

    final hashIdx = text.indexOf('#');
    if (hashIdx != -1) {
      urlPart = text.substring(0, hashIdx).trim();
      final frag = text.substring(hashIdx + 1).trim();
      if (frag.contains('&')) {
        final parts = frag.split('&');
        tokenPart = parts.first.trim();
        for (var i = 1; i < parts.length; i++) {
          final kv = parts[i].trim();
          final eq = kv.indexOf('=');
          if (eq <= 0) continue;
          final k = kv.substring(0, eq).trim().toLowerCase();
          final v = Uri.decodeComponent(kv.substring(eq + 1).trim());
          if ((k == 'lan' || k == 'vpn' || k == 'alt') && v.isNotEmpty) {
            final norm = normalizeUrl(v);
            if (norm.isNotEmpty && !fallbacks.contains(norm)) {
              fallbacks.add(norm);
            }
          }
        }
      } else {
        tokenPart = frag;
      }
    } else {
      final uri = Uri.tryParse(text);
      if (uri != null && uri.queryParameters.containsKey('token')) {
        tokenPart = uri.queryParameters['token']?.trim() ?? '';
        urlPart = Uri(
          scheme: uri.scheme,
          userInfo: uri.userInfo,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path,
        ).toString();
      }
    }
    urlPart = normalizeUrl(urlPart);
    fallbacks.removeWhere((u) => u == urlPart);
    return (url: urlPart, token: tokenPart, fallbackUrls: fallbacks);
  }

  // Gateway URL (Địa chỉ App Chính khi thiết bị ở vai trò App Phụ)
  Future<String> getGatewayUrl() async {
    await init();
    return _prefs.getString(_keyGatewayUrl) ?? '';
  }

  Future<void> setGatewayUrl(String url) async {
    await init();
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    await _prefs.setString(_keyGatewayUrl, cleanUrl);
  }

  // Secret Token
  Future<String> getSecretToken() async {
    await init();
    return _prefs.getString(_keySecretToken) ?? '';
  }

  Future<void> setSecretToken(String token) async {
    await init();
    await _prefs.setString(_keySecretToken, token.trim());
  }

  // Active Server ID
  Future<String?> getActiveServerId() async {
    await init();
    return _prefs.getString(_keyActiveServerId);
  }

  Future<void> setActiveServerId(String id) async {
    await init();
    await _prefs.setString(_keyActiveServerId, id);
  }

  // Default AI Model
  Future<String> getDefaultModel() async {
    await init();
    return _prefs.getString(_keyDefaultModel) ?? 'glm-5.3';
  }

  Future<void> setDefaultModel(String model) async {
    await init();
    await _prefs.setString(_keyDefaultModel, model);
  }

  // Biometric Auth
  Future<bool> getBiometricEnabled() async {
    await init();
    return _prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await init();
    await _prefs.setBool(_keyBiometricEnabled, enabled);
  }

  // Tadu Cloud Authentication
  Future<String?> getAuthToken() async {
    await init();
    return _prefs.getString(_keyAuthToken);
  }

  Future<void> setAuthToken(String? token) async {
    await init();
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyAuthToken);
    } else {
      await _prefs.setString(_keyAuthToken, token);
    }
  }

  Future<String?> getUserEmail() async {
    await init();
    return _prefs.getString(_keyUserEmail);
  }

  Future<void> setUserEmail(String? email) async {
    await init();
    if (email == null || email.isEmpty) {
      await _prefs.remove(_keyUserEmail);
    } else {
      await _prefs.setString(_keyUserEmail, email);
    }
  }

  Future<String?> getUserName() async {
    await init();
    return _prefs.getString(_keyUserName);
  }

  Future<void> setUserName(String? name) async {
    await init();
    if (name == null || name.isEmpty) {
      await _prefs.remove(_keyUserName);
    } else {
      await _prefs.setString(_keyUserName, name);
    }
  }

  Future<bool> isLoggedIn() async {
    await init();
    return _prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  Future<void> setLoggedIn(bool value) async {
    await init();
    await _prefs.setBool(_keyIsLoggedIn, value);
  }

  // Scope History Persistence
  static const String _keyRecentScopes = 'recent_scopes_history';

  Future<List<String>> getRecentScopes() async {
    await init();
    return _prefs.getStringList(_keyRecentScopes) ?? [];
  }

  Future<void> addRecentScope(String scope) async {
    await init();
    final clean = scope.trim();
    if (clean.isEmpty) return;
    var list = _prefs.getStringList(_keyRecentScopes) ?? [];
    list.removeWhere((item) => item.trim() == clean);
    list.insert(0, clean);
    if (list.length > 20) {
      list = list.sublist(0, 20);
    }
    await _prefs.setStringList(_keyRecentScopes, list);
  }

  Future<void> removeRecentScope(String scope) async {
    await init();
    final clean = scope.trim();
    var list = _prefs.getStringList(_keyRecentScopes) ?? [];
    list.removeWhere((item) => item.trim() == clean);
    await _prefs.setStringList(_keyRecentScopes, list);
  }

  Future<void> clearRecentScopes() async {
    await init();
    await _prefs.remove(_keyRecentScopes);
  }

  // Terminal Tabs & Split Layout Persistence
  static const String _keyTerminalSessions = 'terminal_sessions_layout';

  Future<String?> getTerminalSessions() async {
    await init();
    return _prefs.getString(_keyTerminalSessions);
  }

  Future<void> setTerminalSessions(String jsonStr) async {
    await init();
    await _prefs.setString(_keyTerminalSessions, jsonStr);
  }

  Future<bool> getRememberMe() async {
    await init();
    return _prefs.getBool(_keyRememberMe) ?? true;
  }

  Future<void> setRememberMe(bool value) async {
    await init();
    await _prefs.setBool(_keyRememberMe, value);
  }

  Future<void> clearAuth() async {
    await init();
    await _prefs.remove(_keyAuthToken);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserName);
    await _prefs.setBool(_keyIsLoggedIn, false);
  }

  // AI.Type Admin Panel Credentials (Chỉ lưu cục bộ trong Agent Coder nội bộ)
  Future<String> getAiTypeAdminApiUrl() async {
    await init();
    final saved = _prefs.getString(_keyAiTypeAdminApiUrl)?.trim() ?? '';
    return saved.isNotEmpty ? saved : 'https://apiv3.type.vn/v1';
  }

  Future<String> getAiTypeAdminAuthMode() async {
    await init();
    return _prefs.getString(_keyAiTypeAdminAuthMode) ?? 'session';
  }

  Future<String> getAiTypeAdminToken() async {
    await init();
    return _prefs.getString(_keyAiTypeAdminToken)?.trim() ?? '';
  }

  Future<String> getAiTypeAdminUser() async {
    await init();
    return _prefs.getString(_keyAiTypeAdminUser)?.trim() ?? '';
  }

  Future<void> setAiTypeAdminCredentials({
    required String apiUrl,
    required String mode,
    required String token,
    required String user,
  }) async {
    await init();
    await _prefs.setString(_keyAiTypeAdminApiUrl, apiUrl.trim());
    await _prefs.setString(_keyAiTypeAdminAuthMode, mode.trim());
    await _prefs.setString(_keyAiTypeAdminToken, token.trim());
    await _prefs.setString(_keyAiTypeAdminUser, user.trim());
  }

  Future<void> clearAiTypeAdminAuth() async {
    await init();
    await _prefs.remove(_keyAiTypeAdminToken);
    await _prefs.remove(_keyAiTypeAdminUser);
  }

  static String sanitizeUserKey(String? user) {
    if (user == null || user.trim().isEmpty) {
      return '';
    }
    var u = user.trim();
    if (u.contains('@')) {
      u = u.split('@')[0];
    }
    final cleaned = u.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').toLowerCase();
    return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<String> getUserKey() async {
    await init();
    final email = await getUserEmail();
    if (email != null && email.isNotEmpty) {
      final key = sanitizeUserKey(email);
      if (key.isNotEmpty) return key;
    }
    final name = await getUserName();
    if (name != null && name.isNotEmpty) {
      final key = sanitizeUserKey(name);
      if (key.isNotEmpty) return key;
    }
    return '';
  }
}
