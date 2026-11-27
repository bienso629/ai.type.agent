import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class AiTypeAdminException implements Exception {
  final String message;
  final int? statusCode;

  AiTypeAdminException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class AiTypeAdminService {
  static final AiTypeAdminService _instance = AiTypeAdminService._internal();
  factory AiTypeAdminService() => _instance;
  AiTypeAdminService._internal();

  static const String defaultApiUrl = 'https://apiv3.type.vn/v1';

  final StorageService _storage = StorageService();
  final http.Client _client = http.Client();

  String _normalizeBaseUrl(String url) {
    var clean = url.trim();
    if (clean.isEmpty) return defaultApiUrl;
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  Future<({String apiUrl, String mode, String token, String user})> getCredentials() async {
    final apiUrl = await _storage.getAiTypeAdminApiUrl();
    final mode = await _storage.getAiTypeAdminAuthMode();
    final token = await _storage.getAiTypeAdminToken();
    final user = await _storage.getAiTypeAdminUser();
    return (
      apiUrl: _normalizeBaseUrl(apiUrl),
      mode: mode,
      token: token,
      user: user,
    );
  }

  Future<bool> hasSavedCredentials() async {
    final creds = await getCredentials();
    return creds.token.trim().isNotEmpty;
  }

  Map<String, String> _buildAuthHeaders({
    required String mode,
    required String token,
    bool jsonBody = false,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    if (token.isNotEmpty) {
      if (mode == 'secret') {
        headers['X-Admin-Secret'] = token;
      } else if (mode == 'app_token') {
        headers['X-App-Id'] = 'ai.typing';
        headers['X-App-Token'] = token;
      } else {
        headers['X-Admin-Token'] = token;
      }
    }
    return headers;
  }

  Map<String, dynamic> _parseJsonResponse(http.Response response) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = (data['message'] ?? data['error'] ?? 'Lỗi máy chủ (HTTP ${response.statusCode})').toString();
      throw AiTypeAdminException(msg, statusCode: response.statusCode);
    }

    if (data['success'] == false) {
      final msg = (data['message'] ?? data['error'] ?? 'Thao tác không thành công.').toString();
      throw AiTypeAdminException(msg, statusCode: response.statusCode);
    }

    return data;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final creds = await getCredentials();
    if (creds.token.isEmpty) {
      throw AiTypeAdminException('Chưa đăng nhập phiên quản trị AI.Type.', statusCode: 401);
    }

    var uri = Uri.parse('${creds.apiUrl}$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        ...queryParams,
      });
    }

    final headers = _buildAuthHeaders(
      mode: creds.mode,
      token: creds.token,
      jsonBody: body != null,
    );

    late http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await _client.get(uri, headers: headers).timeout(timeout);
          break;
        case 'POST':
          res = await _client
              .post(uri, headers: headers, body: body != null ? jsonEncode(body) : '{}')
              .timeout(timeout);
          break;
        case 'PUT':
          res = await _client
              .put(uri, headers: headers, body: body != null ? jsonEncode(body) : '{}')
              .timeout(timeout);
          break;
        default:
          throw AiTypeAdminException('HTTP method không hỗ trợ: $method');
      }
    } catch (e) {
      if (e is AiTypeAdminException) rethrow;
      throw AiTypeAdminException('Không thể kết nối tới ${creds.apiUrl}: $e');
    }

    return _parseJsonResponse(res);
  }

  /// Đăng nhập quản trị trực tiếp bằng tài khoản Administrator diễn đàn type.vn
  Future<Map<String, dynamic>> loginWithTypeVn({
    required String apiUrl,
    required String username,
    required String password,
  }) async {
    final baseUrl = _normalizeBaseUrl(apiUrl);
    final uri = Uri.parse('$baseUrl/payment/admin-login');

    late http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'username': username.trim(),
              'email': username.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw AiTypeAdminException('Không thể kết nối tới $baseUrl: $e');
    }

    final parsed = _parseJsonResponse(res);
    final data = (parsed['data'] as Map<String, dynamic>?) ?? {};
    final token = (data['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw AiTypeAdminException('Máy chủ không trả về mã phiên quản trị.');
    }

    final userObj = (data['user'] as Map<String, dynamic>?) ?? {};
    final displayUser = (userObj['username'] ?? userObj['email'] ?? username).toString().trim();

    await _storage.setAiTypeAdminCredentials(
      apiUrl: baseUrl,
      mode: 'session',
      token: token,
      user: displayUser,
    );

    return data;
  }

  /// Đăng nhập quản trị chỉ bằng Token (tự động thử lần lượt X-Admin-Secret, X-App-Token và X-Admin-Token)
  Future<Map<String, dynamic>> connectWithToken({
    required String apiUrl,
    required String token,
  }) async {
    final baseUrl = _normalizeBaseUrl(apiUrl);
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw AiTypeAdminException('Vui lòng nhập Token quản trị.');
    }

    const candidateModes = ['secret', 'app_token', 'session'];
    AiTypeAdminException? lastAuthError;

    for (final mode in candidateModes) {
      try {
        return await connectWithKey(
          apiUrl: baseUrl,
          mode: mode,
          token: cleanToken,
        );
      } on AiTypeAdminException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          lastAuthError = e;
          continue;
        }
        rethrow;
      }
    }

    throw lastAuthError ??
        AiTypeAdminException('Token quản trị không hợp lệ hoặc không có quyền truy cập.', statusCode: 403);
  }

  /// Kết nối bằng X-Admin-Secret, X-App-Token hoặc X-Admin-Token và xác thực quyền trước khi lưu
  Future<Map<String, dynamic>> connectWithKey({
    required String apiUrl,
    required String mode,
    required String token,
  }) async {
    final baseUrl = _normalizeBaseUrl(apiUrl);
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw AiTypeAdminException('Vui lòng nhập Token quản trị.');
    }

    final uri = Uri.parse('$baseUrl/payment/admin-summary');
    final headers = _buildAuthHeaders(mode: mode, token: cleanToken);

    late http.Response res;
    try {
      res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw AiTypeAdminException('Không thể kết nối tới $baseUrl: $e');
    }

    final parsed = _parseJsonResponse(res);
    final label = mode == 'secret'
        ? 'Admin Secret'
        : (mode == 'app_token' ? 'Admin App Token' : 'Admin Token');
    await _storage.setAiTypeAdminCredentials(
      apiUrl: baseUrl,
      mode: mode,
      token: cleanToken,
      user: label,
    );

    return (parsed['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> logout() async {
    try {
      final creds = await getCredentials();
      if (creds.mode == 'session' && creds.token.isNotEmpty) {
        await _request('POST', '/payment/admin-logout', timeout: const Duration(seconds: 8));
      }
    } catch (_) {}
    await _storage.clearAiTypeAdminAuth();
  }

  Future<Map<String, dynamic>> getSummary() async {
    final res = await _request('GET', '/payment/admin-summary');
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> getPaymentConfig() async {
    final res = await _request('GET', '/payment/admin-config');
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> updatePaymentConfig(Map<String, dynamic> payload) async {
    final res = await _request('PUT', '/payment/admin-config', body: payload);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> testBankSms({
    required String sender,
    required String message,
  }) async {
    final res = await _request(
      'POST',
      '/payment/test-sms',
      body: {'sender': sender.trim(), 'message': message.trim()},
    );
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> manualConfirmPayment({
    required String email,
    String? orderCode,
    required int months,
    int? amount,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'email': email.trim(),
      'months': months,
    };
    if (orderCode != null && orderCode.trim().isNotEmpty) {
      payload['orderCode'] = orderCode.trim().toUpperCase();
    }
    if (amount != null && amount > 0) {
      payload['amount'] = amount;
    }
    if (note != null && note.trim().isNotEmpty) {
      payload['note'] = note.trim();
    }
    return await _request('POST', '/payment/manual-confirm', body: payload);
  }

  Future<List<Map<String, dynamic>>> getTransactions({String? email}) async {
    final query = <String, String>{};
    if (email != null && email.trim().isNotEmpty) {
      query['email'] = email.trim();
    }
    final res = await _request('GET', '/payment/transactions', queryParams: query);
    final list = (res['data'] as List<dynamic>?) ?? [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<({int total, List<Map<String, dynamic>> items})> getLicenses({String? query}) async {
    final qp = <String, String>{'limit': '250'};
    if (query != null && query.trim().isNotEmpty) {
      qp['q'] = query.trim();
    }
    final res = await _request('GET', '/payment/licenses', queryParams: qp);
    final list = (res['data'] as List<dynamic>?) ?? [];
    return (
      total: (res['total'] as num?)?.toInt() ?? list.length,
      items: list.whereType<Map<String, dynamic>>().toList(),
    );
  }

  Future<Map<String, dynamic>> createLicense({
    required String email,
    String? customerName,
    String? phoneNumber,
    required int months,
    bool assignGroups = true,
  }) async {
    return await _request(
      'POST',
      '/payment/licenses',
      body: {
        'email': email.trim(),
        'customerName': (customerName ?? '').trim().isEmpty ? email.trim() : customerName!.trim(),
        'phoneNumber': (phoneNumber ?? '').trim(),
        'months': months,
        'assignGroups': assignGroups,
      },
    );
  }

  Future<Map<String, dynamic>> extendLicense({
    required String licenseKey,
    int months = 0,
    int days = 0,
  }) async {
    return await _request(
      'POST',
      '/payment/licenses/extend',
      body: {
        'licenseKey': licenseKey.trim(),
        'months': months,
        'days': days,
      },
    );
  }

  Future<({List<Map<String, dynamic>> users, List<Map<String, dynamic>> groups})> getForumUsers({
    String? query,
  }) async {
    final qp = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      qp['q'] = query.trim();
    }
    final res = await _request(
      'GET',
      '/payment/forum/users',
      queryParams: qp,
      timeout: const Duration(seconds: 45),
    );
    final users = ((res['data'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
    final groups = ((res['groups'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
    return (users: users, groups: groups);
  }

  Future<void> updateForumMembership({
    required int uid,
    required String slug,
    required bool add,
  }) async {
    await _request(
      'POST',
      '/payment/forum/membership',
      body: {
        'uid': uid,
        'slug': slug,
        'action': add ? 'add' : 'remove',
      },
    );
  }
}
