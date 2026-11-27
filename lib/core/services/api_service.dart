// ignore_for_file: use_null_aware_elements
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../models/server_model.dart';
import '../../models/metrics_model.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import 'storage_service.dart';
import 'local_config_service.dart';
import 'database_service.dart';
import 'native_ai_service.dart';
import 'native_ssh_service.dart';
import 'cli_scanner_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final StorageService _storage = StorageService();
  final http.Client _client = http.Client();

  final LocalConfigService _localConfig = LocalConfigService();
  final DatabaseService _db = DatabaseService();
  final NativeAiService _ai = NativeAiService();
  final NativeSshService _ssh = NativeSshService();

  Future<bool> isNativeMode() => _isNativeMode();

  Future<bool> _isNativeMode() async {
    final role = await _storage.getAppRole();
    if (role == AppRole.secondary) {
      final gatewayUrl = await _storage.getGatewayUrl();
      return gatewayUrl.trim().isEmpty;
    }
    return true;
  }

  Future<Map<String, String>> _getHeaders({bool isJson = true}) async {
    final token = await _storage.getSecretToken();
    final userEmail = await _storage.getUserEmail();
    final headers = <String, String>{
      if (isJson) 'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-Secret-Token'] = token;
    }
    if (userEmail != null && userEmail.isNotEmpty) {
      headers['X-User-Email'] = userEmail;
      final username = userEmail.split('@')[0];
      headers['X-User-Name'] = username;
    }
    return headers;
  }

  Future<String> _getBaseUrl() async {
    return await _storage.getGatewayUrl();
  }

  // 1. Connectivity & Ping Check (Handshake với App Chính khi ở vai trò App Phụ)
  Future<Map<String, dynamic>?> getRemoteHostInfo() async {
    if (await _isNativeMode()) {
      return {
        'ok': true,
        'role': 'primary',
        'device_name': await _storage.getPrimaryHostName(),
        'os': Platform.operatingSystem,
        'app_version': '1.5.10',
      };
    }
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl.isEmpty) return null;
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map<String, dynamic>) return data;
      }
    } catch (_) {}
    return null;
  }

  Future<List<LocalCliAgent>> getRemoteCliAgents() async {
    if (await _isNativeMode()) {
      return await CliScannerService().scanInstalledAgents();
    }
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl.isEmpty) return const [];
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epModels}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['cli_agents'] is List) {
          return (data['cli_agents'] as List)
              .whereType<Map>()
              .map(
                (m) => LocalCliAgent(
                  id: m['id']?.toString() ?? '',
                  binary: m['binary']?.toString() ?? '',
                  path: m['path']?.toString() ?? '',
                  label: m['label']?.toString() ?? m['id']?.toString() ?? '',
                  version: m['version']?.toString(),
                ),
              )
              .where((a) => a.id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> checkHealth() async {
    if (await _isNativeMode()) {
      return true;
    }
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl.isEmpty) return false;
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epConfig}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 2. Config APIs
  Future<Map<String, dynamic>> getConfig() async {
    if (await _isNativeMode()) {
      return await _localConfig.loadConfig();
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.get(
      Uri.parse('$baseUrl${ApiConstants.epConfig}'),
      headers: await _getHeaders(),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Failed to load config: ${res.statusCode}');
  }

  Future<bool> saveConfig(Map<String, dynamic> config) async {
    if (await _isNativeMode()) {
      return await _localConfig.saveConfig(config);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epConfig}'),
      headers: await _getHeaders(),
      body: jsonEncode(config),
    );
    return res.statusCode == 200;
  }

  Future<List<String>> fetchRemoteModels({String? customBaseUrl, String? customApiKey}) async {
    try {
      final cfg = await getConfig();
      final providerTab = cfg['ai_provider_tab']?.toString() ?? 'proxy';
      final googleKeys = NativeAiService.extractGoogleStudioKeys(cfg);

      var baseUrl = (customBaseUrl != null && customBaseUrl.trim().isNotEmpty)
          ? customBaseUrl.trim()
          : (providerTab == 'google_studio'
              ? 'https://generativelanguage.googleapis.com/v1beta/openai'
              : (cfg['proxy_base_url']?.toString().trim() ?? ''));
      if (baseUrl.isEmpty) {
        baseUrl = 'https://openrouter.ai/api/v1';
      }
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      // Chỉ lấy key đúng nguồn theo tab đang chọn, không trộn Proxy với Google Studio.
      final candidateKeys = (customApiKey != null && customApiKey.trim().isNotEmpty)
          ? NativeAiService.extractApiKeys(customApiKey)
          : (providerTab == 'google_studio'
              ? googleKeys
              : NativeAiService.extractApiKeys(cfg['proxy_api_key']));

      final url = Uri.parse('$baseUrl/models');
      http.Response? res;
      final maxAttempts = candidateKeys.isNotEmpty ? candidateKeys.length : 1;
      for (int i = 0; i < maxAttempts; i++) {
        final key = candidateKeys.isNotEmpty ? candidateKeys[i] : '';
        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        };
        try {
          final r = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
          if (r.statusCode == 200) {
            res = r;
            break;
          }
        } catch (_) {}
      }

      if (res != null && res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final modelsList = <String>[];

        if (decoded is Map && decoded['data'] is List) {
          for (final item in decoded['data']) {
            if (item is Map && item['id'] != null) {
              final id = item['id'].toString().trim().replaceFirst(RegExp(r'^models/'), '');
              if (id.isNotEmpty && !modelsList.contains(id)) {
                modelsList.add(id);
              }
            } else if (item is String && item.trim().isNotEmpty) {
              final id = item.trim();
              if (!modelsList.contains(id)) modelsList.add(id);
            }
          }
        } else if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && item['id'] != null) {
              final id = item['id'].toString().trim().replaceFirst(RegExp(r'^models/'), '');
              if (id.isNotEmpty && !modelsList.contains(id)) {
                modelsList.add(id);
              }
            } else if (item is String && item.trim().isNotEmpty) {
              final id = item.trim();
              if (!modelsList.contains(id)) modelsList.add(id);
            }
          }
        }

        if (modelsList.isNotEmpty) {
          return modelsList;
        }
      }
    } catch (_) {}
    return [];
  }

  // 3. Servers Management APIs
  Future<List<ServerModel>> getServers() async {
    if (await _isNativeMode()) {
      return await _localConfig.getServers();
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epServers}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data.map((e) => ServerModel.fromJson(e as Map<String, dynamic>)).toList();
        } else if (data is Map<String, dynamic> && data['servers'] is List) {
          final list = data['servers'] as List;
          return list.map((e) => ServerModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> selectServer(String serverIp, [ServerModel? serverModel]) async {
    if (await _isNativeMode()) {
      if (serverModel != null) {
        return await _localConfig.selectServer(serverModel);
      }
      final servers = await _localConfig.getServers();
      final target = servers.firstWhere(
        (s) => s.serverIp == serverIp || s.id == serverIp,
        orElse: () => ServerModel(id: serverIp, name: serverIp, serverIp: serverIp),
      );
      return await _localConfig.selectServer(target);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersSelect}'),
      headers: await _getHeaders(),
      body: jsonEncode({'server_ip': serverIp}),
    );
    return res.statusCode == 200;
  }

  Future<bool> updateServer(ServerModel server) async {
    if (await _isNativeMode()) {
      return await _localConfig.addOrUpdateServer(server);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersUpdate}'),
      headers: await _getHeaders(),
      body: jsonEncode(server.toJson()),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteServer(String serverIp) async {
    if (await _isNativeMode()) {
      return await _localConfig.deleteServer(serverIp);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersDelete}'),
      headers: await _getHeaders(),
      body: jsonEncode({'server_ip': serverIp}),
    );
    return res.statusCode == 200;
  }

  Future<String> exportServers({bool includeFullConfig = false}) async {
    if (await _isNativeMode()) {
      return await _localConfig.exportServersJson(includeFullConfig: includeFullConfig);
    }
    final servers = await getServers();
    final exportData = {
      'version': '1.0.0',
      'app': 'AI Type Agent',
      'exported_at': DateTime.now().toIso8601String(),
      'servers_count': servers.length,
      'servers': servers.map((s) => s.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<int> importServers(String jsonStr, {bool overwrite = false}) async {
    if (await _isNativeMode()) {
      return await _localConfig.importServersJson(jsonStr, overwrite: overwrite);
    }
    final dynamic parsed = jsonDecode(jsonStr);
    List<dynamic> incoming = [];
    if (parsed is List) {
      incoming = parsed;
    } else if (parsed is Map && parsed['servers'] is List) {
      incoming = parsed['servers'] as List;
    }
    int count = 0;
    for (final item in incoming) {
      if (item is Map<String, dynamic>) {
        final s = ServerModel.fromJson(item);
        if (await updateServer(s)) count++;
      }
    }
    return count;
  }

  // 4. System Metrics & Info
  Future<SystemMetricsModel> getSystemMetrics() async {
    if (await _isNativeMode()) {
      return await _ssh.getSystemMetrics();
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.get(
      Uri.parse('$baseUrl${ApiConstants.epSystemInfo}'),
      headers: await _getHeaders(),
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return SystemMetricsModel.fromJson(json);
    }
    throw Exception('Failed to get metrics: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> executeServiceAction(String service, String action, {ServerModel? server}) async {
    if (await _isNativeMode()) {
      return await _ssh.executeServiceAction(service, action, server: server);
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epServiceAction}'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'service': service,
          'action': action,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'status': 'error', 'message': 'Không thể kết nối đến máy chủ'};
  }

  // 5. Service Logs API
  Future<String> getServerLogs({int lines = 100}) async {
    if (!await _isNativeMode()) {
      try {
        final baseUrl = await _getBaseUrl();
        final res = await _client.get(
          Uri.parse('$baseUrl${ApiConstants.epServerLogs}?lines=$lines'),
          headers: await _getHeaders(),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data is Map && data['logs'] != null) {
            return data['logs'].toString();
          }
          return utf8.decode(res.bodyBytes);
        }
        return 'Không thể tải nhật ký từ App Chính (HTTP ${res.statusCode}).';
      } catch (e) {
        return 'Lỗi kết nối đọc nhật ký từ App Chính: $e';
      }
    }
    try {
      if (Platform.isLinux) {
        final res = await Process.run('bash', [
          '-c',
          'journalctl -n $lines --no-pager 2>/dev/null || dmesg | tail -n $lines || ps aux | head -n $lines',
        ]).timeout(const Duration(seconds: 5));
        final out = res.stdout.toString().trim();
        return out.isNotEmpty ? out : 'Không có nhật ký hệ thống cục bộ.';
      } else if (Platform.isMacOS) {
        final res = await Process.run('bash', [
          '-c',
          'ps aux | head -n $lines',
        ]).timeout(const Duration(seconds: 5));
        final out = res.stdout.toString().trim();
        return out.isNotEmpty ? out : 'Không có nhật ký hệ thống cục bộ.';
      } else if (Platform.isWindows) {
        final res = await Process.run('cmd.exe', [
          '/c',
          'tasklist',
        ]).timeout(const Duration(seconds: 5));
        final out = res.stdout.toString().trim();
        return out.isNotEmpty ? out : 'Không có nhật ký hệ thống cục bộ.';
      }
    } catch (e) {
      return 'Lỗi tải log cục bộ: $e';
    }
    return 'Không có nhật ký.';
  }

  // 6. 1-Click Deploy Stream
  StreamSubscription<String> streamDeploy({
    ServerModel? server,
    required void Function(String step) onStep,
    required void Function() onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();

    () async {
      if (await _isNativeMode()) {
        try {
          await _ssh.streamDeploy(
            server: server,
            onStep: onStep,
            onDone: onDone,
            onError: onError,
          );
        } catch (e) {
          onError(e);
        }
        return;
      }

      http.Client? deployClient;
      try {
        final baseUrl = await _getBaseUrl();
        deployClient = http.Client();
        final request = http.Request('POST', Uri.parse('$baseUrl${ApiConstants.epServerDeploy}'));
        final headers = await _getHeaders();
        request.headers.addAll(headers);

        final streamedResponse = await deployClient.send(request);
        if (streamedResponse.statusCode != 200) {
          onError('Lỗi server: ${streamedResponse.statusCode}');
          return;
        }

        streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final stepMsg = trimmed.substring(5).trim();
              if (stepMsg.isNotEmpty) {
                onStep(stepMsg);
              }
            }
          },
          onError: (e) => onError(e),
          onDone: () {
            onDone();
            deployClient?.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        onError(e);
        deployClient?.close();
      }
    }();

    return controller.stream.listen((_) {});
  }

  // 7. Chat & AI Sessions APIs
  Future<List<ChatSessionModel>> getChatSessions() async {
    if (await _isNativeMode()) {
      return await _db.getSessions();
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data.map((e) => ChatSessionModel.fromJson(e as Map<String, dynamic>)).toList();
        } else if (data is Map<String, dynamic> && data['sessions'] is List) {
          final list = data['sessions'] as List;
          return list.map((e) => ChatSessionModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<ChatSessionModel> createChatSession({
    String title = 'Cuộc hội thoại mới',
    String? workingDir,
    String? targetServer,
    List<String>? targetServers,
  }) async {
    if (await _isNativeMode()) {
      return await _db.createSession(title: title, workingDir: workingDir, targetServer: targetServer, targetServers: targetServers);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'title': title,
        if (workingDir != null && workingDir.isNotEmpty) 'working_dir': workingDir,
        if (targetServer != null && targetServer.isNotEmpty) 'target_server': targetServer,
        if (targetServers != null && targetServers.isNotEmpty) 'target_servers': jsonEncode(targetServers),
      }),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return ChatSessionModel.fromJson(json);
    }
    throw Exception('Failed to create session');
  }

  Future<bool> updateChatSessionServer(String sessionId, String? targetServer, {List<String>? targetServers}) async {
    if (await _isNativeMode()) {
      return await _db.updateSessionServer(sessionId, targetServer, targetServers: targetServers);
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epChatSessions}/${Uri.encodeComponent(sessionId)}/server'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'target_server': targetServer,
          if (targetServers != null) 'target_servers': targetServers,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateChatSessionScope(String sessionId, String? scope, {List<String>? docFiles}) async {
    if (await _isNativeMode()) {
      return await _db.updateSessionScope(sessionId, scope, docFiles: docFiles);
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epChatSessions}/${Uri.encodeComponent(sessionId)}/scope'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'working_dir': scope,
          if (docFiles != null) 'doc_files': docFiles,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> renameChatSession(String sessionId, String newTitle) async {
    if (await _isNativeMode()) {
      return await _db.updateSessionTitle(sessionId, newTitle);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.put(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId'),
      headers: await _getHeaders(),
      body: jsonEncode({'title': newTitle}),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteChatSession(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.deleteSession(sessionId);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.delete(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId'),
      headers: await _getHeaders(),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteAllChatSessions() async {
    if (await _isNativeMode()) {
      return await _db.deleteAllSessions();
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.delete(
        Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
        headers: await _getHeaders(),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopRemoteChat(String sessionId) async {
    if (await _isNativeMode()) return;
    try {
      final baseUrl = await _getBaseUrl();
      await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epChatStop}'),
        headers: await _getHeaders(),
        body: jsonEncode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // 8b. Work Schedules API (đồng bộ SQLite cục bộ trên App Chính hoặc gọi từ xa từ App Phụ)
  Future<Map<String, dynamic>?> getWorkSchedule(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.getWorkSchedule(sessionId);
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epWorkSchedules}/${Uri.encodeComponent(sessionId)}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['schedule'] is Map) {
          return Map<String, dynamic>.from(data['schedule'] as Map);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> saveWorkSchedule({
    required String sessionId,
    required String projectName,
    required String summary,
    required List<String> docFiles,
    DateTime? generatedAt,
    required List<Map<String, dynamic>> tasks,
  }) async {
    if (await _isNativeMode()) {
      return await _db.saveWorkSchedule(
        sessionId: sessionId,
        projectName: projectName,
        summary: summary,
        docFiles: docFiles,
        generatedAt: generatedAt,
        tasks: tasks,
      );
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epWorkSchedules}/${Uri.encodeComponent(sessionId)}'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'project_name': projectName,
          'summary': summary,
          'doc_files': docFiles,
          'generated_at': (generatedAt ?? DateTime.now()).toIso8601String(),
          'tasks': tasks,
        }),
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteWorkSchedule(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.deleteWorkSchedule(sessionId);
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.delete(
        Uri.parse('$baseUrl${ApiConstants.epWorkSchedules}/${Uri.encodeComponent(sessionId)}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<int> getPendingWorkScheduleCount(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.getPendingWorkScheduleCount(sessionId);
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epWorkSchedules}/${Uri.encodeComponent(sessionId)}/pending-count'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['count'] != null) {
          return int.tryParse(data['count'].toString()) ?? 0;
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<bool> markWorkScheduleTasksDone(
    String sessionId,
    List<String> taskCodes, {
    bool done = true,
  }) async {
    if (await _isNativeMode()) {
      return await _db.markWorkScheduleTasksDone(sessionId, taskCodes, done: done);
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epWorkSchedules}/${Uri.encodeComponent(sessionId)}/done'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'task_codes': taskCodes,
          'done': done,
        }),
      ).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> togglePinSession(String sessionId, {bool? isPinned}) async {
    if (await _isNativeMode()) {
      return await _db.togglePinSession(sessionId, isPinned: isPinned);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId/pin'),
      headers: await _getHeaders(),
      body: jsonEncode(isPinned != null ? {'is_pinned': isPinned} : {}),
    );
    return res.statusCode == 200;
  }

  Future<bool> pinChatSession(String sessionId, [bool? isPinned]) =>
      togglePinSession(sessionId, isPinned: isPinned);

  // 8. Chat History API
  Future<ChatHistoryResult> getChatHistory(
    String sessionId, {
    int limit = 50,
    int? beforeId,
    int? limitQuestions,
  }) async {
    final effectiveLimit = limitQuestions ?? limit;
    if (await _isNativeMode()) {
      return await _db.getMessages(sessionId, limit: effectiveLimit, beforeId: beforeId);
    }
    final baseUrl = await _getBaseUrl();
    final query = [
      'session_id=$sessionId',
      'limit=$effectiveLimit',
      if (beforeId != null) 'before_id=$beforeId',
    ].join('&');

    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epChatHistory}?$query'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final rawMessages = (data['messages'] as List<dynamic>?) ?? [];
        final messages = rawMessages
            .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
            .toList();
        final hasMore = data['has_more'] == true;
        final oldestId = int.tryParse(data['oldest_id']?.toString() ?? '0') ?? 0;

        return ChatHistoryResult(
          messages: messages,
          hasMore: hasMore,
          oldestId: oldestId,
        );
      }
    } catch (_) {}

    return ChatHistoryResult(messages: [], hasMore: false, oldestId: 0);
  }

  Future<List<String>> getRecentUserQuestions(String sessionId, {int limit = 5}) async {
    if (await _isNativeMode()) {
      return await _db.getRecentUserQuestions(sessionId, limit: limit);
    }
    final history = await getChatHistory(sessionId, limit: 30);
    final questions = <String>[];
    for (final m in history.messages.reversed) {
      if (m.role == 'user') {
        final text = m.content.trim();
        if (text.isNotEmpty && !questions.contains(text)) {
          questions.add(text);
          if (questions.length >= limit) break;
        }
      }
    }
    return questions;
  }

  Future<bool> clearChatHistory(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.clearChat(sessionId);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatClear}'),
      headers: await _getHeaders(),
      body: jsonEncode({'session_id': sessionId}),
    );
    return res.statusCode == 200;
  }

  // 9. AI Agent Chat Stream
  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    List<String>? docFiles,
    String? targetServer,
    List<String>? targetServers,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();

    () async {
      if (await _isNativeMode()) {
        final sub = _ai.streamChatMessage(
          sessionId: sessionId,
          message: message,
          model: model,
          attachments: attachments,
          history: history,
          workingDir: workingDir,
          docFiles: docFiles,
          targetServer: targetServer,
          targetServers: targetServers,
          onToken: onToken,
          onStatus: onStatus,
          onTool: onTool,
          onDone: onDone,
          onError: onError,
        );
        controller.onCancel = () => sub.cancel();
        return;
      }

      http.Client? streamClient;
      StreamSubscription<String>? innerSub;
      // Cờ hủy từ UI (stopGenerating): phải đóng kết nối thật sự, không chỉ
      // hủy subscription bề mặt.
      bool streamCancelled = false;
      controller.onCancel = () {
        streamCancelled = true;
        innerSub?.cancel();
        streamClient?.close();
        unawaited(stopRemoteChat(sessionId));
      };
      try {
        final baseUrl = await _getBaseUrl();
        streamClient = http.Client();
        final request = http.Request('POST', Uri.parse('$baseUrl${ApiConstants.epChat}'));
        final headers = await _getHeaders();
        request.headers.addAll(headers);
        request.body = jsonEncode({
          'session_id': sessionId,
          'message': message,
          if (model != null && model.isNotEmpty) 'model': model,
          if (attachments != null && attachments.isNotEmpty)
            'attachments': attachments.map((e) {
              // Video/audio: khong nhung base64/noi dung nhi phan len server
              if (e.isMediaFile) {
                return e.copyWith(content: '').toJson();
              }
              return e.toJson();
            }).toList(),
          if (history != null) 'history': history,
          if (workingDir != null) 'working_dir': workingDir,
          if (docFiles != null && docFiles.isNotEmpty) 'doc_files': docFiles,
          if (targetServer != null && targetServer.isNotEmpty) 'target_server': targetServer,
          if (targetServers != null && targetServers.isNotEmpty) 'target_servers': targetServers,
        });

        // Chặn treo vĩnh viễn khi không thể kết nối/gửi request tới máy chủ
        final streamedResponse = await streamClient
            .send(request)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException(
                  'Không thể kết nối tới máy chủ AI (quá 30 giây).',
                  const Duration(seconds: 30)),
            );
        if (streamedResponse.statusCode != 200) {
          String errDetail = 'Server returned error: ${streamedResponse.statusCode}';
          try {
            final rawBody = await streamedResponse.stream.bytesToString();
            final decoded = jsonDecode(rawBody);
            if (decoded is Map) {
              final msg = (decoded['error'] ?? decoded['message'])?.toString().trim();
              if (msg != null && msg.isNotEmpty) {
                errDetail = msg;
              }
            }
          } catch (_) {}
          streamClient.close();
          onError(errDetail);
          return;
        }

        var accumulatedReply = '';
        bool finished = false;
        void completeOnce(String reply) {
          if (finished) return;
          finished = true;
          onDone(reply);
        }

        // Watchdog chống đứt kết nối ngầm: quá 90 giây không nhận thêm dữ liệu
        // SSE nào (dù chưa done) thì coi như luồng đã chết -> hoàn tất kèm cảnh
        // báo, hủy subscription và đóng client thay vì treo vô hạn.
        int lastSseActivityMs = DateTime.now().millisecondsSinceEpoch;
        final sseWatchdog = Timer.periodic(const Duration(seconds: 5), (t) {
          if (finished || streamCancelled) {
            t.cancel();
            return;
          }
          final elapsed = DateTime.now().millisecondsSinceEpoch - lastSseActivityMs;
          if (elapsed >= 90000) {
            t.cancel();
            final partial = accumulatedReply.trim();
            completeOnce(partial.isEmpty
                ? 'Máy chủ AI không gửi thêm dữ liệu nào trong 90 giây (kết nối có thể đã đứt ngầm). Hãy thử gửi lại yêu cầu.'
                : '$partial\n\n> **Cảnh báo:** Kết nối tới máy chủ AI bị gián đoạn (quá 90 giây không có dữ liệu). '
                    'Phần trả lời trên có thể chưa đầy đủ — hãy nhắn "tiếp tục" để chạy nốt.');
            innerSub?.cancel();
            streamClient?.close();
          }
        });

        innerSub = streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            lastSseActivityMs = DateTime.now().millisecondsSinceEpoch;
            if (streamCancelled) return;
            final trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final jsonStr = trimmed.substring(5).trim();
              if (jsonStr.isEmpty || jsonStr == '[DONE]') {
                // [DONE] chi la ket thuc mot luot stream - KHONG bao xong som,
                // phai doi su kien 'done' that su hoac stream dong hoan toan
                return;
              }
              try {
                final Map<String, dynamic> data = jsonDecode(jsonStr);
                final type = data['type']?.toString();

                if (type == 'token' || type == 'content') {
                  final delta = data['delta']?.toString() ?? data['content']?.toString() ?? '';
                  accumulatedReply += delta;
                  onToken(delta);
                } else if (type == 'status') {
                  final msg = data['message']?.toString() ?? '';
                  onStatus(msg);
                } else if (type == 'tool' || type == 'tool_call') {
                  final toolData = data['tool'] is Map ? data['tool'] as Map<String, dynamic> : data;
                  final item = ToolExecutionItem.fromJson(toolData);
                  onTool(item);
                } else if (type == 'done') {
                  final finalReply = data['reply']?.toString() ?? accumulatedReply;
                  completeOnce(finalReply);
                } else if (type == 'error') {
                  onError(data['message'] ?? data['error'] ?? 'AI Error');
                }
              } catch (_) {}
            }
          },
          onError: (e) {
            sseWatchdog.cancel();
            streamClient?.close();
            if (streamCancelled || finished) return;
            onError(e);
          },
          onDone: () {
            sseWatchdog.cancel();
            if (streamCancelled) return;
            completeOnce(accumulatedReply);
            streamClient?.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        if (!streamCancelled) {
          onError(e);
        }
        streamClient?.close();
      }
    }();

    return controller.stream.listen((_) {});
  }

  // 10. File System Browser APIs (Local Filesystem, SSH Remote, hoặc App Chính từ xa)
  Future<List<String>> listDirectories({String prefix = ''}) async {
    if (!await _isNativeMode()) {
      try {
        final baseUrl = await _getBaseUrl();
        final res = await _client.get(
          Uri.parse('$baseUrl${ApiConstants.epFsListDirs}?prefix=${Uri.encodeComponent(prefix)}'),
          headers: await _getHeaders(),
        ).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data is Map && data['directories'] is List) {
            return (data['directories'] as List).map((e) => e.toString()).toList();
          }
          if (data is List) {
            return data.map((e) => e.toString()).toList();
          }
        }
      } catch (_) {}
      return [];
    }
    try {
      final cfg = await _localConfig.loadConfig();
      final serverIp = cfg['server_ip']?.toString() ?? '127.0.0.1';
      final isRemote = serverIp.isNotEmpty && serverIp != '127.0.0.1' && serverIp != 'localhost';

      if (isRemote) {
        return await _ssh.listRemoteDirs(prefix);
      }

      String searchPath = prefix.trim();
      final homeDir = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '/';

      if (searchPath.isEmpty) {
        searchPath = homeDir;
      } else if (searchPath.startsWith('~')) {
        searchPath = searchPath.replaceFirst('~', homeDir);
      }

      Directory targetDir;
      String filter = '';

      final checkDir = Directory(searchPath);
      if (checkDir.existsSync()) {
        targetDir = checkDir;
      } else {
        final parent = File(searchPath).parent;
        if (parent.existsSync()) {
          targetDir = parent;
          filter = searchPath.split(Platform.pathSeparator).last.toLowerCase();
        } else {
          targetDir = Directory(homeDir);
        }
      }

      final results = <String>[];
      final entities = targetDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is Directory) {
          final dirName = entity.path.split(Platform.pathSeparator).last;
          if (dirName.startsWith('.') && !filter.startsWith('.')) continue;
          if (filter.isEmpty ||
              dirName.toLowerCase().contains(filter) ||
              entity.path.toLowerCase().contains(filter)) {
            results.add(entity.path);
          }
        }
      }
      results.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return results.take(35).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> listRemoteDirectories({String prefix = ''}) =>
      listDirectories(prefix: prefix);

  Future<Map<String, dynamic>> uploadFile({
    required String fileName,
    required Uint8List bytes,
    String? targetDir,
    ServerModel? server,
    void Function(int sentBytes, int totalBytes, double progress)? onProgress,
  }) async {
    // 0. Nếu đang ở chế độ App Phụ -> gửi tệp trực tiếp lên máy App Chính
    if (!await _isNativeMode()) {
      final baseUrl = await _getBaseUrl();
      try {
        final res = await _client.post(
          Uri.parse('$baseUrl${ApiConstants.epFsUpload}'),
          headers: await _getHeaders(),
          body: jsonEncode({
            'file_name': fileName,
            'content_base64': base64Encode(bytes),
            if (targetDir != null && targetDir.isNotEmpty) 'target_dir': targetDir,
          }),
        ).timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (onProgress != null) onProgress(bytes.length, bytes.length, 1.0);
          return data is Map<String, dynamic> ? data : {'status': 'success'};
        }
        return {'status': 'error', 'message': 'HTTP ${res.statusCode}'};
      } catch (e) {
        return {'status': 'error', 'message': e.toString()};
      }
    }

    final isLocal = server == null ||
        server.name == 'Local Machine' ||
        server.name == 'Local' ||
        server.name == 'localhost' ||
        server.serverIp == '127.0.0.1';

    // 1. If on Local Machine, save directly to local disk without SSH
    if (isLocal) {
      try {
        final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\.\-\_]'), '_');
        String destDir = targetDir ?? Directory.current.path;
        if (!Directory(destDir).existsSync()) {
          destDir = Directory.current.path;
        }
        final uploadDir = Directory('$destDir/uploads');
        if (!uploadDir.existsSync()) {
          uploadDir.createSync(recursive: true);
        }
        final destFile = File('${uploadDir.path}/$cleanFileName');
        await destFile.writeAsBytes(bytes);
        if (onProgress != null) onProgress(bytes.length, bytes.length, 1.0);
        return {
          'status': 'success',
          'remote_path': destFile.path,
          'local_path': destFile.path,
          'size': bytes.length,
          'name': fileName,
        };
      } catch (e) {
        return {'status': 'error', 'message': 'Lỗi lưu tệp cục bộ: $e'};
      }
    }

    // 2. If Remote VPS in Native SSH Mode
    return await _ssh.uploadFile(
      fileName: fileName,
      bytes: bytes,
      targetDir: targetDir,
      server: server,
      onProgress: onProgress,
    );
  }

  Future<Uint8List?> downloadFile({
    required String remotePath,
    void Function(int receivedBytes, int totalBytes, double progress)? onProgress,
  }) async {
    if (await _isNativeMode()) {
      return await _ssh.downloadFile(
        remotePath: remotePath,
        onProgress: onProgress,
      );
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epFsDownload}?path=${Uri.encodeComponent(remotePath)}'),
        headers: await _getHeaders(),
      );
      if (res.statusCode == 200) {
        if (onProgress != null) onProgress(res.bodyBytes.length, res.bodyBytes.length, 1.0);
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
