import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tadu_cloud_ai_agent_mobile/core/constants/api_constants.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/api_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/cli_scanner_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/database_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/local_config_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/native_ai_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/primary_host_server_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/remote_file_download_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/remote_tunnel_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/storage_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/attachment_item.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/chat_message.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/chat_session.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/remote_fs_entry.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/server_model.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/chat_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/gateway_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/server_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/terminal_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/screens/chat/widgets/remote_files_browser_dialog.dart';
import 'package:tadu_cloud_ai_agent_mobile/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _PassthroughHttpOverrides extends HttpOverrides {}

class _FakeNativePrimaryApiService implements ApiService {
  final DatabaseService db;
  final NativeAiService ai;

  _FakeNativePrimaryApiService({required this.db, required this.ai});

  @override
  Future<bool> isNativeMode() async => true;

  @override
  Future<List<ChatSessionModel>> getChatSessions() => db.getSessions();

  @override
  Future<ChatHistoryResult> getChatHistory(
    String sessionId, {
    int limit = 50,
    int? beforeId,
    int? limitQuestions,
  }) =>
      db.getMessages(sessionId, limit: limitQuestions ?? limit, beforeId: beforeId);

  @override
  Future<void> stopRemoteChat(String sessionId) async {}

  @override
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
    void Function(String reason)? onDisconnected,
    bool stopRemoteOnCancel = false,
  }) {
    return ai.streamChatMessage(
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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalConfigService implements LocalConfigService {
  Map<String, dynamic> _cfg = {
    'server_ip': '127.0.0.1',
    'ai_model': 'glm-5.3',
    'active_agent_engine': 'antigravity-cli',
    'ai_provider_tab': 'proxy',
    'proxy_base_url': 'https://openrouter.ai/api/v1',
    'proxy_api_key': '',
    'servers': <Map<String, dynamic>>[],
  };
  final List<ServerModel> _servers = [
    ServerModel(
      id: 'local',
      name: 'Local Machine',
      serverIp: '127.0.0.1',
      sshUser: 'yenai',
      sshPort: 22,
      isSelected: true,
    ),
  ];

  @override
  Future<Map<String, dynamic>> loadConfig() async => Map<String, dynamic>.from(_cfg);

  @override
  Future<bool> saveConfig(Map<String, dynamic> updates) async {
    _cfg = {..._cfg, ...updates};
    return true;
  }

  @override
  Future<List<ServerModel>> getServers() async => List<ServerModel>.from(_servers);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCliScannerService implements CliScannerService {
  @override
  Future<List<LocalCliAgent>> scanInstalledAgents({bool forceRefresh = false}) async {
    return const [
      LocalCliAgent(
        id: 'antigravity-cli',
        binary: 'agy',
        path: '/usr/local/bin/agy',
        label: 'Google Antigravity CLI',
        version: '2.0.0',
      ),
      LocalCliAgent(
        id: 'claude-cli',
        binary: 'claude',
        path: '/usr/local/bin/claude',
        label: 'Anthropic Claude Code CLI',
        version: '1.0.0',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNativeAiService implements NativeAiService {
  final DatabaseService db;
  String? lastReceivedMessage;
  String? lastReceivedModel;
  String? lastReceivedWorkingDir;
  int callCount = 0;
  Completer<void>? holdBeforeDone;

  _FakeNativeAiService(this.db);

  @override
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
    callCount++;
    lastReceivedMessage = message;
    lastReceivedModel = model;
    lastReceivedWorkingDir = workingDir;

    bool cancelled = false;
    final controller = StreamController<String>();
    controller.onCancel = () {
      cancelled = true;
    };
    () async {
      await db.insertMessage(
        ChatMessageModel(sessionId: sessionId, role: 'user', content: message),
      );
      if (cancelled) return;
      onStatus('Đang thực thi trên máy App Chính...');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (cancelled) return;
      onTool(
        ToolExecutionItem(
          tool: 'run_command',
          command: 'pwd',
          output: workingDir ?? '/tmp',
        ),
      );
      onToken('Kết quả từ ');
      if (holdBeforeDone != null && !holdBeforeDone!.isCompleted) {
        await holdBeforeDone!.future;
      }
      if (cancelled) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (cancelled) return;
      onToken('App Chính: $message');
      final fullReply = 'Kết quả từ App Chính: $message';
      await db.insertMessage(
        ChatMessageModel(
          sessionId: sessionId,
          role: 'assistant',
          content: fullReply,
          model: model ?? 'antigravity-cli',
        ),
      );
      if (cancelled) return;
      onDone(fullReply);
    }();
    return controller.stream.listen((_) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('StorageService.parsePairingString', () {
    test('tách chính xác URL và token từ các định dạng chuỗi ghép nối', () {
      final a = StorageService.parsePairingString('http://192.168.1.10:8765#secret_abc123');
      expect(a.url, 'http://192.168.1.10:8765');
      expect(a.token, 'secret_abc123');

      final b = StorageService.parsePairingString('aitype://10.0.0.5:9000/#tok_999');
      expect(b.url, 'http://10.0.0.5:9000');
      expect(b.token, 'tok_999');

      final c = StorageService.parsePairingString('192.168.1.20:8765#tok_bare');
      expect(c.url, 'http://192.168.1.20:8765');
      expect(c.token, 'tok_bare');

      final d = StorageService.parsePairingString('https://host.local:8765/?token=query_tok');
      expect(d.url, 'https://host.local:8765');
      expect(d.token, 'query_tok');

      final e = StorageService.parsePairingString('   ');
      expect(e.url, '');
      expect(e.token, '');
      expect(e.fallbackUrls, isEmpty);

      final f = StorageService.parsePairingString(
        'http://100.68.203.77:8765#tok_vpn&lan=http%3A%2F%2F192.168.1.78%3A8765',
      );
      expect(f.url, 'http://100.68.203.77:8765');
      expect(f.token, 'tok_vpn');
      expect(f.fallbackUrls, ['http://192.168.1.78:8765']);
    });
  });

  group('PrimaryHostServerService <-> Secondary ApiService E2E', () {
    late Directory tempDir;
    late DatabaseService primaryDb;
    late _FakeLocalConfigService fakeConfig;
    late _FakeCliScannerService fakeCli;
    late _FakeNativeAiService fakeAi;
    late PrimaryHostServerService primaryHost;
    late String pairingToken;
    late String baseUrl;
    final List<String> mutations = [];
    late StreamSubscription<String> mutationSub;
    HttpOverrides? previousHttpOverrides;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();
    });

    setUp(() async {
      previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('agent_coder_remote_test_');
      final dbPath = p.join(tempDir.path, 'primary_chat.db');
      primaryDb = DatabaseService.forTest(dbPath);
      await primaryDb.init();

      fakeConfig = _FakeLocalConfigService();
      fakeCli = _FakeCliScannerService();
      fakeAi = _FakeNativeAiService(primaryDb);
      primaryHost = PrimaryHostServerService.forTest(
        databaseService: primaryDb,
        localConfigService: fakeConfig,
        nativeAiService: fakeAi,
        cliScannerService: fakeCli,
      );

      mutations.clear();
      mutationSub = primaryHost.onRemoteMutation.listen(mutations.add);

      pairingToken = 'test_pairing_token_64bit_secure';
      final started = await primaryHost.start(
        port: 0,
        token: pairingToken,
        deviceName: 'Ubuntu Workstation Primary',
        bindAddress: InternetAddress.loopbackIPv4,
      );
      expect(started, isTrue);
      expect(primaryHost.isRunning, isTrue);
      expect(primaryHost.boundPort, greaterThan(0));
      baseUrl = 'http://127.0.0.1:${primaryHost.boundPort}';

      // Cấu hình thiết bị client ở chế độ App Phụ trỏ tới App Chính loopback
      final storage = StorageService();
      await storage.setAppRole(AppRole.secondary);
      await storage.setGatewayUrl(baseUrl);
      await storage.setSecretToken(pairingToken);
    });

    tearDown(() async {
      await mutationSub.cancel();
      await primaryHost.stop();
      await primaryDb.close();
      await StorageService().setAppRole(AppRole.primary);
      await StorageService().setGatewayUrl('');
      await StorageService().setSecretToken('');
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      HttpOverrides.global = previousHttpOverrides;
    });

    test('chặn request thiếu hoặc sai token bằng HTTP 401 và cho phép token hợp lệ', () async {
      final client = http.Client();
      try {
        final noAuthRes = await client.get(Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'));
        expect(noAuthRes.statusCode, 401);

        final badAuthRes = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: {'Authorization': 'Bearer wrong_token'},
        );
        expect(badAuthRes.statusCode, 401);

        final goodRes = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: {'Authorization': 'Bearer $pairingToken'},
        );
        expect(goodRes.statusCode, 200);
        final decoded = jsonDecode(utf8.decode(goodRes.bodyBytes)) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['role'], 'primary');
        expect(decoded['device_name'], 'Ubuntu Workstation Primary');
        expect(decoded['app_version'], '1.5.10');
        expect(decoded['cli_agents_count'], 2);
      } finally {
        client.close();
      }
    });

    test('App Phụ điều khiển toàn bộ Chat Sessions, SSE Chat Stream, Work Schedule và File System trên App Chính', () async {
      final api = ApiService();
      expect(await api.isNativeMode(), isFalse);

      // 1. Handshake & CLI agents
      final info = await api.getRemoteHostInfo();
      expect(info, isNotNull);
      expect(info!['device_name'], 'Ubuntu Workstation Primary');
      expect(info['app_version'], '1.5.10');

      final agents = await api.getRemoteCliAgents();
      expect(agents.length, 2);
      expect(agents.map((a) => a.id), containsAll(['antigravity-cli', 'claude-cli']));

      // 2. Chat session CRUD trên SQLite của App Chính
      final created = await api.createChatSession(title: 'Dự án điều khiển từ xa');
      final sid = created.id;

      expect(await api.renameChatSession(sid, 'Dự án đã đổi tên'), isTrue);
      expect(await api.togglePinSession(sid, isPinned: true), isTrue);
      expect(
        await api.updateChatSessionScope(
          sid,
          tempDir.path,
          docFiles: const ['README.md', 'docs/plan.md'],
        ),
        isTrue,
      );
      expect(
        await api.updateChatSessionServer(
          sid,
          'vps-prod',
          targetServers: const ['vps-prod', 'vps-staging'],
        ),
        isTrue,
      );

      final sessions = await api.getChatSessions();
      final matched = sessions.firstWhere((s) => s.id == sid);
      expect(matched.title, 'Dự án đã đổi tên');
      expect(matched.isPinned, isTrue);
      expect(matched.workingDirScope, tempDir.path);
      expect(matched.docFiles, ['README.md', 'docs/plan.md']);
      expect(matched.targetServers, ['vps-prod', 'vps-staging']);

      // 3. Live SSE Chat Stream từ App Phụ -> chạy AI trên App Chính
      final tokens = <String>[];
      final statuses = <String>[];
      final tools = <ToolExecutionItem>[];
      final doneCompleter = Completer<String>();

      final sub = api.streamChatMessage(
        sessionId: sid,
        message: 'Kiểm tra trạng thái hệ thống',
        model: 'antigravity-cli',
        workingDir: tempDir.path,
        onToken: tokens.add,
        onStatus: statuses.add,
        onTool: tools.add,
        onDone: (reply) {
          if (!doneCompleter.isCompleted) doneCompleter.complete(reply);
        },
        onError: (err) {
          if (!doneCompleter.isCompleted) doneCompleter.completeError(err);
        },
      );

      final finalReply = await doneCompleter.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      expect(finalReply, 'Kết quả từ App Chính: Kiểm tra trạng thái hệ thống');
      expect(tokens.join(), 'Kết quả từ App Chính: Kiểm tra trạng thái hệ thống');
      expect(statuses, contains('Đang thực thi trên máy App Chính...'));
      expect(tools.length, 1);
      expect(tools.first.tool, 'run_command');
      expect(fakeAi.lastReceivedWorkingDir, tempDir.path);

      // Xác minh lịch sử hội thoại đã được lưu trực tiếp trong SQLite của App Chính
      final history = await api.getChatHistory(sid);
      expect(history.messages.length, 2);
      expect(history.messages.first.role, 'user');
      expect(history.messages.last.content, 'Kết quả từ App Chính: Kiểm tra trạng thái hệ thống');

      // 4. Work Schedules CRUD từ xa
      final savedSchedule = await api.saveWorkSchedule(
        sessionId: sid,
        projectName: 'Remote Sync App',
        summary: 'Đồng bộ công việc từ điện thoại',
        docFiles: const ['spec.md'],
        tasks: [
          {
            'id': 'T-01',
            'title': 'Kiểm tra build Linux',
            'description': 'Chạy build_deb.sh',
            'start_date': '2026-11-26',
            'end_date': '2026-11-26',
            'priority': 'high',
            'phase': 'Release',
            'done': false,
          },
          {
            'id': 'T-02',
            'title': 'Cài APK lên điện thoại',
            'description': 'Chạy adb install -r',
            'start_date': '2026-11-26',
            'end_date': '2026-11-27',
            'priority': 'medium',
            'phase': 'Mobile',
            'done': false,
          },
        ],
      );
      expect(savedSchedule, isTrue);
      expect(await api.getPendingWorkScheduleCount(sid), 2);

      final schedule = await api.getWorkSchedule(sid);
      expect(schedule, isNotNull);
      expect(schedule!['project_name'], 'Remote Sync App');
      expect((schedule['tasks'] as List).length, 2);

      expect(await api.markWorkScheduleTasksDone(sid, const ['T-01'], done: true), isTrue);
      expect(await api.getPendingWorkScheduleCount(sid), 1);

      expect(await api.deleteWorkSchedule(sid), isTrue);
      expect(await api.getWorkSchedule(sid), isNull);

      // 5. Duyệt thư mục Scope & Upload/Download tệp lên máy App Chính
      final subDir = Directory(p.join(tempDir.path, 'sub_project'))..createSync();
      final dirs = await api.listDirectories(prefix: tempDir.path);
      expect(dirs, contains(subDir.path));

      final payloadBytes = Uint8List.fromList(utf8.encode('hello from secondary phone'));
      final uploadRes = await api.uploadFile(
        fileName: 'note.txt',
        bytes: payloadBytes,
        targetDir: tempDir.path,
      );
      expect(uploadRes['status'], 'success');
      final remotePath = uploadRes['remote_path']?.toString() ?? '';
      expect(remotePath, isNotEmpty);
      expect(File(remotePath).existsSync(), isTrue);

      final downloaded = await api.downloadFile(remotePath: remotePath);
      expect(downloaded, isNotNull);
      expect(utf8.decode(downloaded!), 'hello from secondary phone');

      // 6. Xác minh App Chính đã nhận được sự kiện onRemoteMutation để tự làm mới UI
      expect(mutations, contains('sessions'));
      expect(mutations, contains('schedule:$sid'));

      // 7. Xóa lịch sử & xóa phiên từ App Phụ
      expect(await api.clearChatHistory(sid), isTrue);
      expect((await api.getChatHistory(sid)).messages, isEmpty);
      expect(await api.deleteChatSession(sid), isTrue);
    });

    test('luồng ghép nối 1 chạm (POST /api/pair/request -> duyệt trên PC -> cấp token đúng 1 lần)', () async {
      final incoming = <PendingPairingRequest>[];
      final pairSub = primaryHost.onPairingRequest.listen(incoming.add);
      final client = http.Client();
      try {
        primaryHost.updateRuntimeMetadata(publicUrl: 'https://coder-pc.example.com');

        // 1. Gửi yêu cầu ghép nối không cần token sẵn
        final reqRes = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epPairRequest}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_name': 'Xiaomi 10T Pro', 'os': 'android'}),
        );
        expect(reqRes.statusCode, 200);
        final reqBody = jsonDecode(utf8.decode(reqRes.bodyBytes)) as Map<String, dynamic>;
        final reqId = reqBody['request_id'] as String;
        final pin = reqBody['pin'] as String;
        expect(reqId, isNotEmpty);
        expect(pin.length, 6);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(incoming.length, 1);
        expect(incoming.first.clientDeviceName, 'Xiaomi 10T Pro');
        expect(incoming.first.pin, pin);

        // 2. Trước khi PC duyệt -> status phải là pending (tuyệt đối không lộ token)
        final pendingRes = await client.get(Uri.parse('$baseUrl${ApiConstants.epPairStatus}?id=$reqId'));
        final pendingBody = jsonDecode(utf8.decode(pendingRes.bodyBytes)) as Map<String, dynamic>;
        expect(pendingBody['status'], 'pending');
        expect(pendingBody.containsKey('token'), isFalse);

        // 3. Người dùng bấm Chấp nhận trên PC -> status trả về approved kèm token và preferred_url
        primaryHost.approvePairingRequest(reqId);
        final approvedRes = await client.get(Uri.parse('$baseUrl${ApiConstants.epPairStatus}?id=$reqId'));
        final approvedBody = jsonDecode(utf8.decode(approvedRes.bodyBytes)) as Map<String, dynamic>;
        expect(approvedBody['status'], 'approved');
        expect(approvedBody['token'], pairingToken);
        expect(approvedBody['preferred_url'], 'https://coder-pc.example.com');

        // 4. Gọi lại lần 2 -> phải expired (cấp token đúng 1 lần duy nhất)
        final replayRes = await client.get(Uri.parse('$baseUrl${ApiConstants.epPairStatus}?id=$reqId'));
        final replayBody = jsonDecode(utf8.decode(replayRes.bodyBytes)) as Map<String, dynamic>;
        expect(replayBody['status'], 'expired');

        // 5. Kiểm tra luồng Từ chối
        final req2Res = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epPairRequest}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_name': 'Unknown Phone', 'os': 'ios'}),
        );
        final req2Id = (jsonDecode(utf8.decode(req2Res.bodyBytes)) as Map)['request_id'] as String;
        primaryHost.rejectPairingRequest(req2Id);
        final rejRes = await client.get(Uri.parse('$baseUrl${ApiConstants.epPairStatus}?id=$req2Id'));
        expect((jsonDecode(utf8.decode(rejRes.bodyBytes)) as Map)['status'], 'rejected');
      } finally {
        await pairSub.cancel();
        client.close();
      }
    });

    test('đồng bộ loading thời gian thực sang App Chính khi App Phụ đang hỏi Agent và chặn gửi trùng cùng hộp hội thoại', () async {
      final api = ApiService();
      final created = await api.createChatSession(title: 'Hộp hội thoại đồng bộ');
      final sid = created.id;

      // Khởi tạo ChatProvider đại diện cho UI App Chính gắn trực tiếp vào primaryHost
      final primaryChat = ChatProvider(
        apiService: api,
        hostServer: primaryHost,
        autoInit: false,
      );
      await primaryChat.loadSessions(silent: true);
      final sessionOnPrimary = primaryChat.sessions.firstWhere((s) => s.id == sid);
      await primaryChat.selectSession(sessionOnPrimary);
      expect(primaryChat.isGenerating, isFalse);
      expect(primaryChat.isRemoteGenerating, isFalse);

      // Giữ luồng AI ở trạng thái đang xử lý để kiểm chứng trạng thái live giữa chừng
      final hold = Completer<void>();
      fakeAi.holdBeforeDone = hold;
      fakeAi.callCount = 0;

      final doneCompleter = Completer<String>();
      final sub = api.streamChatMessage(
        sessionId: sid,
        message: 'Câu hỏi từ App Phụ',
        model: 'antigravity-cli',
        onToken: (_) {},
        onStatus: (_) {},
        onTool: (_) {},
        onDone: (reply) {
          if (!doneCompleter.isCompleted) doneCompleter.complete(reply);
        },
        onError: (err) {
          if (!doneCompleter.isCompleted) doneCompleter.completeError(err);
        },
      );

      // Chờ sự kiện start & token đầu tiên lan sang App Chính
      for (var i = 0; i < 40 && !primaryChat.isSessionRemoteGenerating(sid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // 1. App Chính phải thấy ngay trạng thái loading + tin nhắn từ App Phụ
      expect(primaryChat.isSessionGenerating(sid), isTrue);
      expect(primaryChat.isSessionRemoteGenerating(sid), isTrue);
      expect(primaryChat.isGenerating, isTrue);
      expect(primaryChat.isRemoteGenerating, isTrue);
      expect(primaryChat.messages.any((m) => m.role == 'user' && m.content == 'Câu hỏi từ App Phụ'), isTrue);
      expect(primaryChat.messages.any((m) => m.role == 'assistant' && m.isStreaming), isTrue);

      // 2. Thử gửi trùng từ App Chính cùng hộp hội thoại -> phải bị chặn hoàn toàn
      final msgCountBefore = primaryChat.messages.length;
      await primaryChat.sendMessage('Câu hỏi gửi đè từ App Chính');
      expect(primaryChat.messages.length, msgCountBefore);
      expect(fakeAi.callCount, 1);

      // 3. Thử gửi trùng từ HTTP POST /api/chat thứ hai cùng phiên -> phải trả HTTP 409 Conflict
      final conflictClient = http.Client();
      try {
        final conflictRes = await conflictClient.post(
          Uri.parse('$baseUrl${ApiConstants.epChat}'),
          headers: {
            'Authorization': 'Bearer $pairingToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'session_id': sid, 'message': 'Gửi đè từ máy phụ khác'}),
        );
        expect(conflictRes.statusCode, 409);
      } finally {
        conflictClient.close();
      }

      // 4. Mở khóa để Agent trả lời xong -> App Chính tự kết thúc loading và hiển thị đầy đủ câu trả lời
      hold.complete();
      final finalReply = await doneCompleter.future.timeout(const Duration(seconds: 5));
      expect(finalReply, 'Kết quả từ App Chính: Câu hỏi từ App Phụ');
      await sub.cancel();

      for (var i = 0; i < 40 && primaryChat.isSessionGenerating(sid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(primaryChat.isSessionGenerating(sid), isFalse);
      expect(primaryChat.isSessionRemoteGenerating(sid), isFalse);
      expect(primaryChat.messages.any((m) => m.role == 'assistant' && m.content == finalReply && !m.isStreaming), isTrue);

      // 5. Kiểm tra nút Dừng trên App Chính có thể dừng luôn luồng App Phụ đang chạy
      final holdStop = Completer<void>();
      fakeAi.holdBeforeDone = holdStop;
      final stopDone = Completer<String>();
      final stopSub = api.streamChatMessage(
        sessionId: sid,
        message: 'Tác vụ cần dừng từ App Chính',
        model: 'antigravity-cli',
        onToken: (_) {},
        onStatus: (_) {},
        onTool: (_) {},
        onDone: (reply) {
          if (!stopDone.isCompleted) stopDone.complete(reply);
        },
        onError: (err) {
          if (!stopDone.isCompleted) stopDone.complete('ERR:$err');
        },
      );

      for (var i = 0; i < 40 && !primaryChat.isSessionRemoteGenerating(sid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(primaryChat.isRemoteGenerating, isTrue);

      primaryChat.stopGenerating();
      final stopMsg = await stopDone.future.timeout(const Duration(seconds: 5));
      expect(stopMsg, contains('App Chính'));
      expect(primaryChat.isGenerating, isFalse);
      expect(primaryHost.isRemoteSessionGenerating(sid), isFalse);

      if (!holdStop.isCompleted) holdStop.complete();
      fakeAi.holdBeforeDone = null;
      await stopSub.cancel();
      primaryChat.dispose();
    });

    test('theo dõi nhiều thiết bị App Phụ, ngắt kết nối từng máy không ảnh hưởng máy khác và cho phép lại', () async {
      final client = http.Client();
      final revokedEvents = <String>[];
      final revokedSub = ApiService.onDeviceRevoked.listen(revokedEvents.add);
      try {
        Map<String, String> headersFor(String id, String name, String os) => {
              'Authorization': 'Bearer $pairingToken',
              'Content-Type': 'application/json',
              'X-Client-Id': id,
              'X-Client-Name': Uri.encodeComponent(name),
              'X-Client-OS': os,
            };

        // 1. Hai thiết bị App Phụ riêng biệt kết nối bằng cùng một Pairing Token
        final resA = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_xiaomi_a', 'Điện thoại Xiaomi', 'android'),
        );
        expect(resA.statusCode, 200);

        final resB = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_macbook_b', 'MacBook Phụ', 'macos'),
        );
        expect(resB.statusCode, 200);
        final decodedB = jsonDecode(utf8.decode(resB.bodyBytes)) as Map<String, dynamic>;
        expect(decodedB['online_clients_count'], 2);

        expect(primaryHost.onlineClientCount, 2);
        expect(primaryHost.connectedClients.length, 2);
        final snapA = primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_xiaomi_a');
        final snapB = primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_macbook_b');
        expect(snapA.deviceName, 'Điện thoại Xiaomi');
        expect(snapA.os, 'android');
        expect(snapA.isOnline, isTrue);
        expect(snapB.deviceName, 'MacBook Phụ');
        expect(snapB.os, 'macos');
        expect(snapB.isOnline, isTrue);

        // 2. Thiết bị A bắt đầu một phiên chat đang chạy -> activeChats == 1
        await StorageService().setClientDeviceId('dev_xiaomi_a');
        final api = ApiService();
        final created = await api.createChatSession(title: 'Phiên test kick client A');
        final sid = created.id;

        final hold = Completer<void>();
        fakeAi.holdBeforeDone = hold;
        final streamDone = Completer<String>();
        final chatSub = api.streamChatMessage(
          sessionId: sid,
          message: 'Đang chạy từ máy A',
          model: 'antigravity-cli',
          onToken: (_) {},
          onStatus: (_) {},
          onTool: (_) {},
          onDone: (r) {
            if (!streamDone.isCompleted) streamDone.complete('DONE:$r');
          },
          onError: (e) {
            if (!streamDone.isCompleted) streamDone.complete('ERR:$e');
          },
        );

        for (var i = 0; i < 40 && !primaryHost.isRemoteSessionGenerating(sid); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(primaryHost.isRemoteSessionGenerating(sid), isTrue);
        expect(
          primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_xiaomi_a').activeChats,
          1,
        );

        // 3. App Chính ngắt kết nối riêng thiết bị A -> hủy luồng chat của A, chặn A bằng 401 DEVICE_REVOKED, nhưng máy B vẫn chạy bình thường
        await primaryHost.disconnectClient('dev_xiaomi_a', revoke: true);
        final endState = await streamDone.future.timeout(const Duration(seconds: 5));
        expect(endState, contains('ngắt kết nối'));
        expect(primaryHost.isRemoteSessionGenerating(sid), isFalse);
        expect(primaryHost.onlineClientCount, 1);
        expect(primaryHost.revokedClientIds, contains('dev_xiaomi_a'));
        expect(
          primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_xiaomi_a').isRevoked,
          isTrue,
        );

        if (!hold.isCompleted) hold.complete();
        fakeAi.holdBeforeDone = null;
        await chatSub.cancel();

        // Thiết bị A gọi lại -> bị chặn 401 DEVICE_REVOKED và ApiService phát sự kiện onDeviceRevoked
        final blockedA = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_xiaomi_a', 'Điện thoại Xiaomi', 'android'),
        );
        expect(blockedA.statusCode, 401);
        final blockedBody = jsonDecode(utf8.decode(blockedA.bodyBytes)) as Map<String, dynamic>;
        expect(blockedBody['code'], 'DEVICE_REVOKED');

        final apiRevokedInfo = await api.getRemoteHostInfo();
        expect(apiRevokedInfo?['code'], 'DEVICE_REVOKED');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(revokedEvents, isNotEmpty);

        // Thiết bị B vẫn truy cập hoàn toàn bình thường
        final stillOkB = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_macbook_b', 'MacBook Phụ', 'macos'),
        );
        expect(stillOkB.statusCode, 200);
        expect(primaryHost.onlineClientCount, 1);

        // 4. App Chính bấm "Cho phép lại" cho thiết bị A -> chưa tính online cho tới khi A kết nối lại
        primaryHost.restoreClient('dev_xiaomi_a');
        expect(primaryHost.revokedClientIds, isNot(contains('dev_xiaomi_a')));
        expect(primaryHost.onlineClientCount, 1);

        final reconnectedA = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_xiaomi_a', 'Điện thoại Xiaomi', 'android'),
        );
        expect(reconnectedA.statusCode, 200);
        expect(primaryHost.onlineClientCount, 2);

        // 5. Thiết bị B tự ngắt kết nối chủ động (POST /api/remote/disconnect) -> giảm ngay số online mà không bị chặn
        final discB = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epRemoteDisconnect}'),
          headers: headersFor('dev_macbook_b', 'MacBook Phụ', 'macos'),
        );
        expect(discB.statusCode, 200);
        expect(primaryHost.onlineClientCount, 1);
        expect(primaryHost.revokedClientIds, isNot(contains('dev_macbook_b')));

        final rejoinB = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_macbook_b', 'MacBook Phụ', 'macos'),
        );
        expect(rejoinB.statusCode, 200);
        expect(primaryHost.onlineClientCount, 2);

        // 6. Thiết bị bị thu hồi nếu ghép nối 1 chạm và được PC duyệt -> tự động gỡ chặn
        await primaryHost.disconnectClient('dev_xiaomi_a', revoke: true);
        expect(primaryHost.revokedClientIds, contains('dev_xiaomi_a'));
        final pairReq = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epPairRequest}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_id': 'dev_xiaomi_a',
            'device_name': 'Điện thoại Xiaomi',
            'os': 'android',
          }),
        );
        expect(pairReq.statusCode, 200);
        final reqId = (jsonDecode(utf8.decode(pairReq.bodyBytes)) as Map)['request_id'] as String;
        primaryHost.approvePairingRequest(reqId);
        expect(primaryHost.revokedClientIds, isNot(contains('dev_xiaomi_a')));

        final afterApproveA = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_xiaomi_a', 'Điện thoại Xiaomi', 'android'),
        );
        expect(afterApproveA.statusCode, 200);
      } finally {
        await revokedSub.cancel();
        client.close();
      }
    });

    test('ẩn app phụ / đứt socket giữa chừng không hủy Agent trên App Chính, quay lại tự nối tiếp luồng live hoặc tải kết quả đã xong', () async {
      final api = ApiService();
      final created = await api.createChatSession(title: 'Phiên chạy bền nền');
      final sid = created.id;

      // === KỊCH BẢN 1: Ẩn app (đứt socket SSE) giữa chừng, quay lại KHI Agent vẫn đang chạy -> bám nối lại live qua /api/chat/live ===
      final hold1 = Completer<void>();
      fakeAi.holdBeforeDone = hold1;

      final firstTokenSeen = Completer<void>();
      final firstSub = api.streamChatMessage(
        sessionId: sid,
        message: 'Tác vụ chạy lâu 1',
        model: 'antigravity-cli',
        onToken: (tok) {
          if (tok.isNotEmpty && !firstTokenSeen.isCompleted) {
            firstTokenSeen.complete();
          }
        },
        onStatus: (_) {},
        onTool: (_) {},
        onDone: (_) {},
        onError: (_) {},
        onDisconnected: (_) {},
      );

      await firstTokenSeen.future.timeout(const Duration(seconds: 5));
      expect(primaryHost.isRemoteSessionGenerating(sid), isTrue);

      // Mô phỏng hệ điều hành đóng băng app phụ / đóng socket TCP (không bấm Stop)
      await firstSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Agent trên App Chính PHẢI VẪN ĐANG CHẠY, tuyệt đối không bị cancel!
      expect(primaryHost.isRemoteSessionGenerating(sid), isTrue);
      expect(primaryHost.activeChatCount, 1);

      // Mở lại App Phụ (ChatProvider mới hoặc quay lại tiền cảnh) -> tự bám nối lại luồng live đang chạy
      final secondaryChat = ChatProvider(
        apiService: api,
        hostServer: PrimaryHostServerService.forTest(databaseService: primaryDb),
        autoInit: false,
      );
      await secondaryChat.loadSessions(silent: true);
      final targetSess = secondaryChat.sessions.firstWhere((s) => s.id == sid);
      await secondaryChat.selectSession(targetSess);

      for (var i = 0; i < 40 && !secondaryChat.isSessionGenerating(sid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(secondaryChat.isSessionGenerating(sid), isTrue);
      expect(
        secondaryChat.messages.any((m) => m.role == 'assistant' && m.isStreaming && m.content.contains('Kết quả từ ')),
        isTrue,
      );

      // Mở khóa để Agent trên App Chính chạy xong -> App Phụ đang bám live nhận đủ câu trả lời
      hold1.complete();
      for (var i = 0; i < 60 && secondaryChat.isSessionGenerating(sid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(secondaryChat.isSessionGenerating(sid), isFalse);
      expect(primaryHost.isRemoteSessionGenerating(sid), isFalse);
      expect(
        secondaryChat.messages.any(
          (m) => m.role == 'assistant' && m.content == 'Kết quả từ App Chính: Tác vụ chạy lâu 1' && !m.isStreaming,
        ),
        isTrue,
      );

      // === KỊCH BẢN 2: Ẩn app lâu, Agent chạy XONG hoàn toàn trong lúc đứt socket -> onAppResumed() tải đủ câu trả lời từ SQLite ===
      final hold2 = Completer<void>();
      fakeAi.holdBeforeDone = hold2;

      final tok2Seen = Completer<void>();
      final sub2 = api.streamChatMessage(
        sessionId: sid,
        message: 'Tác vụ hoàn tất trong lúc ẩn app',
        model: 'antigravity-cli',
        onToken: (tok) {
          if (tok.isNotEmpty && !tok2Seen.isCompleted) tok2Seen.complete();
        },
        onStatus: (_) {},
        onTool: (_) {},
        onDone: (_) {},
        onError: (_) {},
        onDisconnected: (_) {},
      );
      await tok2Seen.future.timeout(const Duration(seconds: 5));
      await sub2.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(primaryHost.isRemoteSessionGenerating(sid), isTrue);

      // Hoàn tất Agent trong lúc App Phụ hoàn toàn không mở kết nối SSE
      hold2.complete();
      for (var i = 0; i < 50 && primaryHost.isRemoteSessionGenerating(sid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(primaryHost.isRemoteSessionGenerating(sid), isFalse);

      // Khi người dùng mở lại App Phụ -> onAppResumed() kiểm tra /api/chat/live (active: false) và tải câu trả lời mới nhất
      await secondaryChat.onAppResumed();
      expect(
        secondaryChat.messages.any(
          (m) => m.role == 'assistant' && m.content == 'Kết quả từ App Chính: Tác vụ hoàn tất trong lúc ẩn app',
        ),
        isTrue,
      );

      // === KỊCH BẢN 3: Bấm Dừng (/api/chat/stop) vẫn phải dừng được Agent ngay cả sau khi socket ban đầu đã đóng ===
      final hold3 = Completer<void>();
      fakeAi.holdBeforeDone = hold3;
      final tok3Seen = Completer<void>();
      final sub3 = api.streamChatMessage(
        sessionId: sid,
        message: 'Tác vụ cần bấm dừng tường minh',
        model: 'antigravity-cli',
        onToken: (tok) {
          if (tok.isNotEmpty && !tok3Seen.isCompleted) tok3Seen.complete();
        },
        onStatus: (_) {},
        onTool: (_) {},
        onDone: (_) {},
        onError: (_) {},
        onDisconnected: (_) {},
      );
      await tok3Seen.future.timeout(const Duration(seconds: 5));
      await sub3.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(primaryHost.isRemoteSessionGenerating(sid), isTrue);

      await api.stopRemoteChat(sid);
      expect(primaryHost.isRemoteSessionGenerating(sid), isFalse);
      if (!hold3.isCompleted) hold3.complete();
      fakeAi.holdBeforeDone = null;
      secondaryChat.dispose();
    });

    test('tự động tạo thư mục làm việc riêng cho từng App Phụ trong thư mục gốc đã cấu hình và cô lập phạm vi truy cập', () async {
      final workspacesRoot = p.join(tempDir.path, 'secondary_workspaces');
      primaryHost.updateRuntimeMetadata(secondaryWorkspacesRoot: workspacesRoot);
      expect(primaryHost.secondaryWorkspacesRoot, p.normalize(workspacesRoot));

      final client = http.Client();
      try {
        Map<String, String> headersFor(String id, String name, String os) => {
              'Authorization': 'Bearer $pairingToken',
              'Content-Type': 'application/json',
              'X-Client-Id': id,
              'X-Client-Name': Uri.encodeComponent(name),
              'X-Client-OS': os,
            };

        // 1. Hai App Phụ khác nhau kết nối -> mỗi máy được cấp 1 thư mục con riêng trong workspacesRoot
        final info1Res = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_phone_1111', 'Điện thoại Xiaomi', 'android'),
        );
        expect(info1Res.statusCode, 200);
        final info1 = jsonDecode(utf8.decode(info1Res.bodyBytes)) as Map<String, dynamic>;
        final ws1 = info1['client_workspace_dir']?.toString() ?? '';
        expect(ws1, isNotEmpty);
        expect(PrimaryHostServerService.isPathWithinRoot(ws1, workspacesRoot), isTrue);
        expect(Directory(ws1).existsSync(), isTrue);

        final info2Res = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_ipad_2222', 'iPad Công Việc', 'ios'),
        );
        expect(info2Res.statusCode, 200);
        final info2 = jsonDecode(utf8.decode(info2Res.bodyBytes)) as Map<String, dynamic>;
        final ws2 = info2['client_workspace_dir']?.toString() ?? '';
        expect(ws2, isNotEmpty);
        expect(PrimaryHostServerService.isPathWithinRoot(ws2, workspacesRoot), isTrue);
        expect(Directory(ws2).existsSync(), isTrue);
        expect(ws1, isNot(equals(ws2)));

        // ConnectedSecondaryClient phản ánh đúng đường dẫn thư mục làm việc của từng máy
        final snap1 = primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_phone_1111');
        final snap2 = primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_ipad_2222');
        expect(snap1.workspaceDir, ws1);
        expect(snap2.workspaceDir, ws2);

        // Đổi tên hiển thị của cùng clientId -> vẫn tái sử dụng đúng thư mục cũ, không sinh thư mục thừa
        final info1RenamedRes = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epRemoteInfo}'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
        );
        final info1Renamed = jsonDecode(utf8.decode(info1RenamedRes.bodyBytes)) as Map<String, dynamic>;
        expect(info1Renamed['client_workspace_dir'], ws1);

        // 2. Tạo session từ App Phụ 1 không truyền working_dir -> tự gắn mặc định là ws1
        final createSessRes = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
          body: jsonEncode({'title': 'Dự án của Phone 1'}),
        );
        expect(createSessRes.statusCode, 200);
        final sessJson = jsonDecode(utf8.decode(createSessRes.bodyBytes)) as Map<String, dynamic>;
        final sid = sessJson['id'] as String;
        expect(sessJson['working_dir'], ws1);

        // Cho phép chọn thư mục con bên trong ws1, nhưng cố trỏ sang ws2 sẽ bị ép về ws1
        final sub1 = Directory(p.join(ws1, 'my_project'))..createSync(recursive: true);
        final okSubScope = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sid/scope'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
          body: jsonEncode({'working_dir': sub1.path}),
        );
        expect((jsonDecode(utf8.decode(okSubScope.bodyBytes)) as Map)['working_dir'], sub1.path);

        final escapeScope = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sid/scope'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
          body: jsonEncode({'working_dir': ws2}),
        );
        expect((jsonDecode(utf8.decode(escapeScope.bodyBytes)) as Map)['working_dir'], ws1);

        // Chạy POST /api/chat từ App Phụ 1 cố truyền working_dir: ws2 -> AI chỉ nhận đúng ws1
        final chatReq = http.Request('POST', Uri.parse('$baseUrl${ApiConstants.epChat}'))
          ..headers.addAll(headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'))
          ..body = jsonEncode({
            'session_id': sid,
            'message': 'Kiểm tra thư mục làm việc',
            'working_dir': ws2,
          });
        final chatStreamRes = await client.send(chatReq);
        expect(chatStreamRes.statusCode, 200);
        await chatStreamRes.stream.drain<void>();
        expect(fakeAi.lastReceivedWorkingDir, ws1);

        // 3. Duyệt thư mục, upload & download bị cô lập hoàn toàn theo từng App Phụ
        final list1Res = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epFsListDirs}?prefix=${Uri.encodeQueryComponent(ws2)}'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
        );
        final list1 = ((jsonDecode(utf8.decode(list1Res.bodyBytes)) as Map)['directories'] as List).cast<String>();
        expect(list1, contains(ws1));
        expect(list1, contains(sub1.path));
        expect(list1, isNot(contains(ws2)));

        final upload1Res = await client.post(
          Uri.parse('$baseUrl${ApiConstants.epFsUpload}'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
          body: jsonEncode({
            'file_name': 'secret_phone1.txt',
            'content_base64': base64Encode(utf8.encode('private phone1 data')),
            'target_dir': ws2, // Cố ghi sang thư mục của máy 2 -> bị chặn về ws1
          }),
        );
        expect(upload1Res.statusCode, 200);
        final uploadedPath1 = (jsonDecode(utf8.decode(upload1Res.bodyBytes)) as Map)['remote_path'] as String;
        expect(PrimaryHostServerService.isPathWithinRoot(uploadedPath1, ws1), isTrue);
        expect(File(uploadedPath1).existsSync(), isTrue);

        // Máy 1 tải được tệp của mình (200), máy 2 tải tệp của máy 1 bị chặn (403 Forbidden)
        final dlOwn = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epFsDownload}?path=${Uri.encodeQueryComponent(uploadedPath1)}'),
          headers: headersFor('dev_phone_1111', 'Xiaomi Đổi Tên', 'android'),
        );
        expect(dlOwn.statusCode, 200);
        expect(utf8.decode(dlOwn.bodyBytes), 'private phone1 data');

        final dlCross = await client.get(
          Uri.parse('$baseUrl${ApiConstants.epFsDownload}?path=${Uri.encodeQueryComponent(uploadedPath1)}'),
          headers: headersFor('dev_ipad_2222', 'iPad Công Việc', 'ios'),
        );
        expect(dlCross.statusCode, 403);

        // 4. Đổi thư mục gốc lúc runtime -> cập nhật workspace mới cho các máy đang kết nối
        final newRoot = p.join(tempDir.path, 'moved_workspaces_root');
        primaryHost.updateRuntimeMetadata(secondaryWorkspacesRoot: newRoot);
        final movedSnap1 = primaryHost.connectedClients.firstWhere((c) => c.clientId == 'dev_phone_1111');
        expect(PrimaryHostServerService.isPathWithinRoot(movedSnap1.workspaceDir, newRoot), isTrue);
        expect(Directory(movedSnap1.workspaceDir).existsSync(), isTrue);
      } finally {
        client.close();
      }
    });

    test('App Phụ duyệt ảnh, video, tệp qua /api/fs/list_entries và tải stream thẳng xuống đĩa + hỗ trợ HTTP Range', () async {
      final workspacesRoot = p.join(tempDir.path, 'media_workspaces');
      primaryHost.updateRuntimeMetadata(secondaryWorkspacesRoot: workspacesRoot);
      await StorageService().setClientDeviceId('dev_media_phone');

      final api = ApiService();
      final info = await api.getRemoteHostInfo();
      final wsDir = info?['client_workspace_dir']?.toString() ?? '';
      expect(wsDir, isNotEmpty);

      // Tạo thư mục con, ảnh PNG, video MP4 giả lập (128KB) và tệp PDF bên trong workspace của App Phụ
      final subMedia = Directory(p.join(wsDir, 'exports'))..createSync(recursive: true);
      final pngFile = File(p.join(wsDir, 'banner.png'))
        ..writeAsBytesSync(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]));
      final videoBytes = Uint8List.fromList(List<int>.generate(131072, (i) => i % 251));
      final mp4File = File(p.join(wsDir, 'demo_clip.mp4'))..writeAsBytesSync(videoBytes);
      final pdfFile = File(p.join(subMedia.path, 'report.pdf'))..writeAsStringSync('%PDF-1.7 sample report');

      // 1. Liệt kê tất cả ở thư mục gốc workspace
      final allRes = await api.listRemoteEntries();
      expect(allRes.hasError, isFalse);
      expect(allRes.currentPath, wsDir);
      expect(allRes.parentPath, isNull); // Không cho leo ra ngoài workspace
      expect(allRes.entries.map((e) => e.name), containsAll(['exports', 'banner.png', 'demo_clip.mp4']));
      final videoEntry = allRes.entries.firstWhere((e) => e.name == 'demo_clip.mp4');
      expect(videoEntry.isVideo, isTrue);
      expect(videoEntry.mimeType, 'video/mp4');
      expect(videoEntry.size, videoBytes.length);

      // 2. Lọc theo loại Hình ảnh & Video + đi vào thư mục con exports
      final imgOnly = await api.listRemoteEntries(filter: 'image');
      expect(imgOnly.entries.where((e) => !e.isDir).map((e) => e.name), ['banner.png']);

      final vidOnly = await api.listRemoteEntries(filter: 'video');
      expect(vidOnly.entries.where((e) => !e.isDir).map((e) => e.name), ['demo_clip.mp4']);

      final subRes = await api.listRemoteEntries(path: subMedia.path);
      expect(subRes.parentPath, wsDir);
      expect(subRes.entries.map((e) => e.name), contains('report.pdf'));

      // 3. Tải stream video thẳng xuống đĩa bằng RemoteFileDownloadService.downloadAndSave
      final saveDestDir = Directory(p.join(tempDir.path, 'phone_downloads'))..createSync(recursive: true);
      final progressUpdates = <double>[];
      final saveRes = await RemoteFileDownloadService.downloadAndSave(
        api: api,
        remotePath: mp4File.path,
        fileName: 'demo_clip.mp4',
        customSaveDirectory: saveDestDir.path,
        onProgress: (_, _, prog) => progressUpdates.add(prog),
      );
      expect(saveRes.ok, isTrue);
      expect(saveRes.bytes, videoBytes.length);
      expect(File(saveRes.savedPath).readAsBytesSync(), orderedEquals(videoBytes));
      expect(progressUpdates.last, 1.0);

      // 4. Kiểm tra HTTP Range (206 Partial Content) phục vụ stream/tua video
      final rawClient = http.Client();
      try {
        final rangeRes = await rawClient.get(
          Uri.parse('$baseUrl${ApiConstants.epFsDownload}?path=${Uri.encodeQueryComponent(mp4File.path)}'),
          headers: {
            'Authorization': 'Bearer $pairingToken',
            'X-Client-Id': 'dev_media_phone',
            'Range': 'bytes=0-15',
          },
        );
        expect(rangeRes.statusCode, 206);
        expect(rangeRes.headers['content-type'], 'video/mp4');
        expect(rangeRes.headers['accept-ranges'], 'bytes');
        expect(rangeRes.headers['content-range'], 'bytes 0-15/${videoBytes.length}');
        expect(rangeRes.bodyBytes.length, 16);
        expect(rangeRes.bodyBytes, orderedEquals(videoBytes.sublist(0, 16)));
      } finally {
        rawClient.close();
      }

      // 5. Kiểm tra trích xuất đường dẫn ảnh/video/tệp từ câu trả lời của Agent
      final extracted = RemoteFileDownloadService.extractDownloadablePathsFromText(
        'Đã xuất xong ảnh [banner](file://${pngFile.path}), video `${mp4File.path}` và báo cáo ${pdfFile.path}. '
        'Bỏ qua link web https://example.com/fake.png nhé.',
      );
      expect(extracted, [pngFile.path, mp4File.path, pdfFile.path]);
    });

    test('đồng bộ loading thời gian thực từ App Chính sang App Phụ khi App Chính đang hỏi Agent và cho phép dừng từ xa', () async {
      final remoteApi = ApiService();
      final nativePrimaryApi = _FakeNativePrimaryApiService(db: primaryDb, ai: fakeAi);

      final created = await remoteApi.createChatSession(title: 'Phiên đồng bộ App Chính -> App Phụ');
      final sid = created.id;

      final primaryChat = ChatProvider(
        apiService: nativePrimaryApi,
        hostServer: primaryHost,
        autoInit: false,
      );
      final secondaryChat = ChatProvider(
        apiService: remoteApi,
        hostServer: PrimaryHostServerService.forTest(databaseService: primaryDb),
        autoInit: false,
      );

      try {
        await primaryChat.loadSessions(silent: true);
        await secondaryChat.loadSessions(silent: true);
        await primaryChat.selectSession(primaryChat.sessions.firstWhere((s) => s.id == sid));
        await secondaryChat.selectSession(secondaryChat.sessions.firstWhere((s) => s.id == sid));

        // Bật luồng sự kiện thời gian thực trên App Phụ (GET /api/remote/events)
        await secondaryChat.startRemoteEventSync();
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(primaryChat.isGenerating, isFalse);
        expect(secondaryChat.isGenerating, isFalse);
        expect(secondaryChat.isRemoteGenerating, isFalse);

        // 1. App Chính bắt đầu hỏi Agent (giữ giữa chừng để kiểm chứng đồng bộ live sang App Phụ)
        final hold1 = Completer<void>();
        fakeAi.holdBeforeDone = hold1;
        fakeAi.callCount = 0;

        unawaited(primaryChat.sendMessage('Câu hỏi chạy trực tiếp trên App Chính'));

        for (var i = 0; i < 60 && !secondaryChat.isRemoteGenerating; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        // App Phụ phải thấy ngay loading + nhãn nguồn "App Chính" + tin nhắn live đang stream
        expect(secondaryChat.isSessionGenerating(sid), isTrue);
        expect(secondaryChat.isGenerating, isTrue);
        expect(secondaryChat.isRemoteGenerating, isTrue);
        expect(secondaryChat.remoteGeneratingSourceLabel, 'App Chính');

        for (var i = 0;
            i < 60 && !secondaryChat.messages.any((m) => m.role == 'assistant' && m.content.contains('Kết quả từ '));
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(
          secondaryChat.messages.any((m) => m.role == 'assistant' && m.isStreaming && m.content.contains('Kết quả từ ')),
          isTrue,
        );

        // 2. Chặn gửi trùng từ App Phụ trên cùng hộp hội thoại trong khi App Chính đang hỏi Agent
        await secondaryChat.sendMessage('Câu hỏi gửi đè từ App Phụ');
        expect(fakeAi.callCount, 1);

        // 3. App Chính hoàn tất câu trả lời -> App Phụ tự tắt loading và hiện đủ nội dung
        hold1.complete();
        for (var i = 0; i < 60 && (primaryChat.isGenerating || secondaryChat.isGenerating); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(primaryChat.isGenerating, isFalse);
        expect(secondaryChat.isGenerating, isFalse);
        expect(secondaryChat.isRemoteGenerating, isFalse);
        expect(
          secondaryChat.messages.any(
            (m) =>
                m.role == 'assistant' &&
                !m.isStreaming &&
                m.content == 'Kết quả từ App Chính: Câu hỏi chạy trực tiếp trên App Chính',
          ),
          isTrue,
        );

        // 4. App Phụ có thể bấm Dừng từ xa phiên đang chạy trên App Chính
        final hold2 = Completer<void>();
        fakeAi.holdBeforeDone = hold2;
        unawaited(primaryChat.sendMessage('Tác vụ cần App Phụ bấm dừng từ xa'));

        for (var i = 0; i < 60 && !secondaryChat.isRemoteGenerating; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(primaryChat.isGenerating, isTrue);
        expect(secondaryChat.isRemoteGenerating, isTrue);

        secondaryChat.stopGenerating();
        for (var i = 0; i < 60 && primaryChat.isGenerating; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(primaryChat.isGenerating, isFalse);
        expect(secondaryChat.isGenerating, isFalse);
        expect(primaryHost.isSessionBusy(sid), isFalse);

        if (!hold2.isCompleted) hold2.complete();
        fakeAi.holdBeforeDone = null;
      } finally {
        primaryChat.dispose();
        secondaryChat.dispose();
      }
    });
  });

  group('SettingsScreen Role Control UI (Mobile & Desktop)', () {
    testWidgets('hiển thị thẻ Vai Trò Thiết Bị và chuyển đổi App Chính <-> App Phụ không lỗi layout trên mobile', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();
      await StorageService().setAppRole(AppRole.primary);
      await StorageService().setPrimaryHostEnabled(false);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final gatewayProvider = GatewayProvider();
      final serverProvider = ServerProvider();
      final chatProvider = ChatProvider();
      final terminalProvider = TerminalProvider();
      addTearDown(() {
        gatewayProvider.dispose();
        serverProvider.dispose();
        chatProvider.dispose();
        terminalProvider.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GatewayProvider>.value(value: gatewayProvider),
            ChangeNotifierProvider<ServerProvider>.value(value: serverProvider),
            ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
            ChangeNotifierProvider<TerminalProvider>.value(value: terminalProvider),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Kiểm tra thẻ Group 0, Mã QR ghép nối và các chế độ Đường hầm Internet trên mobile
      expect(find.text('0. Vai Trò Thiết Bị (App Chính / App Phụ)'), findsOneWidget);
      expect(find.byKey(const Key('role_primary_button')), findsOneWidget);
      expect(find.byKey(const Key('role_secondary_button')), findsOneWidget);
      expect(find.byKey(const Key('primary_host_toggle')), findsOneWidget);
      expect(find.byKey(const Key('primary_pairing_qr')), findsOneWidget);
      expect(find.byKey(const Key('tunnel_mode_off')), findsOneWidget);
      expect(find.byKey(const Key('tunnel_mode_quick')), findsOneWidget);
      expect(find.byKey(const Key('tunnel_mode_named')), findsOneWidget);
      expect(find.byKey(const Key('tunnel_mode_custom')), findsOneWidget);

      // Chuyển sang Domain cố định & URL/VPN riêng (không chạy tiến trình ngoài) để kiểm tra bố cục mobile
      await tester.tap(find.byKey(const Key('tunnel_mode_named')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      expect(find.byKey(const Key('named_tunnel_url_input')), findsOneWidget);
      expect(find.byKey(const Key('named_tunnel_token_input')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tunnel_mode_custom')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      expect(find.byKey(const Key('custom_public_url_input')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tunnel_mode_off')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();

      // Chuyển sang App Phụ -> mặc định hiển thị Tìm máy tính gần đây và mục nhập tay được gập gọn
      await tester.tap(find.byKey(const Key('role_secondary_button')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(gatewayProvider.role, AppRole.secondary);
      expect(find.byKey(const Key('secondary_discover_hosts_button')), findsOneWidget);
      expect(find.byKey(const Key('toggle_manual_connect_button')), findsOneWidget);
      expect(find.byKey(const Key('secondary_url_input')), findsNothing);

      // Mở mục kết nối thủ công -> mặc định là tab 1 (Dán chuỗi ghép nối), không bày trùng 3 ô cùng lúc
      await tester.tap(find.byKey(const Key('toggle_manual_connect_button')));
      await tester.pump();
      expect(find.byKey(const Key('manual_mode_paste_tab')), findsOneWidget);
      expect(find.byKey(const Key('manual_mode_fields_tab')), findsOneWidget);
      expect(find.byKey(const Key('secondary_pairing_paste_input')), findsOneWidget);
      expect(find.byKey(const Key('secondary_url_input')), findsNothing);
      expect(find.byKey(const Key('secondary_connect_button')), findsOneWidget);

      // Chuyển sang tab 2 (Nhập URL & Mã) -> chỉ hiện đúng 2 ô URL + Token
      await tester.tap(find.byKey(const Key('manual_mode_fields_tab')));
      await tester.pump();
      expect(find.byKey(const Key('secondary_pairing_paste_input')), findsNothing);
      expect(find.byKey(const Key('secondary_url_input')), findsOneWidget);
      expect(find.byKey(const Key('secondary_token_input')), findsOneWidget);
      expect(find.byKey(const Key('secondary_connect_button')), findsOneWidget);

      // Kiểm tra disconnectFromPrimary xóa sạch URL/Token và đưa trạng thái về disconnected
      await gatewayProvider.disconnectFromPrimary(clearSavedCredentials: true);
      expect(gatewayProvider.status, GatewayStatus.disconnected);
      expect(gatewayProvider.gatewayUrl, isEmpty);
      expect(gatewayProvider.secretToken, isEmpty);

      // Chuyển lại App Chính để sạch trạng thái
      await tester.tap(find.byKey(const Key('role_primary_button')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(gatewayProvider.role, AppRole.primary);

      // Xả hết animation/toast và timer timeout ngắn hạn trước khi kết thúc test
      await tester.pump(const Duration(seconds: 12));

      // Đảm bảo không có ngoại lệ RenderFlex overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('hiển thị danh sách thiết bị App Phụ đang kết nối và ngắt/cho phép từng máy trên mobile', (tester) async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();
      await StorageService().setAppRole(AppRole.primary);
      await StorageService().setPrimaryHostEnabled(false);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final host = PrimaryHostServerService.instance;
      const testToken = 'ui_connected_clients_token_123';
      final uiRootDir = Directory.systemTemp.createTempSync('agent_coder_ui_ws_root_');
      await StorageService().setSecondaryWorkspacesRoot(uiRootDir.path);
      await host.stop();
      host.clearRevokedClients();

      final started = await tester.runAsync(() => host.start(
            port: 0,
            token: testToken,
            deviceName: 'Primary UI Test',
            secondaryWorkspacesRoot: uiRootDir.path,
            bindAddress: InternetAddress.loopbackIPv4,
          ));
      expect(started, isTrue);

      final gw = GatewayProvider();
      final serverProvider = ServerProvider();
      final chatProvider = ChatProvider();
      final terminalProvider = TerminalProvider();
      addTearDown(() async {
        gw.dispose();
        serverProvider.dispose();
        chatProvider.dispose();
        terminalProvider.dispose();
        host.clearRevokedClients();
        await host.stop();
        if (uiRootDir.existsSync()) {
          uiRootDir.deleteSync(recursive: true);
        }
        HttpOverrides.global = previousOverrides;
      });

      // Giả lập 2 thiết bị App Phụ kết nối vào PrimaryHostServerService.instance
      await tester.runAsync(() async {
        final httpClient = http.Client();
        try {
          final base = 'http://127.0.0.1:${host.boundPort}';
          await httpClient.get(
            Uri.parse('$base${ApiConstants.epRemoteInfo}'),
            headers: {
              'Authorization': 'Bearer $testToken',
              'X-Client-Id': 'dev_ui_phone',
              'X-Client-Name': Uri.encodeComponent('Xiaomi 10T Pro'),
              'X-Client-OS': 'android',
            },
          );
          await httpClient.get(
            Uri.parse('$base${ApiConstants.epRemoteInfo}'),
            headers: {
              'Authorization': 'Bearer $testToken',
              'X-Client-Id': 'dev_ui_tablet',
              'X-Client-Name': Uri.encodeComponent('iPad Mini'),
              'X-Client-OS': 'ios',
            },
          );
        } finally {
          httpClient.close();
        }
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GatewayProvider>.value(value: gw),
            ChangeNotifierProvider<ServerProvider>.value(value: serverProvider),
            ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
            ChangeNotifierProvider<TerminalProvider>.value(value: terminalProvider),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('secondary_workspaces_root_input')), findsOneWidget);
      expect(find.byKey(const Key('pick_secondary_workspaces_root_button')), findsOneWidget);
      expect(find.byKey(const Key('save_secondary_workspaces_root_button')), findsOneWidget);
      expect(find.byKey(const Key('connected_secondary_clients_panel')), findsOneWidget);
      expect(find.byKey(const Key('client_workspace_dev_ui_phone')), findsOneWidget);
      expect(find.byKey(const Key('client_workspace_dev_ui_tablet')), findsOneWidget);
      expect(find.text('2 đang online'), findsOneWidget);
      expect(find.text('Xiaomi 10T Pro'), findsOneWidget);
      expect(find.text('iPad Mini'), findsOneWidget);

      // Cuộn tới nút Ngắt kết nối của riêng Xiaomi 10T Pro rồi bấm
      final disconnectPhoneBtn = find.byKey(const Key('disconnect_client_dev_ui_phone'));
      await tester.ensureVisible(disconnectPhoneBtn);
      await tester.pump();
      await tester.tap(disconnectPhoneBtn);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('1 đang online'), findsOneWidget);
      expect(find.text('Đã ngắt quyền'), findsOneWidget);
      expect(find.byKey(const Key('restore_client_dev_ui_phone')), findsOneWidget);
      expect(host.revokedClientIds, contains('dev_ui_phone'));

      // Bấm Cho phép lại -> gỡ chặn thiết bị
      final restorePhoneBtn = find.byKey(const Key('restore_client_dev_ui_phone'));
      await tester.ensureVisible(restorePhoneBtn);
      await tester.pump();
      await tester.tap(restorePhoneBtn);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(host.revokedClientIds, isNot(contains('dev_ui_phone')));
      await tester.pump(const Duration(seconds: 12));
      expect(tester.takeException(), isNull);
    });

    testWidgets('RemoteFilesBrowserDialog hiển thị thư mục, ảnh, video, tệp và lọc mượt trên màn hình mobile', (tester) async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();

      final tempRoot = Directory.systemTemp.createTempSync('agent_coder_browser_ui_');
      final db = DatabaseService.forTest(p.join(tempRoot.path, 'browser.db'));
      final host = PrimaryHostServerService.forTest(databaseService: db);
      const tok = 'browser_ui_token_999';
      final wsRoot = p.join(tempRoot.path, 'ws_root');

      final started = await tester.runAsync(() async {
        await db.init();
        return await host.start(
          port: 0,
          token: tok,
          deviceName: 'Primary Media Host',
          secondaryWorkspacesRoot: wsRoot,
          bindAddress: InternetAddress.loopbackIPv4,
        );
      });
      expect(started, isTrue);

      await StorageService().setAppRole(AppRole.secondary);
      await StorageService().setGatewayUrl('http://127.0.0.1:${host.boundPort}');
      await StorageService().setSecretToken(tok);
      await StorageService().setClientDeviceId('dev_browser_mobile');

      addTearDown(() async {
        await tester.runAsync(() async {
          await host.stop();
          await db.close();
        });
        await StorageService().setAppRole(AppRole.primary);
        await StorageService().setGatewayUrl('');
        await StorageService().setSecretToken('');
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        HttpOverrides.global = previousOverrides;
      });

      final api = ApiService();
      final info = await tester.runAsync(() => api.getRemoteHostInfo());
      final clientWs = info?['client_workspace_dir']?.toString() ?? '';
      expect(clientWs, isNotEmpty);

      // Tạo dữ liệu mẫu trong workspace của App Phụ
      final subDir = Directory(p.join(clientWs, 'clips'))..createSync(recursive: true);
      File(p.join(clientWs, 'clip_01.mp4')).writeAsBytesSync(List<int>.filled(2048, 7));
      File(p.join(clientWs, 'summary.pdf')).writeAsStringSync('%PDF-1.7');
      File(p.join(subDir.path, 'nested_video.mkv')).writeAsBytesSync(List<int>.filled(1024, 9));

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> pumpUntil(Finder finder) async {
        for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
          await tester.pump();
        }
      }

      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: RemoteFilesBrowserDialog(
                initialPath: clientWs,
                isSecondaryMode: true,
                apiService: api,
              ),
            ),
          ),
        );
        await pumpUntil(find.text('clips'));

        final renderedTexts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
        expect(find.byKey(const Key('remote_files_browser_dialog')), findsOneWidget);
        expect(find.text('clips'), findsOneWidget, reason: 'Rendered texts: $renderedTexts');
        expect(find.text('clip_01.mp4'), findsOneWidget);
        expect(find.text('summary.pdf'), findsOneWidget);

        // Lọc chỉ hiện Video
        await tester.tap(find.byKey(const Key('remote_fs_filter_video')));
        await tester.pump();
        await pumpUntil(find.text('clip_01.mp4'));
        expect(find.text('clip_01.mp4'), findsOneWidget);
        expect(find.text('summary.pdf'), findsNothing);

        // Bấm vào thư mục con clips -> thấy tệp nested_video.mkv và xuất hiện nút lên thư mục cha
        await tester.tap(find.byKey(const Key('remote_fs_entry_clips')));
        await tester.pump();
        await pumpUntil(find.text('nested_video.mkv'));
        expect(find.text('nested_video.mkv'), findsOneWidget);
        expect(find.byKey(const Key('remote_fs_up_button')), findsOneWidget);

        // Lên thư mục cha
        await tester.tap(find.byKey(const Key('remote_fs_up_button')));
        await tester.pump();
        await pumpUntil(find.text('clip_01.mp4'));
        expect(find.text('clip_01.mp4'), findsOneWidget);

        await tester.pump(const Duration(seconds: 20));
        expect(tester.takeException(), isNull);
      }, _PassthroughHttpOverrides());
    });
  });

  group('RemoteTunnelService & Network Endpoint Filtering', () {
    test('trích xuất URL Quick Tunnel, chuẩn hóa Public URL và lọc bỏ card mạng Docker', () {
      expect(
        RemoteTunnelService.extractQuickTunnelUrl(
          '2026-11-26 INF |  https://solar-pine-42.trycloudflare.com  |',
        ),
        'https://solar-pine-42.trycloudflare.com',
      );
      expect(
        RemoteTunnelService.extractQuickTunnelUrl('INF Registered tunnel connection'),
        isNull,
      );

      expect(
        RemoteTunnelService.normalizePublicUrl('agent.example.com/'),
        'https://agent.example.com',
      );
      expect(
        RemoteTunnelService.normalizePublicUrl('100.68.203.77:8765/'),
        'http://100.68.203.77:8765',
      );
      expect(
        RemoteTunnelService.normalizePublicUrl('https://remote.myhost.vn///'),
        'https://remote.myhost.vn',
      );

      // Kiểm tra lọc card ảo Docker / VM / Bridge
      expect(PrimaryHostServerService.isVirtualBridgeInterface('docker0'), isTrue);
      expect(PrimaryHostServerService.isVirtualBridgeInterface('br-8f31ab12'), isTrue);
      expect(PrimaryHostServerService.isVirtualBridgeInterface('veth12a4f'), isTrue);
      expect(PrimaryHostServerService.isVirtualBridgeInterface('virbr0'), isTrue);
      expect(PrimaryHostServerService.isVirtualBridgeInterface('enp3s0'), isFalse);
      expect(PrimaryHostServerService.isVirtualBridgeInterface('wlan0'), isFalse);
      expect(PrimaryHostServerService.isVirtualBridgeInterface('tailscale0'), isFalse);

      // Kiểm tra nhận diện dải Tailscale CGNAT (100.64.0.0/10)
      expect(PrimaryHostServerService.isTailscaleOrCgnatIp('100.68.203.77'), isTrue);
      expect(PrimaryHostServerService.isTailscaleOrCgnatIp('100.127.255.254'), isTrue);
      expect(PrimaryHostServerService.isTailscaleOrCgnatIp('100.128.0.1'), isFalse);
      expect(PrimaryHostServerService.isTailscaleOrCgnatIp('192.168.1.78'), isFalse);
    });

    test('GatewayProvider ưu tiên địa chỉ Internet HTTPS trong primaryPairingString khi kích hoạt Custom URL', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();
      await StorageService().setAppRole(AppRole.primary);
      await StorageService().setPrimaryHostEnabled(false);
      await StorageService().setPrimaryHostPort(19765);

      final gw = GatewayProvider();
      addTearDown(() async {
        await RemoteTunnelService.instance.stop(resetModeToOff: true);
        await PrimaryHostServerService.instance.stop();
        await StorageService().setPrimaryHostPort(ApiConstants.defaultPrimaryHostPort);
        gw.dispose();
      });

      await Future<void>.delayed(const Duration(milliseconds: 120));
      await gw.applyCustomPublicUrl('https://pc-home.example.com');
      expect(gw.isInternetTunnelRunning, isTrue);
      expect(gw.publicTunnelUrl, 'https://pc-home.example.com');
      expect(gw.primaryPairingString, startsWith('https://pc-home.example.com#'));
      expect(gw.primaryInternetPairingString, startsWith('https://pc-home.example.com#'));

      await gw.setTunnelMode(RemoteTunnelMode.off);
      expect(gw.isInternetTunnelRunning, isFalse);
      expect(gw.publicTunnelUrl, isEmpty);
    });

    test('Chi App Phu yeu cau tao/xuat anh, video hoac file moi bat preview + download', () {
      const assistantWithImage = 'Da tao xong anh tai `/tmp/workspace/cat.png` va video `/tmp/workspace/demo.mp4`.';
      const assistantWithPdf = 'Bao cao da xuat ra [report.pdf](file:///tmp/workspace/report.pdf).';

      // App Chinh: tuyet doi KHONG hien du yeu cau tao anh/video/file
      expect(
        RemoteFileDownloadService.shouldShowRemotePreviewAndDownload(
          isSecondaryMode: false,
          userPrompt: 'Tao cho minh 1 tam anh con meo va video demo',
          assistantText: assistantWithImage,
        ),
        isFalse,
      );

      // App Phu + yeu cau tao anh/video/file: HIEN preview + download
      expect(
        RemoteFileDownloadService.shouldShowRemotePreviewAndDownload(
          isSecondaryMode: true,
          userPrompt: 'Tạo cho mình 1 ảnh con mèo và video ngắn',
          assistantText: assistantWithImage,
        ),
        isTrue,
      );
      expect(
        RemoteFileDownloadService.shouldShowRemotePreviewAndDownload(
          isSecondaryMode: true,
          userPrompt: 'Xuất báo cáo PDF giúp mình',
          assistantText: assistantWithPdf,
        ),
        isTrue,
      );

      // App Phu + xac nhan ngan "lam luon" sau yeu cau tao anh/file: HIEN
      expect(
        RemoteFileDownloadService.shouldShowRemotePreviewAndDownload(
          isSecondaryMode: true,
          userPrompt: 'Làm luôn',
          previousUserPrompt: 'Tạo file PDF tổng kết dự án nhé',
          assistantText: assistantWithPdf,
        ),
        isTrue,
      );

      // App Phu + cau hoi thong thuong KHONG yeu cau tao media/file: AN
      expect(
        RemoteFileDownloadService.shouldShowRemotePreviewAndDownload(
          isSecondaryMode: true,
          userPrompt: 'Giải thích lệnh ffmpeg chạy thế nào?',
          assistantText: assistantWithImage,
        ),
        isFalse,
      );
      expect(
        RemoteFileDownloadService.shouldShowRemotePreviewAndDownload(
          isSecondaryMode: true,
          userPrompt: 'Kiểm tra thư mục dự án hiện có gì',
          assistantText: assistantWithPdf,
        ),
        isFalse,
      );

      // Tep ma nguon TypeScript (.ts) KHONG duoc nhan nham la video hay tep tai xuong
      expect(RemoteFsEntry.detectKind('/tmp/affiliate-livestream-dialog.component.ts'), 'file');
      expect(
        RemoteFileDownloadService.extractDownloadablePathsFromText(
          'Da sua tep [affiliate-livestream-dialog.component.ts](file:///tmp/affiliate-livestream-dialog.component.ts)',
        ),
        isEmpty,
      );
    });

    testWidgets('RemoteChatDetectedFilesBar an hoan toan tren App Chinh va chi hien tren App Phu', (tester) async {
      final api = ApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteChatDetectedFilesBar(
              paths: const ['/tmp/demo_image.png', '/tmp/demo_video.mp4'],
              isSecondaryMode: false,
              apiService: api,
            ),
          ),
        ),
      );
      expect(find.text('demo_image.png'), findsNothing);
      expect(find.text('demo_video.mp4'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteChatDetectedFilesBar(
              paths: const ['/tmp/demo_image.png', '/tmp/demo_video.mp4'],
              isSecondaryMode: true,
              apiService: api,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('demo_image.png'), findsOneWidget);
      expect(find.text('demo_video.mp4'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsNWidgets(2));
    });
  });
}
