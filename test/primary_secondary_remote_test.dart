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
import 'package:tadu_cloud_ai_agent_mobile/core/services/remote_tunnel_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/storage_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/attachment_item.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/chat_message.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/server_model.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/chat_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/gateway_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/server_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/terminal_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

      // Xả hết animation/toast ngắn hạn trước khi kết thúc test
      await tester.pump(const Duration(seconds: 4));

      // Đảm bảo không có ngoại lệ RenderFlex overflow
      expect(tester.takeException(), isNull);
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
  });
}
