// ignore_for_file: use_null_aware_elements
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../models/server_model.dart';
import '../../models/metrics_model.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final StorageService _storage = StorageService();
  final http.Client _client = http.Client();

  Future<Map<String, String>> _getHeaders({bool isJson = true}) async {
    final token = await _storage.getSecretToken();
    final headers = <String, String>{
      if (isJson) 'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-Secret-Token'] = token;
    }
    return headers;
  }

  Future<String> _getBaseUrl() async {
    return await _storage.getGatewayUrl();
  }

  // 1. Connectivity & Ping Check
  Future<bool> checkHealth() async {
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epConfig}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 2. Config APIs
  Future<Map<String, dynamic>> getConfig() async {
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
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epConfig}'),
      headers: await _getHeaders(),
      body: jsonEncode(config),
    );
    return res.statusCode == 200;
  }

  // 3. Servers Management APIs
  Future<List<ServerModel>> getServers() async {
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

  Future<bool> selectServer(String serverIp) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersSelect}'),
      headers: await _getHeaders(),
      body: jsonEncode({'server_ip': serverIp}),
    );
    return res.statusCode == 200;
  }

  Future<bool> updateServer(ServerModel server) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersUpdate}'),
      headers: await _getHeaders(),
      body: jsonEncode(server.toJson()),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteServer(String serverIp) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersDelete}'),
      headers: await _getHeaders(),
      body: jsonEncode({'server_ip': serverIp}),
    );
    return res.statusCode == 200;
  }

  // 4. System Metrics & Info
  Future<SystemMetricsModel> getSystemMetrics() async {
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

  Future<Map<String, dynamic>> executeServiceAction(String service, String action) async {
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

  // 5. Service Logs API: GET /api/server/logs?lines=100
  Future<String> getServerLogs({int lines = 100}) async {
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epServerLogs}?lines=$lines'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return data['logs']?.toString() ?? 'Không có nhật ký.';
      }
    } catch (e) {
      return 'Lỗi kết nối nhật ký: $e';
    }
    return 'Không thể tải nhật ký.';
  }

  // 6. 1-Click Deploy SSE Stream: POST /api/server/deploy
  StreamSubscription<String> streamDeploy({
    required void Function(String step) onStep,
    required void Function() onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();

    () async {
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

  Future<ChatSessionModel> createChatSession({String title = 'Cuộc hội thoại mới'}) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
      headers: await _getHeaders(),
      body: jsonEncode({'title': title}),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map<String, dynamic> && data['session'] is Map) {
        return ChatSessionModel.fromJson(data['session'] as Map<String, dynamic>);
      }
      if (data is Map<String, dynamic>) {
        return ChatSessionModel.fromJson(data);
      }
    }
    return ChatSessionModel(id: 'sess_${DateTime.now().millisecondsSinceEpoch}', title: title);
  }

  Future<bool> deleteChatSession(String sessionId) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.delete(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId'),
      headers: await _getHeaders(),
    );
    return res.statusCode == 200;
  }

  Future<bool> renameChatSession(String sessionId, String newTitle) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.put(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId'),
      headers: await _getHeaders(),
      body: jsonEncode({'title': newTitle}),
    );
    return res.statusCode == 200;
  }

  Future<bool> pinChatSession(String sessionId, bool isPinned) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId/pin'),
      headers: await _getHeaders(),
      body: jsonEncode({'is_pinned': isPinned}),
    );
    return res.statusCode == 200;
  }

  Future<List<ChatMessageModel>> getChatHistory(String sessionId) async {
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epChatHistory}?session_id=$sessionId'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
        } else if (data is Map<String, dynamic> && data['messages'] is List) {
          final list = data['messages'] as List;
          return list.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> clearChatHistory(String sessionId) async {
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatClear}'),
      headers: await _getHeaders(),
      body: jsonEncode({'session_id': sessionId}),
    );
    return res.statusCode == 200;
  }

  // 8. AI Chat SSE Stream Request
  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();

    () async {
      http.Client? streamClient;
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
          if (history != null) 'history': history,
          if (workingDir != null) 'working_dir': workingDir,
        });

        final streamedResponse = await streamClient.send(request);
        if (streamedResponse.statusCode != 200) {
          onError('Server returned error: ${streamedResponse.statusCode}');
          return;
        }

        var accumulatedReply = '';

        streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final jsonStr = trimmed.substring(5).trim();
              if (jsonStr.isEmpty || jsonStr == '[DONE]') {
                onDone(accumulatedReply);
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
                  onDone(finalReply);
                } else if (type == 'error') {
                  onError(data['message'] ?? data['error'] ?? 'AI Error');
                }
              } catch (e) {
                // If not JSON, ignore
              }
            }
          },
          onError: (e) {
            onError(e);
          },
          onDone: () {
            onDone(accumulatedReply);
            streamClient?.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        onError(e);
        streamClient?.close();
      }
    }();

    return controller.stream.listen((_) {});
  }

  // 9. SSH Remote Directories & Files
  Future<List<String>> listRemoteDirectories({String prefix = '/'}) async {
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epFsListDirs}?prefix=${Uri.encodeComponent(prefix)}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['directories'] is List) {
          return (data['directories'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}
    return ['/var/www', '/etc/nginx', '/opt/ai_agent', '/home', '/var/log', '/etc', '/opt'];
  }
}
