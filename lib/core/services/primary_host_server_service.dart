import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_pty_desktop/flutter_pty.dart';
import 'package:path/path.dart' as p;

import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/server_model.dart';
import '../constants/api_constants.dart';
import 'cli_scanner_service.dart';
import 'database_service.dart';
import 'local_config_service.dart';
import 'native_ai_service.dart';
import 'native_ssh_service.dart';

/// Thông tin máy tính App Chính được phát hiện tự động trong mạng gần đây qua UDP Discovery.
class DiscoveredPrimaryHost {
  final String deviceName;
  final String os;
  final int port;
  final String lanUrl;
  final String vpnUrl;
  final String publicUrl;
  final String preferredUrl;

  const DiscoveredPrimaryHost({
    required this.deviceName,
    required this.os,
    required this.port,
    required this.lanUrl,
    this.vpnUrl = '',
    this.publicUrl = '',
    required this.preferredUrl,
  });

  bool get hasInternetAccess => publicUrl.isNotEmpty || vpnUrl.isNotEmpty;
}

/// Yêu cầu ghép nối 1 chạm từ App Phụ đang chờ người dùng bấm "Chấp nhận" trên màn hình App Chính.
class PendingPairingRequest {
  final String id;
  final String clientId;
  final String clientDeviceName;
  final String clientOs;
  final String clientIp;
  final String pin;
  final DateTime createdAt;
  String status; // 'pending' | 'approved' | 'rejected'

  PendingPairingRequest({
    required this.id,
    this.clientId = '',
    required this.clientDeviceName,
    required this.clientOs,
    required this.clientIp,
    required this.pin,
    required this.createdAt,
    this.status = 'pending',
  });

  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(seconds: 65);
}

/// Thông tin một thiết bị App Phụ đang (hoặc vừa) kết nối vào App Chính.
class ConnectedSecondaryClient {
  final String clientId;
  String deviceName;
  String os;
  String ip;
  String workspaceDir;
  final DateTime connectedAt;
  DateTime lastSeenAt;
  int activeChats;
  int activeTerminals;
  bool isRevoked;

  ConnectedSecondaryClient({
    required this.clientId,
    required this.deviceName,
    required this.os,
    required this.ip,
    this.workspaceDir = '',
    required this.connectedAt,
    required this.lastSeenAt,
    this.activeChats = 0,
    this.activeTerminals = 0,
    this.isRevoked = false,
  });

  /// Coi là đang online nếu không bị ngắt quyền và đang có luồng hoạt động hoặc vừa giao tiếp trong 65 giây.
  bool get isOnline =>
      !isRevoked &&
      (activeChats > 0 ||
          activeTerminals > 0 ||
          DateTime.now().difference(lastSeenAt) <= const Duration(seconds: 65));

  ConnectedSecondaryClient copySnapshot() => ConnectedSecondaryClient(
        clientId: clientId,
        deviceName: deviceName,
        os: os,
        ip: ip,
        workspaceDir: workspaceDir,
        connectedAt: connectedAt,
        lastSeenAt: lastSeenAt,
        activeChats: activeChats,
        activeTerminals: activeTerminals,
        isRevoked: isRevoked,
      );
}

/// Loại sự kiện đồng bộ trực tiếp phiên chat mà App Phụ đang hỏi Agent về UI App Chính.
enum RemoteChatSyncType { start, status, token, tool, done, error, stop }

/// Sự kiện đồng bộ thời gian thực từ luồng SSE App Phụ sang `ChatProvider` của App Chính.
class RemoteChatSyncEvent {
  final String sessionId;
  final RemoteChatSyncType type;
  final String? userMessage;
  final String? model;
  final List<AttachmentItem>? attachments;
  final String? token;
  final String? status;
  final ToolExecutionItem? tool;
  final String? reply;
  final String? error;

  const RemoteChatSyncEvent({
    required this.sessionId,
    required this.type,
    this.userMessage,
    this.model,
    this.attachments,
    this.token,
    this.status,
    this.tool,
    this.reply,
    this.error,
  });
}

/// Trạng thái snapshot của một phiên chat đang được App Phụ hỏi Agent trên App Chính.
class RemoteChatLiveSnapshot {
  final String sessionId;
  final String userMessage;
  final String model;
  final List<AttachmentItem>? attachments;
  String content;
  String status;
  final List<ToolExecutionItem> toolExecutions;

  RemoteChatLiveSnapshot({
    required this.sessionId,
    required this.userMessage,
    required this.model,
    this.attachments,
    this.content = '',
    this.status = 'App Phụ đang hỏi Agent...',
    List<ToolExecutionItem>? toolExecutions,
  }) : toolExecutions = toolExecutions ?? [];
}

/// Một kết nối SSE đang lắng nghe tiến độ luồng chat từ App Phụ (ban đầu qua POST /api/chat hoặc nối lại qua GET /api/chat/live).
class _RemoteSseSubscriber {
  final String clientId;
  final HttpResponse response;
  final Completer<void> done = Completer<void>();
  bool closed = false;
  Timer? keepAliveTimer;

  _RemoteSseSubscriber(this.clientId, this.response) {
    keepAliveTimer = Timer.periodic(const Duration(seconds: 15), (t) {
      if (closed) {
        t.cancel();
        return;
      }
      try {
        response.write(': ping\n\n');
      } catch (_) {
        detach();
      }
    });
  }

  void sendEvent(Map<String, dynamic> payload) {
    if (closed) return;
    try {
      response.write('data: ${jsonEncode(payload)}\n\n');
    } catch (_) {
      detach();
    }
  }

  void detach() {
    if (closed) return;
    closed = true;
    keepAliveTimer?.cancel();
    if (!done.isCompleted) done.complete();
  }

  Future<void> finishAndClose() async {
    if (closed) return;
    closed = true;
    keepAliveTimer?.cancel();
    try {
      response.write('data: [DONE]\n\n');
      await response.flush();
      await response.close();
    } catch (_) {}
    if (!done.isCompleted) done.complete();
  }
}

/// Máy chủ HTTP / SSE / WebSocket nhúng trong **App Chính (Primary)**.
/// Khi được bật, mọi thiết bị **App Phụ (Secondary)** có đúng Mã ghép nối (Pairing Token)
/// có thể kết nối từ xa để đồng bộ và điều khiển trực tiếp App Chính:
/// - Quản lý cuộc hội thoại & gửi prompt chạy Agent CLI / AI Model ngay trên máy App Chính (stream SSE).
/// - Xem & chỉnh sửa Lịch làm việc (Work Schedules) trong SQLite của App Chính.
/// - Duyệt thư mục Scope & tải tệp đính kèm lên máy App Chính.
/// - Quản lý máy chủ SSH, cấu hình AI, thông số hệ thống & logs của App Chính.
/// - Mở phiên Terminal tương tác trực tiếp trên máy App Chính qua WebSocket PTY (`/ws/terminal`).
class PrimaryHostServerService {
  static final PrimaryHostServerService instance = PrimaryHostServerService._internal();
  factory PrimaryHostServerService() => instance;

  PrimaryHostServerService._internal({
    DatabaseService? databaseService,
    LocalConfigService? localConfigService,
    NativeAiService? nativeAiService,
    NativeSshService? nativeSshService,
    CliScannerService? cliScannerService,
  })  : _db = databaseService ?? DatabaseService(),
        _config = localConfigService ?? LocalConfigService(),
        _ai = nativeAiService ?? NativeAiService(),
        _ssh = nativeSshService ?? NativeSshService(),
        _cliScanner = cliScannerService ?? CliScannerService();

  /// Khởi tạo instance riêng phục vụ kiểm thử tích hợp tự động.
  factory PrimaryHostServerService.forTest({
    required DatabaseService databaseService,
    LocalConfigService? localConfigService,
    NativeAiService? nativeAiService,
    NativeSshService? nativeSshService,
    CliScannerService? cliScannerService,
  }) {
    return PrimaryHostServerService._internal(
      databaseService: databaseService,
      localConfigService: localConfigService,
      nativeAiService: nativeAiService,
      nativeSshService: nativeSshService,
      cliScannerService: cliScannerService,
    );
  }

  final DatabaseService _db;
  final LocalConfigService _config;
  final NativeAiService _ai;
  final NativeSshService _ssh;
  final CliScannerService _cliScanner;

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  int _boundPort = 0;
  String _token = '';
  String _deviceName = '';
  String _publicUrl = '';
  String _secondaryWorkspacesRoot = '';
  String? _lastError;
  int _activeTerminalSockets = 0;

  final Map<String, StreamSubscription<String>> _activeChatStreams = {};
  final Map<String, Future<void> Function(String reason)> _activeChatStoppers = {};
  final Map<String, RemoteChatLiveSnapshot> _activeRemoteChatSnapshots = {};
  final Map<String, Set<_RemoteSseSubscriber>> _chatSseSubscribers = {};
  final Map<String, String> _activeChatClientIds = {};
  final Map<String, ConnectedSecondaryClient> _connectedClients = {};
  final Map<String, String> _clientWorkspaceDirs = {};
  final Set<String> _revokedClientIds = {};
  final Map<String, Set<WebSocket>> _clientTerminalSockets = {};
  final Map<String, DateTime> _lastClientEmitAt = {};
  Timer? _clientPresenceTimer;
  final Map<String, PendingPairingRequest> _pairingRequests = {};
  final StreamController<String> _mutationController = StreamController<String>.broadcast();
  final StreamController<RemoteChatSyncEvent> _remoteChatSyncController =
      StreamController<RemoteChatSyncEvent>.broadcast();
  final StreamController<List<ConnectedSecondaryClient>> _clientsChangedController =
      StreamController<List<ConnectedSecondaryClient>>.broadcast();
  final StreamController<PendingPairingRequest> _pairingRequestController =
      StreamController<PendingPairingRequest>.broadcast();

  /// Callback do `ChatProvider` trên App Chính đăng ký để kiểm tra phiên nào đang chạy cục bộ.
  bool Function(String sessionId)? isLocalSessionGenerating;

  bool get isRunning => _server != null;
  int get boundPort => _boundPort;
  String get token => _token;
  String get deviceName => _deviceName;
  String get publicUrl => _publicUrl;
  String get secondaryWorkspacesRoot => _secondaryWorkspacesRoot;
  String? get lastError => _lastError;
  int get activeTerminalCount => _activeTerminalSockets;
  int get activeChatCount => _activeChatStreams.length;

  /// Lấy đường dẫn thư mục làm việc đã cấp cho một `clientId` cụ thể (nếu đang bật thư mục gốc).
  String? getClientWorkspaceDir(String clientId) => _clientWorkspaceDirs[clientId];

  /// Kiểm tra đường dẫn `candidate` có nằm gọn trong thư mục `root` hay không (chống path traversal `..`).
  static bool isPathWithinRoot(String candidate, String root) {
    final normRoot = p.normalize(p.absolute(root));
    final normCandidate = p.normalize(p.absolute(candidate));
    if (normCandidate == normRoot) return true;
    return p.isWithin(normRoot, normCandidate);
  }

  static String _stripVietnameseDiacritics(String input) {
    const map = <String, String>{
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
    };
    final buf = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  static String _shortClientSuffix(String clientId) {
    final clean = clientId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return 'client';
    return clean.length > 8 ? clean.substring(clean.length - 8) : clean;
  }

  /// Tạo tên thư mục con dễ đọc và không trùng lặp cho một thiết bị App Phụ.
  static String buildClientWorkspaceFolderName(String clientId, String deviceName) {
    final asciiName = _stripVietnameseDiacritics(deviceName.trim());
    var slug = asciiName
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.length > 28) {
      slug = slug.substring(0, 28).replaceAll(RegExp(r'_+$'), '');
    }
    if (slug.isEmpty) slug = 'app_phu';
    final suffix = _shortClientSuffix(clientId);
    if (slug.endsWith('_$suffix') || slug == suffix) {
      return slug;
    }
    return '${slug}_$suffix';
  }

  static String _expandWorkspaceRoot(String? raw) {
    var pathStr = (raw ?? '').trim();
    if (pathStr.isEmpty) return '';
    if (pathStr == '~' || pathStr.startsWith('~/') || pathStr.startsWith('~\\')) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      if (home.isNotEmpty) {
        pathStr = pathStr == '~' ? home : p.join(home, pathStr.substring(2));
      }
    }
    return p.normalize(p.absolute(pathStr));
  }

  /// Đảm bảo mỗi thiết bị App Phụ (`clientId`) có một thư mục làm việc riêng bền vững bên trong `_secondaryWorkspacesRoot`.
  String _ensureClientWorkspaceDir(String clientId, String deviceName) {
    if (_secondaryWorkspacesRoot.isEmpty) return '';
    final cleanId = clientId.trim();
    if (cleanId.isEmpty) return '';

    final cached = _clientWorkspaceDirs[cleanId];
    if (cached != null && cached.isNotEmpty && isPathWithinRoot(cached, _secondaryWorkspacesRoot)) {
      try {
        final d = Directory(cached);
        if (!d.existsSync()) d.createSync(recursive: true);
        return cached;
      } catch (_) {}
    }

    try {
      final rootDir = Directory(_secondaryWorkspacesRoot);
      if (!rootDir.existsSync()) {
        rootDir.createSync(recursive: true);
      }
      // Tái sử dụng thư mục đã tồn tại cùng hậu tố `_<shortId>` (giữ nguyên workspace khi đổi tên máy hoặc khởi động lại App Chính)
      final suffix = _shortClientSuffix(cleanId);
      final suffixTag = '_$suffix';
      for (final entity in rootDir.listSync(followLinks: false)) {
        if (entity is Directory) {
          final base = p.basename(entity.path).toLowerCase();
          if (base == suffix || base.endsWith(suffixTag)) {
            final existingPath = p.normalize(p.absolute(entity.path));
            _clientWorkspaceDirs[cleanId] = existingPath;
            return existingPath;
          }
        }
      }

      final folderName = buildClientWorkspaceFolderName(cleanId, deviceName);
      final targetPath = p.normalize(p.join(_secondaryWorkspacesRoot, folderName));
      final targetDir = Directory(targetPath);
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }
      _clientWorkspaceDirs[cleanId] = targetPath;
      return targetPath;
    } catch (_) {
      return '';
    }
  }

  /// Ràng buộc đường dẫn làm việc của App Phụ nằm gọn trong thư mục riêng của thiết bị đó (nếu đã cấu hình).
  String? _resolveClientScopedPath(String clientWorkspaceDir, String? requestedPath) {
    if (clientWorkspaceDir.isEmpty) return requestedPath;
    final raw = (requestedPath ?? '').trim();
    if (raw.isEmpty) return clientWorkspaceDir;
    var candidate = raw;
    if (candidate == '~' || candidate.startsWith('~/') || candidate.startsWith('~\\')) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      if (home.isNotEmpty) {
        candidate = candidate == '~' ? home : p.join(home, candidate.substring(2));
      }
    }
    final resolved = p.isAbsolute(candidate)
        ? p.normalize(candidate)
        : p.normalize(p.join(clientWorkspaceDir, candidate));
    if (isPathWithinRoot(resolved, clientWorkspaceDir)) {
      return resolved;
    }
    return clientWorkspaceDir;
  }

  void _applyWorkspacesRoot(String? rawRoot) {
    final normalized = _expandWorkspaceRoot(rawRoot);
    if (normalized == _secondaryWorkspacesRoot) return;
    _secondaryWorkspacesRoot = normalized;
    _clientWorkspaceDirs.clear();
    if (_secondaryWorkspacesRoot.isNotEmpty) {
      try {
        final rootDir = Directory(_secondaryWorkspacesRoot);
        if (!rootDir.existsSync()) {
          rootDir.createSync(recursive: true);
        }
      } catch (_) {}
    }
    for (final c in _connectedClients.values) {
      c.workspaceDir = _ensureClientWorkspaceDir(c.clientId, c.deviceName);
    }
    _emitClientsChanged();
  }

  /// Danh sách các thiết bị App Phụ đang kết nối / đã nhận diện trên App Chính.
  List<ConnectedSecondaryClient> get connectedClients {
    final list = _connectedClients.values.map((c) => c.copySnapshot()).toList();
    list.sort((a, b) {
      if (a.isRevoked != b.isRevoked) return a.isRevoked ? 1 : -1;
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return b.lastSeenAt.compareTo(a.lastSeenAt);
    });
    return list;
  }

  /// Số thiết bị App Phụ đang online thực tế.
  int get onlineClientCount => _connectedClients.values.where((c) => c.isOnline).length;

  /// Tập hợp ID các thiết bị đã bị thu hồi quyền truy cập.
  Set<String> get revokedClientIds => Set<String>.unmodifiable(_revokedClientIds);

  /// Phát sự kiện khi danh sách hoặc trạng thái thiết bị App Phụ thay đổi.
  Stream<List<ConnectedSecondaryClient>> get onConnectedClientsChanged =>
      _clientsChangedController.stream;

  void _emitClientsChanged() {
    if (!_clientsChangedController.isClosed) {
      _clientsChangedController.add(connectedClients);
    }
  }

  /// Nạp lại danh sách thiết bị đã bị thu hồi từ bộ nhớ cục bộ khi khởi động App Chính.
  void loadRevokedClientIds(Iterable<String> ids) {
    _revokedClientIds
      ..clear()
      ..addAll(ids.map((e) => e.trim()).where((e) => e.isNotEmpty));
    for (final c in _connectedClients.values) {
      c.isRevoked = _revokedClientIds.contains(c.clientId);
    }
    _emitClientsChanged();
  }

  /// Xóa toàn bộ danh sách thiết bị bị thu hồi (dùng khi tạo Pairing Token hoàn toàn mới).
  void clearRevokedClients() {
    _revokedClientIds.clear();
    _connectedClients.removeWhere((_, c) => c.isRevoked);
    _emitClientsChanged();
  }

  void _recomputeClientActivity(String clientId) {
    final client = _connectedClients[clientId];
    if (client == null) return;
    final chats = _activeChatClientIds.values.where((id) => id == clientId).length;
    final terms = _clientTerminalSockets[clientId]?.length ?? 0;
    final changed = client.activeChats != chats || client.activeTerminals != terms;
    client.activeChats = chats;
    client.activeTerminals = terms;
    if (changed) {
      _emitClientsChanged();
    }
  }

  ({String clientId, String deviceName, String os, String ip}) _extractClientInfo(HttpRequest req) {
    final rawIp = (req.headers.value('cf-connecting-ip') ??
            req.headers.value('x-forwarded-for')?.split(',').first ??
            req.connectionInfo?.remoteAddress.address ??
            'unknown')
        .trim();
    final ip = rawIp.isEmpty ? 'unknown' : rawIp;

    final rawId = (req.headers.value('x-client-id') ?? req.uri.queryParameters['client_id'] ?? '').trim();
    final clientId = rawId.isNotEmpty ? rawId : 'ip:$ip';

    String rawName = (req.headers.value('x-client-name') ?? req.uri.queryParameters['client_name'] ?? '').trim();
    if (rawName.isNotEmpty) {
      try {
        rawName = Uri.decodeComponent(rawName);
      } catch (_) {}
    }
    final rawOs = (req.headers.value('x-client-os') ?? req.uri.queryParameters['client_os'] ?? '').trim();
    final os = rawOs.isNotEmpty ? rawOs : 'unknown';
    final deviceName = rawName.isNotEmpty
        ? rawName
        : (os.toLowerCase() == 'android'
            ? 'Điện thoại Android ($ip)'
            : (os.toLowerCase() == 'ios' ? 'Thiết bị iOS ($ip)' : 'App Phụ ($ip)'));
    return (clientId: clientId, deviceName: deviceName, os: os, ip: ip);
  }

  void _touchClient(({String clientId, String deviceName, String os, String ip}) info) {
    final now = DateTime.now();
    final workspaceDir = _ensureClientWorkspaceDir(info.clientId, info.deviceName);
    final existing = _connectedClients[info.clientId];
    if (existing == null) {
      _connectedClients[info.clientId] = ConnectedSecondaryClient(
        clientId: info.clientId,
        deviceName: info.deviceName,
        os: info.os,
        ip: info.ip,
        workspaceDir: workspaceDir,
        connectedAt: now,
        lastSeenAt: now,
        isRevoked: false,
      );
      _lastClientEmitAt[info.clientId] = now;
      _emitClientsChanged();
      return;
    }

    final wasOnline = existing.isOnline;
    final metaChanged = existing.deviceName != info.deviceName ||
        existing.os != info.os ||
        existing.ip != info.ip ||
        existing.workspaceDir != workspaceDir ||
        existing.isRevoked;
    existing.deviceName = info.deviceName;
    existing.os = info.os;
    existing.ip = info.ip;
    existing.workspaceDir = workspaceDir;
    existing.isRevoked = false;
    existing.lastSeenAt = now;

    final lastEmit = _lastClientEmitAt[info.clientId];
    if (!wasOnline || metaChanged || lastEmit == null || now.difference(lastEmit) >= const Duration(seconds: 5)) {
      _lastClientEmitAt[info.clientId] = now;
      _emitClientsChanged();
    }
  }

  /// Ngắt kết nối ngay lập tức một thiết bị App Phụ cụ thể (đóng Terminal WS + hủy Chat SSE + thu hồi quyền nếu `revoke == true`).
  Future<void> disconnectClient(String clientId, {bool revoke = true}) async {
    final cleanId = clientId.trim();
    if (cleanId.isEmpty) return;

    if (revoke) {
      _revokedClientIds.add(cleanId);
      final existing = _connectedClients[cleanId];
      if (existing != null) {
        existing.isRevoked = true;
      }
    }

    // 1. Dừng mọi luồng Chat SSE mà thiết bị này đang chạy
    final sessionsToStop = _activeChatClientIds.entries
        .where((e) => e.value == cleanId)
        .map((e) => e.key)
        .toList();
    for (final sId in sessionsToStop) {
      await stopActiveChat(
        sId,
        reason: revoke
            ? 'Thiết bị này đã bị ngắt kết nối khỏi App Chính.'
            : 'App Phụ đã ngắt kết nối.',
      );
    }

    // 1b. Đóng cả các kết nối SSE quan sát (/api/chat/live) của riêng thiết bị này
    for (final subs in _chatSseSubscribers.values) {
      for (final s in subs.where((e) => e.clientId == cleanId).toList()) {
        s.sendEvent({
          'type': 'error',
          'message': revoke
              ? 'Thiết bị này đã bị ngắt kết nối khỏi App Chính.'
              : 'App Phụ đã ngắt kết nối.',
        });
        await s.finishAndClose();
        subs.remove(s);
      }
    }

    // 2. Đóng toàn bộ WebSocket Terminal của riêng thiết bị này
    final sockets = _clientTerminalSockets.remove(cleanId);
    if (sockets != null) {
      for (final ws in sockets.toList()) {
        try {
          if (ws.readyState == WebSocket.open) {
            ws.add('\r\n\x1b[31m[Thiết bị này đã bị ngắt kết nối từ App Chính]\x1b[0m\r\n');
          }
          await ws.close(WebSocketStatus.policyViolation, 'DEVICE_REVOKED');
        } catch (_) {}
      }
    }

    if (!revoke) {
      _connectedClients.remove(cleanId);
      _lastClientEmitAt.remove(cleanId);
    } else {
      final existing = _connectedClients[cleanId];
      if (existing != null) {
        existing.activeChats = 0;
        existing.activeTerminals = 0;
      }
    }
    _emitClientsChanged();
  }

  /// Cho phép lại một thiết bị App Phụ trước đó đã bị ngắt kết nối.
  void restoreClient(String clientId) {
    final cleanId = clientId.trim();
    if (cleanId.isEmpty) return;
    _revokedClientIds.remove(cleanId);
    _connectedClients.remove(cleanId);
    _lastClientEmitAt.remove(cleanId);
    _emitClientsChanged();
  }

  /// Kiểm tra một phiên hội thoại có đang được App Phụ hỏi Agent hay không.
  bool isRemoteSessionGenerating(String? sessionId) =>
      sessionId != null && _activeChatStreams.containsKey(sessionId);

  /// Kiểm tra một phiên hội thoại có đang bận (từ App Phụ hoặc cục bộ trên App Chính) hay không.
  bool isSessionBusy(String sessionId) =>
      _activeChatStreams.containsKey(sessionId) ||
      (isLocalSessionGenerating?.call(sessionId) == true);

  /// Danh sách ID các phiên đang có App Phụ chạy Agent.
  Set<String> get activeRemoteSessionIds => _activeChatStreams.keys.toSet();

  /// Lấy snapshot live của phiên đang chạy từ App Phụ (phục vụ khi App Chính mới chuyển vào phiên giữa chừng).
  RemoteChatLiveSnapshot? getActiveRemoteChatSnapshot(String sessionId) =>
      _activeRemoteChatSnapshots[sessionId];

  /// Phát sự kiện khi App Phụ thay đổi dữ liệu trên App Chính để UI App Chính tự làm mới.
  Stream<String> get onRemoteMutation => _mutationController.stream;

  /// Phát sự kiện trực tiếp vòng đời luồng chat từ App Phụ để App Chính đồng bộ loading và khóa nhập trùng.
  Stream<RemoteChatSyncEvent> get onRemoteChatSync => _remoteChatSyncController.stream;

  /// Phát sự kiện khi có App Phụ gửi yêu cầu ghép nối 1 chạm chờ người dùng phê duyệt trên App Chính.
  Stream<PendingPairingRequest> get onPairingRequest => _pairingRequestController.stream;

  void _emitRemoteChatSync(RemoteChatSyncEvent event) {
    if (!_remoteChatSyncController.isClosed) {
      _remoteChatSyncController.add(event);
    }
  }

  /// Dừng luồng AI mà App Phụ đang chạy cho `sessionId` (có thể gọi từ nút Dừng trên App Chính hoặc `/api/chat/stop`).
  Future<void> stopActiveChat(
    String sessionId, {
    String reason = 'Đã dừng phản hồi.',
  }) async {
    final stopper = _activeChatStoppers.remove(sessionId);
    if (stopper != null) {
      await stopper(reason);
      return;
    }
    final existing = _activeChatStreams.remove(sessionId);
    _activeRemoteChatSnapshots.remove(sessionId);
    if (existing != null) {
      try {
        await existing.cancel();
      } catch (_) {}
      if (!sessionId.startsWith('schedule_')) {
        _emitRemoteChatSync(
          RemoteChatSyncEvent(
            sessionId: sessionId,
            type: RemoteChatSyncType.stop,
            reply: reason,
          ),
        );
        _emitMutation('chat:$sessionId');
      }
    }
  }

  /// Phê duyệt yêu cầu ghép nối 1 chạm từ App Phụ.
  void approvePairingRequest(String requestId) {
    final req = _pairingRequests[requestId];
    if (req != null && !req.isExpired && req.status == 'pending') {
      req.status = 'approved';
      if (req.clientId.isNotEmpty && _revokedClientIds.remove(req.clientId)) {
        final existing = _connectedClients[req.clientId];
        if (existing != null) existing.isRevoked = false;
        _emitClientsChanged();
      }
    }
  }

  /// Từ chối yêu cầu ghép nối 1 chạm từ App Phụ.
  void rejectPairingRequest(String requestId) {
    final req = _pairingRequests[requestId];
    if (req != null && req.status == 'pending') {
      req.status = 'rejected';
    }
  }

  void _emitMutation(String topic) {
    if (!_mutationController.isClosed) {
      _mutationController.add(topic);
    }
  }

  /// Kiểm tra tên card mạng có phải interface ảo của Docker/VM/Container hay không.
  static bool isVirtualBridgeInterface(String ifaceName) {
    final name = ifaceName.trim().toLowerCase();
    if (name.isEmpty) return false;
    const ignoredPrefixes = [
      'docker',
      'br-',
      'veth',
      'virbr',
      'cni',
      'flannel',
      'kube',
      'podman',
      'lxc',
      'lxdbr',
      'vmnet',
      'vboxnet',
      'cali',
      'cilium',
    ];
    for (final pfx in ignoredPrefixes) {
      if (name.startsWith(pfx)) return true;
    }
    return false;
  }

  /// Kiểm tra IPv4 có thuộc dải CGNAT / Tailscale Mesh VPN (`100.64.0.0/10`) hay không.
  static bool isTailscaleOrCgnatIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final o1 = int.tryParse(parts[0]) ?? -1;
    final o2 = int.tryParse(parts[1]) ?? -1;
    return o1 == 100 && o2 >= 64 && o2 <= 127;
  }

  /// Phân tách rõ IP LAN vật lý và IP VPN Mesh (Tailscale/WireGuard/ZeroTier), loại bỏ toàn bộ bridge Docker.
  static Future<({List<String> lanIps, List<String> vpnIps})> getNetworkEndpoints() async {
    final lanIps = <String>[];
    final vpnIps = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (isVirtualBridgeInterface(iface.name)) continue;
        final lowerName = iface.name.toLowerCase();
        final isVpnIface = lowerName.startsWith('tailscale') ||
            lowerName.startsWith('wg') ||
            lowerName.startsWith('zt') ||
            lowerName.startsWith('utun') ||
            lowerName.startsWith('tun');
        for (final addr in iface.addresses) {
          final ip = addr.address.trim();
          if (ip.isEmpty || ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          if (isVpnIface || isTailscaleOrCgnatIp(ip)) {
            if (!vpnIps.contains(ip)) vpnIps.add(ip);
          } else {
            if (!lanIps.contains(ip)) lanIps.add(ip);
          }
        }
      }
      int scoreLan(String ip) {
        if (ip.startsWith('192.168.')) return 0;
        if (ip.startsWith('10.')) return 1;
        if (ip.startsWith('172.')) return 2;
        return 3;
      }
      lanIps.sort((a, b) => scoreLan(a).compareTo(scoreLan(b)));
      vpnIps.sort();
    } catch (_) {}
    return (lanIps: lanIps, vpnIps: vpnIps);
  }

  /// Liệt kê các địa chỉ IPv4 khả dụng (LAN ưu tiên trước, sau đó VPN Mesh; đã lọc bỏ bridge Docker).
  static Future<List<String>> getLocalIpv4Addresses() async {
    final endpoints = await getNetworkEndpoints();
    return [...endpoints.lanIps, ...endpoints.vpnIps];
  }

  /// Quét tự động các máy tính App Chính đang bật trong cùng mạng Wi-Fi / LAN qua UDP Broadcast.
  static Future<List<DiscoveredPrimaryHost>> discoverNearbyHosts({
    Duration timeout = const Duration(milliseconds: 1600),
    int discoveryPort = ApiConstants.discoveryPort,
  }) async {
    final found = <String, DiscoveredPrimaryHost>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        try {
          final text = utf8.decode(dg.data, allowMalformed: true).trim();
          final decoded = jsonDecode(text);
          if (decoded is! Map || decoded['type'] != 'AI_TYPE_HOST_V1') return;
          final port = int.tryParse(decoded['port']?.toString() ?? '') ?? ApiConstants.defaultPrimaryHostPort;
          final senderIp = dg.address.address;
          final lanUrl = (decoded['lan_url']?.toString().trim().isNotEmpty == true)
              ? decoded['lan_url'].toString().trim()
              : 'http://$senderIp:$port';
          final vpnUrl = decoded['vpn_url']?.toString().trim() ?? '';
          final publicUrl = decoded['public_url']?.toString().trim() ?? '';
          final preferredUrl = (decoded['preferred_url']?.toString().trim().isNotEmpty == true)
              ? decoded['preferred_url'].toString().trim()
              : (publicUrl.isNotEmpty ? publicUrl : (vpnUrl.isNotEmpty ? vpnUrl : lanUrl));
          final deviceName = decoded['device_name']?.toString().trim() ?? senderIp;
          final os = decoded['os']?.toString().trim() ?? 'linux';
          final key = '$deviceName|$lanUrl';
          found[key] = DiscoveredPrimaryHost(
            deviceName: deviceName,
            os: os,
            port: port,
            lanUrl: lanUrl,
            vpnUrl: vpnUrl,
            publicUrl: publicUrl,
            preferredUrl: preferredUrl,
          );
        } catch (_) {}
      });

      final probe = utf8.encode(jsonEncode({'type': 'AI_TYPE_DISCOVER_V1'}));
      final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
      // Thêm địa chỉ broadcast trực tiếp cho các subnet LAN (VD 192.168.1.255) để tăng độ ổn định trên Android
      final endpoints = await getNetworkEndpoints();
      for (final ip in endpoints.lanIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final bcast = InternetAddress.tryParse('${parts[0]}.${parts[1]}.${parts[2]}.255');
          if (bcast != null) targets.add(bcast);
        }
      }

      for (var round = 0; round < 2; round++) {
        for (final target in targets) {
          try {
            socket.send(probe, target, discoveryPort);
          } catch (_) {}
        }
        await Future<void>.delayed(Duration(milliseconds: timeout.inMilliseconds ~/ 2));
      }
      await sub.cancel();
    } catch (_) {
    } finally {
      try {
        socket?.close();
      } catch (_) {}
    }
    return found.values.toList();
  }

  Future<void> _startDiscoveryResponder() async {
    await _stopDiscoveryResponder();
    try {
      final sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ApiConstants.discoveryPort,
        reuseAddress: true,
      );
      sock.broadcastEnabled = true;
      _discoverySocket = sock;
      sock.listen((event) async {
        if (event != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null || _server == null) return;
        try {
          final text = utf8.decode(dg.data, allowMalformed: true);
          if (!text.contains('AI_TYPE_DISCOVER_V1')) return;
          final urls = await _resolveAdvertisedUrls();
          final reply = utf8.encode(jsonEncode({
            'type': 'AI_TYPE_HOST_V1',
            'device_name': _deviceName,
            'os': Platform.operatingSystem,
            'port': _boundPort,
            'lan_url': urls.lanUrl,
            'vpn_url': urls.vpnUrl,
            'public_url': urls.publicUrl,
            'preferred_url': urls.preferredUrl,
          }));
          sock.send(reply, dg.address, dg.port);
        } catch (_) {}
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _stopDiscoveryResponder() async {
    final sock = _discoverySocket;
    _discoverySocket = null;
    try {
      sock?.close();
    } catch (_) {}
  }

  Future<({String lanUrl, String vpnUrl, String publicUrl, String preferredUrl})> _resolveAdvertisedUrls() async {
    final endpoints = await getNetworkEndpoints();
    final port = _boundPort > 0 ? _boundPort : ApiConstants.defaultPrimaryHostPort;
    final lanUrl = endpoints.lanIps.isNotEmpty ? 'http://${endpoints.lanIps.first}:$port' : 'http://127.0.0.1:$port';
    final vpnUrl = endpoints.vpnIps.isNotEmpty ? 'http://${endpoints.vpnIps.first}:$port' : '';
    final pubUrl = _publicUrl.trim();
    final preferredUrl = pubUrl.isNotEmpty ? pubUrl : (vpnUrl.isNotEmpty ? vpnUrl : lanUrl);
    return (lanUrl: lanUrl, vpnUrl: vpnUrl, publicUrl: pubUrl, preferredUrl: preferredUrl);
  }

  /// Khởi động máy chủ lắng nghe điều khiển từ xa trên cổng chỉ định (`port: 0` cho phép OS cấp cổng ngẫu nhiên khi test).
  Future<bool> start({
    required int port,
    required String token,
    required String deviceName,
    String? publicUrl,
    String? secondaryWorkspacesRoot,
    InternetAddress? bindAddress,
    bool enableDiscovery = true,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      _lastError = 'Mã ghép nối (Pairing Token) không được để trống.';
      return false;
    }

    if (_server != null && _boundPort == port && port != 0) {
      _token = cleanToken;
      _deviceName = deviceName.trim().isNotEmpty ? deviceName.trim() : 'AI Type Agent';
      if (publicUrl != null) _publicUrl = publicUrl.trim();
      if (secondaryWorkspacesRoot != null) {
        _applyWorkspacesRoot(secondaryWorkspacesRoot);
      }
      _lastError = null;
      if (enableDiscovery && _discoverySocket == null) {
        unawaited(_startDiscoveryResponder());
      }
      return true;
    }

    await stop();
    try {
      final srv = await HttpServer.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        port,
        shared: false,
      );
      _server = srv;
      _boundPort = srv.port;
      _token = cleanToken;
      _deviceName = deviceName.trim().isNotEmpty ? deviceName.trim() : 'AI Type Agent';
      if (publicUrl != null) _publicUrl = publicUrl.trim();
      _applyWorkspacesRoot(secondaryWorkspacesRoot);
      _lastError = null;

      srv.listen(
        _handleRequest,
        onError: (_) {},
      );
      _clientPresenceTimer?.cancel();
      _clientPresenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_connectedClients.isNotEmpty) {
          _emitClientsChanged();
        }
      });
      if (enableDiscovery && bindAddress == null) {
        unawaited(_startDiscoveryResponder());
      }
      return true;
    } catch (e) {
      _lastError = 'Không thể mở cổng $port: $e';
      _server = null;
      _boundPort = 0;
      return false;
    }
  }

  Future<void> stop() async {
    _clientPresenceTimer?.cancel();
    _clientPresenceTimer = null;
    await _stopDiscoveryResponder();
    _pairingRequests.clear();
    final activeIds = _activeChatStreams.keys.toList();
    for (final sId in activeIds) {
      await stopActiveChat(sId, reason: 'Máy chủ điều khiển từ xa đã dừng.');
    }
    for (final sockets in _clientTerminalSockets.values) {
      for (final ws in sockets.toList()) {
        try {
          await ws.close();
        } catch (_) {}
      }
    }
    for (final sId in _chatSseSubscribers.keys.toList()) {
      await _closeChatSseSubscribers(sId);
    }
    _chatSseSubscribers.clear();
    _activeChatStreams.clear();
    _activeChatStoppers.clear();
    _activeRemoteChatSnapshots.clear();
    _activeChatClientIds.clear();
    _clientTerminalSockets.clear();
    _connectedClients.clear();
    _clientWorkspaceDirs.clear();
    _lastClientEmitAt.clear();
    _emitClientsChanged();
    final srv = _server;
    _server = null;
    _boundPort = 0;
    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
    }
  }

  void updateRuntimeMetadata({
    String? token,
    String? deviceName,
    String? publicUrl,
    String? secondaryWorkspacesRoot,
  }) {
    if (token != null && token.trim().isNotEmpty) {
      _token = token.trim();
    }
    if (deviceName != null && deviceName.trim().isNotEmpty) {
      _deviceName = deviceName.trim();
    }
    if (publicUrl != null) {
      _publicUrl = publicUrl.trim();
    }
    if (secondaryWorkspacesRoot != null) {
      _applyWorkspacesRoot(secondaryWorkspacesRoot);
    }
  }

  bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ab.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }

  bool _isAuthorized(HttpRequest req) {
    if (_token.isEmpty) return false;
    final authHeader = req.headers.value(HttpHeaders.authorizationHeader)?.trim() ?? '';
    String candidate = '';
    if (authHeader.toLowerCase().startsWith('bearer ')) {
      candidate = authHeader.substring(7).trim();
    } else if (req.headers.value('x-secret-token') != null) {
      candidate = req.headers.value('x-secret-token')!.trim();
    } else if (req.uri.queryParameters['token'] != null) {
      candidate = req.uri.queryParameters['token']!.trim();
    }
    if (candidate.isEmpty) return false;
    return _constantTimeEquals(candidate, _token);
  }

  void _setCorsHeaders(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Secret-Token, X-User-Email, X-User-Name, X-Client-Id, X-Client-Name, X-Client-OS',
    );
  }

  Future<void> _sendJson(HttpResponse res, int statusCode, Object body) async {
    res.statusCode = statusCode;
    res.headers.contentType = ContentType.json;
    _setCorsHeaders(res);
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest req) async {
    try {
      final raw = await utf8.decoder.bind(req).join();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final res = req.response;
    _setCorsHeaders(res);

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final path = req.uri.path;
    final method = req.method.toUpperCase();

    // 0. Luồng yêu cầu & phê duyệt ghép nối 1 chạm (không cần token sẵn, bắt buộc người dùng bấm Chấp nhận trên PC)
    if (method == 'POST' && path == ApiConstants.epPairRequest) {
      _pairingRequests.removeWhere((_, v) => v.isExpired);
      if (_pairingRequests.length >= 10) {
        await _sendJson(res, HttpStatus.tooManyRequests, {
          'error': 'Quá nhiều yêu cầu ghép nối đang chờ. Hãy thử lại sau ít giây.',
        });
        return;
      }
      final body = await _readJsonBody(req);
      final reqClientId = (body['client_id']?.toString() ?? req.headers.value('x-client-id') ?? '').trim();
      final clientName = body['device_name']?.toString().trim();
      final clientOs = body['os']?.toString().trim();
      final rng = Random.secure();
      final reqId = List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      final pin = (100000 + rng.nextInt(900000)).toString();
      final clientIp = req.connectionInfo?.remoteAddress.address ?? 'unknown';

      final pending = PendingPairingRequest(
        id: reqId,
        clientId: reqClientId,
        clientDeviceName: (clientName != null && clientName.isNotEmpty) ? clientName : 'Thiết bị App Phụ',
        clientOs: (clientOs != null && clientOs.isNotEmpty) ? clientOs : 'mobile',
        clientIp: clientIp,
        pin: pin,
        createdAt: DateTime.now(),
      );
      _pairingRequests[reqId] = pending;
      if (!_pairingRequestController.isClosed) {
        _pairingRequestController.add(pending);
      }
      await _sendJson(res, HttpStatus.ok, {
        'ok': true,
        'request_id': reqId,
        'pin': pin,
        'device_name': _deviceName,
        'expires_in': 60,
      });
      return;
    }

    if (method == 'GET' && path == ApiConstants.epPairStatus) {
      final reqId = req.uri.queryParameters['id']?.trim() ?? '';
      final pending = _pairingRequests[reqId];
      if (pending == null || pending.isExpired) {
        _pairingRequests.remove(reqId);
        await _sendJson(res, HttpStatus.ok, {'status': 'expired'});
        return;
      }
      if (pending.status == 'rejected') {
        _pairingRequests.remove(reqId);
        await _sendJson(res, HttpStatus.ok, {'status': 'rejected'});
        return;
      }
      if (pending.status == 'approved') {
        // Chỉ cấp token đúng 1 lần duy nhất rồi xóa ngay yêu cầu ghép nối
        _pairingRequests.remove(reqId);
        final urls = await _resolveAdvertisedUrls();
        await _sendJson(res, HttpStatus.ok, {
          'status': 'approved',
          'token': _token,
          'device_name': _deviceName,
          'preferred_url': urls.preferredUrl,
          'lan_url': urls.lanUrl,
          'vpn_url': urls.vpnUrl,
          'public_url': urls.publicUrl,
        });
        return;
      }
      await _sendJson(res, HttpStatus.ok, {'status': 'pending'});
      return;
    }

    if (!_isAuthorized(req)) {
      await _sendJson(res, HttpStatus.unauthorized, {
        'error': 'Unauthorized',
        'message': 'Mã ghép nối (Pairing Token) không hợp lệ hoặc bị thiếu.',
      });
      return;
    }

    final clientInfo = _extractClientInfo(req);

    // App Phụ tự báo ngắt kết nối sạch sẽ
    if (method == 'POST' && path == ApiConstants.epRemoteDisconnect) {
      await disconnectClient(clientInfo.clientId, revoke: false);
      await _sendJson(res, HttpStatus.ok, {'ok': true});
      return;
    }

    // Chặn thiết bị App Phụ đã bị App Chính ngắt kết nối riêng lẻ
    if (_revokedClientIds.contains(clientInfo.clientId)) {
      await _sendJson(res, HttpStatus.unauthorized, {
        'error': 'DEVICE_REVOKED',
        'code': 'DEVICE_REVOKED',
        'message': 'Thiết bị này đã bị ngắt kết nối từ App Chính.',
      });
      return;
    }

    _touchClient(clientInfo);
    final clientWorkspaceDir = _ensureClientWorkspaceDir(clientInfo.clientId, clientInfo.deviceName);

    try {
      // 1. WebSocket Terminal trực tiếp trên App Chính
      if (path == ApiConstants.wsTerminal) {
        await _handleTerminalWebSocket(req, clientInfo.clientId, clientWorkspaceDir: clientWorkspaceDir);
        return;
      }

      // 2. Handshake & Thông tin thiết bị App Chính
      if (method == 'GET' && path == ApiConstants.epRemoteInfo) {
        final cfg = await _config.loadConfig();
        final sessions = await _db.getSessions();
        final cliAgents = await _cliScanner.scanInstalledAgents();
        await _sendJson(res, HttpStatus.ok, {
          'ok': true,
          'role': 'primary',
          'device_name': _deviceName,
          'os': Platform.operatingSystem,
          'app_version': '1.5.10',
          'port': _boundPort,
          'active_model': cfg['active_agent_engine']?.toString() ?? cfg['ai_model']?.toString() ?? 'glm-5.3',
          'sessions_count': sessions.length,
          'cli_agents_count': cliAgents.length,
          'online_clients_count': onlineClientCount,
          'workspaces_root': _secondaryWorkspacesRoot,
          'client_workspace_dir': clientWorkspaceDir,
        });
        return;
      }

      // 3. Danh sách CLI Agents cục bộ trên App Chính
      if (method == 'GET' && path == ApiConstants.epModels) {
        final cfg = await _config.loadConfig();
        final cliAgents = await _cliScanner.scanInstalledAgents();
        await _sendJson(res, HttpStatus.ok, {
          'active_model': cfg['active_agent_engine']?.toString() ?? cfg['ai_model']?.toString() ?? 'glm-5.3',
          'provider_tab': cfg['ai_provider_tab']?.toString() ?? 'proxy',
          'cli_agents': cliAgents
              .map((a) => {
                    'id': a.id,
                    'binary': a.binary,
                    'path': a.path,
                    'label': a.label,
                    if (a.version != null) 'version': a.version,
                  })
              .toList(),
        });
        return;
      }

      // 4. Cấu hình AI & Hệ thống
      if (path == ApiConstants.epConfig) {
        if (method == 'GET') {
          final cfg = await _config.loadConfig();
          await _sendJson(res, HttpStatus.ok, cfg);
          return;
        }
        if (method == 'POST') {
          final body = await _readJsonBody(req);
          final ok = await _config.saveConfig(body);
          if (ok) _emitMutation('config');
          await _sendJson(res, ok ? HttpStatus.ok : HttpStatus.internalServerError, {'ok': ok});
          return;
        }
      }

      // 5. Quản lý Máy chủ SSH
      if (method == 'GET' && path == ApiConstants.epServers) {
        final servers = await _config.getServers();
        await _sendJson(res, HttpStatus.ok, {
          'servers': servers.map((s) => s.toJson()).toList(),
        });
        return;
      }
      if (method == 'POST' && path == ApiConstants.epServersSelect) {
        final body = await _readJsonBody(req);
        final serverIp = body['server_ip']?.toString() ?? '';
        final servers = await _config.getServers();
        final target = servers.firstWhere(
          (s) => s.serverIp == serverIp || s.id == serverIp || s.name == serverIp,
          orElse: () => ServerModel(id: serverIp, name: serverIp, serverIp: serverIp),
        );
        final ok = await _config.selectServer(target);
        if (ok) _emitMutation('servers');
        await _sendJson(res, HttpStatus.ok, {'ok': ok});
        return;
      }
      if (method == 'POST' && path == ApiConstants.epServersUpdate) {
        final body = await _readJsonBody(req);
        final srv = ServerModel.fromJson(body);
        final ok = await _config.addOrUpdateServer(srv);
        if (ok) _emitMutation('servers');
        await _sendJson(res, HttpStatus.ok, {'ok': ok});
        return;
      }
      if (method == 'POST' && path == ApiConstants.epServersDelete) {
        final body = await _readJsonBody(req);
        final serverIp = body['server_ip']?.toString() ?? '';
        final ok = await _config.deleteServer(serverIp);
        if (ok) _emitMutation('servers');
        await _sendJson(res, HttpStatus.ok, {'ok': ok});
        return;
      }

      // 6. Quản lý Cuộc hội thoại (Chat Sessions)
      if (path == ApiConstants.epChatSessions) {
        if (method == 'GET') {
          final sessions = await _db.getSessions();
          await _sendJson(res, HttpStatus.ok, {
            'sessions': sessions.map((s) => s.toJson()).toList(),
          });
          return;
        }
        if (method == 'POST') {
          final body = await _readJsonBody(req);
          List<String>? targetServers;
          if (body['target_servers'] is List) {
            targetServers = (body['target_servers'] as List).map((e) => e.toString()).toList();
          } else if (body['target_servers'] is String) {
            try {
              final decoded = jsonDecode(body['target_servers'] as String);
              if (decoded is List) {
                targetServers = decoded.map((e) => e.toString()).toList();
              }
            } catch (_) {}
          }
          final effectiveWorkingDir = _resolveClientScopedPath(
            clientWorkspaceDir,
            body['working_dir']?.toString(),
          );
          final created = await _db.createSession(
            title: body['title']?.toString() ?? 'Cuộc hội thoại mới',
            workingDir: effectiveWorkingDir,
            targetServer: body['target_server']?.toString(),
            targetServers: targetServers,
          );
          _emitMutation('sessions');
          await _sendJson(res, HttpStatus.ok, created.toJson());
          return;
        }
        if (method == 'DELETE') {
          final ok = await _db.deleteAllSessions();
          _emitMutation('sessions');
          await _sendJson(res, HttpStatus.ok, {'ok': ok});
          return;
        }
      }

      if (path.startsWith('${ApiConstants.epChatSessions}/')) {
        final sub = path.substring('${ApiConstants.epChatSessions}/'.length);
        final segments = sub.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          final sessionId = Uri.decodeComponent(segments[0]);
          if (segments.length == 1) {
            if (method == 'PUT') {
              final body = await _readJsonBody(req);
              final ok = await _db.updateSessionTitle(sessionId, body['title']?.toString() ?? '');
              _emitMutation('sessions');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
            if (method == 'DELETE') {
              final ok = await _db.deleteSession(sessionId);
              _emitMutation('sessions');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
          } else if (segments.length == 2 && method == 'POST') {
            final action = segments[1];
            final body = await _readJsonBody(req);
            if (action == 'pin') {
              final isPinned = body.containsKey('is_pinned') ? (body['is_pinned'] == true) : null;
              final ok = await _db.togglePinSession(sessionId, isPinned: isPinned);
              _emitMutation('sessions');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
            if (action == 'scope') {
              final rawScope = body['working_dir']?.toString();
              final scope = _resolveClientScopedPath(clientWorkspaceDir, rawScope);
              List<String>? docFiles;
              if (body['doc_files'] is List) {
                docFiles = (body['doc_files'] as List).map((e) => e.toString()).toList();
              }
              final ok = await _db.updateSessionScope(sessionId, scope, docFiles: docFiles);
              _emitMutation('sessions');
              await _sendJson(res, HttpStatus.ok, {'ok': ok, 'working_dir': scope});
              return;
            }
            if (action == 'server') {
              final targetServer = body['target_server']?.toString();
              List<String>? targetServers;
              if (body['target_servers'] is List) {
                targetServers = (body['target_servers'] as List).map((e) => e.toString()).toList();
              }
              final ok = await _db.updateSessionServer(sessionId, targetServer, targetServers: targetServers);
              _emitMutation('sessions');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
          }
        }
      }

      // 7. Lịch sử hội thoại
      if (method == 'GET' && path == ApiConstants.epChatHistory) {
        final sessionId = req.uri.queryParameters['session_id'] ?? 'default';
        final limit = int.tryParse(req.uri.queryParameters['limit'] ?? '50') ?? 50;
        final beforeId = int.tryParse(req.uri.queryParameters['before_id'] ?? '');
        final result = await _db.getMessages(sessionId, limit: limit, beforeId: beforeId);
        await _sendJson(res, HttpStatus.ok, {
          'messages': result.messages.map((m) => m.toJson()).toList(),
          'has_more': result.hasMore,
          'oldest_id': result.oldestId,
        });
        return;
      }

      if (method == 'POST' && path == ApiConstants.epChatClear) {
        final body = await _readJsonBody(req);
        final sessionId = body['session_id']?.toString() ?? 'default';
        final ok = await _db.clearChat(sessionId);
        _emitMutation('chat:$sessionId');
        await _sendJson(res, HttpStatus.ok, {'ok': ok});
        return;
      }

      // 8. Dừng luồng AI đang chạy cho session
      if (method == 'POST' && path == ApiConstants.epChatStop) {
        final body = await _readJsonBody(req);
        final sessionId = body['session_id']?.toString() ?? '';
        if (sessionId.isNotEmpty) {
          await stopActiveChat(sessionId, reason: 'Đã dừng phản hồi từ App Phụ.');
        }
        await _sendJson(res, HttpStatus.ok, {'ok': true});
        return;
      }

      // 9. Chat Stream (SSE) & nối lại luồng đang chạy trên App Chính
      if (method == 'GET' && path == ApiConstants.epChatLive) {
        await _handleChatLive(req, clientInfo.clientId);
        return;
      }
      if (method == 'POST' && path == ApiConstants.epChat) {
        await _handleChatStream(req, clientInfo.clientId, clientWorkspaceDir: clientWorkspaceDir);
        return;
      }

      // 10. Lịch làm việc (Work Schedules trong SQLite của App Chính)
      if (path.startsWith('${ApiConstants.epWorkSchedules}/')) {
        final sub = path.substring('${ApiConstants.epWorkSchedules}/'.length);
        final segments = sub.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          final sessionId = Uri.decodeComponent(segments[0]);
          if (segments.length == 1) {
            if (method == 'GET') {
              final data = await _db.getWorkSchedule(sessionId);
              await _sendJson(res, HttpStatus.ok, {'schedule': data});
              return;
            }
            if (method == 'POST') {
              final body = await _readJsonBody(req);
              final rawTasks = (body['tasks'] is List)
                  ? (body['tasks'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
                  : <Map<String, dynamic>>[];
              final docFiles = (body['doc_files'] is List)
                  ? (body['doc_files'] as List).map((e) => e.toString()).toList()
                  : <String>[];
              final genAt = DateTime.tryParse(body['generated_at']?.toString() ?? '');
              final ok = await _db.saveWorkSchedule(
                sessionId: sessionId,
                projectName: body['project_name']?.toString() ?? '',
                summary: body['summary']?.toString() ?? '',
                docFiles: docFiles,
                generatedAt: genAt,
                tasks: rawTasks,
              );
              _emitMutation('schedule:$sessionId');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
            if (method == 'DELETE') {
              final ok = await _db.deleteWorkSchedule(sessionId);
              _emitMutation('schedule:$sessionId');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
          } else if (segments.length == 2) {
            final action = segments[1];
            if (method == 'GET' && action == 'pending-count') {
              final count = await _db.getPendingWorkScheduleCount(sessionId);
              await _sendJson(res, HttpStatus.ok, {'count': count});
              return;
            }
            if (method == 'POST' && action == 'done') {
              final body = await _readJsonBody(req);
              final codes = (body['task_codes'] is List)
                  ? (body['task_codes'] as List).map((e) => e.toString()).toList()
                  : <String>[];
              final done = body['done'] != false;
              final ok = await _db.markWorkScheduleTasksDone(sessionId, codes, done: done);
              _emitMutation('schedule:$sessionId');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
              return;
            }
          }
        }
      }

      // 11. Duyệt thư mục Scope & Upload/Download tệp trên App Chính
      if (method == 'GET' && path == ApiConstants.epFsListDirs) {
        final prefix = req.uri.queryParameters['prefix'] ?? '';
        final dirs = await _listLocalOrSshDirectories(prefix, rootConstraint: clientWorkspaceDir);
        await _sendJson(res, HttpStatus.ok, {
          'directories': dirs,
          if (clientWorkspaceDir.isNotEmpty) 'workspace_root': clientWorkspaceDir,
        });
        return;
      }

      if (method == 'POST' && path == ApiConstants.epFsUpload) {
        final body = await _readJsonBody(req);
        final fileName = (body['file_name']?.toString() ?? 'upload.bin').replaceAll(RegExp(r'[^\w\.\-\_]'), '_');
        final b64 = body['content_base64']?.toString() ?? '';
        final targetDir = body['target_dir']?.toString();
        final bytes = base64Decode(b64);

        String destDir;
        if (clientWorkspaceDir.isNotEmpty) {
          final scoped = _resolveClientScopedPath(clientWorkspaceDir, targetDir) ?? clientWorkspaceDir;
          final d = Directory(scoped);
          if (!d.existsSync()) {
            d.createSync(recursive: true);
          }
          destDir = scoped;
        } else {
          destDir = (targetDir != null && targetDir.trim().isNotEmpty && Directory(targetDir.trim()).existsSync())
              ? targetDir.trim()
              : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path);
        }
        final uploadDir = Directory(p.join(destDir, 'uploads'));
        if (!uploadDir.existsSync()) {
          uploadDir.createSync(recursive: true);
        }
        final destFile = File(p.join(uploadDir.path, fileName));
        await destFile.writeAsBytes(bytes);
        await _sendJson(res, HttpStatus.ok, {
          'status': 'success',
          'remote_path': destFile.path,
          'local_path': destFile.path,
          'size': bytes.length,
          'name': fileName,
        });
        return;
      }

      if (method == 'GET' && path == ApiConstants.epFsDownload) {
        final filePath = req.uri.queryParameters['path'] ?? '';
        if (filePath.isEmpty) {
          await _sendJson(res, HttpStatus.notFound, {'error': 'File not found'});
          return;
        }
        if (clientWorkspaceDir.isNotEmpty && !isPathWithinRoot(filePath, clientWorkspaceDir)) {
          await _sendJson(res, HttpStatus.forbidden, {
            'error': 'Không được phép tải tệp nằm ngoài thư mục làm việc của thiết bị App Phụ này.',
          });
          return;
        }
        final file = File(filePath);
        if (!file.existsSync()) {
          await _sendJson(res, HttpStatus.notFound, {'error': 'File not found'});
          return;
        }
        res.statusCode = HttpStatus.ok;
        res.headers.contentType = ContentType.binary;
        await res.addStream(file.openRead());
        await res.close();
        return;
      }

      // 12. Thông số hệ thống, dịch vụ, logs và deploy trên App Chính
      if (method == 'GET' && path == ApiConstants.epSystemInfo) {
        final metrics = await _ssh.getSystemMetrics();
        await _sendJson(res, HttpStatus.ok, {
          'status': metrics.status,
          'uptime': metrics.uptime,
          'os': metrics.os,
          'server_ip': metrics.serverIp,
          'service_status': metrics.serviceStatus,
          'last_sync': metrics.lastSync,
          'metrics': {
            'uptime_seconds': metrics.uptimeSeconds,
            'loadavg': metrics.loadAvg,
            'procs': metrics.procs,
            'ram_total': metrics.ramTotal,
            'ram_used': metrics.ramUsed,
            'ram_avail': metrics.ramAvail,
            'ram_percent': metrics.ramPercent,
            'ram_total_mb': metrics.ramTotalMb,
            'ram_used_mb': metrics.ramUsedMb,
            'disk_total': metrics.diskTotal,
            'disk_used': metrics.diskUsed,
            'disk_avail': metrics.diskAvail,
            'disk_percent': metrics.diskPercent,
            'net_rx_kbs': metrics.netRxSpeed,
            'net_tx_kbs': metrics.netTxSpeed,
            'net_rx_total': metrics.netRxTotal,
            'net_tx_total': metrics.netTxTotal,
            'net_percent': metrics.netPercent,
          },
        });
        return;
      }

      if (method == 'POST' && path == ApiConstants.epServiceAction) {
        final body = await _readJsonBody(req);
        final result = await _ssh.executeServiceAction(
          body['service']?.toString() ?? '',
          body['action']?.toString() ?? '',
        );
        await _sendJson(res, HttpStatus.ok, result);
        return;
      }

      if (method == 'GET' && path == ApiConstants.epServerLogs) {
        final lines = int.tryParse(req.uri.queryParameters['lines'] ?? '100') ?? 100;
        String logOut = 'Không có nhật ký cục bộ.';
        try {
          if (Platform.isLinux) {
            final proc = await Process.run('bash', [
              '-c',
              'journalctl -n $lines --no-pager 2>/dev/null || dmesg | tail -n $lines || ps aux | head -n $lines',
            ]).timeout(const Duration(seconds: 5));
            logOut = proc.stdout.toString().trim();
          } else if (Platform.isMacOS) {
            final proc = await Process.run('bash', ['-c', 'ps aux | head -n $lines']).timeout(const Duration(seconds: 5));
            logOut = proc.stdout.toString().trim();
          } else if (Platform.isWindows) {
            final proc = await Process.run('cmd.exe', ['/c', 'tasklist']).timeout(const Duration(seconds: 5));
            logOut = proc.stdout.toString().trim();
          }
        } catch (e) {
          logOut = 'Lỗi đọc logs trên App Chính: $e';
        }
        await _sendJson(res, HttpStatus.ok, {'logs': logOut});
        return;
      }

      if (method == 'POST' && path == ApiConstants.epServerDeploy) {
        await _handleDeployStream(req);
        return;
      }

      await _sendJson(res, HttpStatus.notFound, {'error': 'Not Found', 'path': path});
    } catch (e) {
      try {
        await _sendJson(res, HttpStatus.internalServerError, {'error': e.toString()});
      } catch (_) {}
    }
  }

  Future<void> _handleChatStream(
    HttpRequest req,
    String clientId, {
    String clientWorkspaceDir = '',
  }) async {
    final res = req.response;
    final body = await _readJsonBody(req);
    final sessionId = body['session_id']?.toString() ?? 'default';
    final message = body['message']?.toString() ?? '';
    final model = body['model']?.toString();
    final workingDir = _resolveClientScopedPath(clientWorkspaceDir, body['working_dir']?.toString());
    final targetServer = body['target_server']?.toString();
    final docFiles = (body['doc_files'] is List)
        ? (body['doc_files'] as List).map((e) => e.toString()).toList()
        : null;
    final targetServers = (body['target_servers'] is List)
        ? (body['target_servers'] as List).map((e) => e.toString()).toList()
        : null;
    final history = (body['history'] is List)
        ? (body['history'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : null;
    final attachments = (body['attachments'] is List)
        ? (body['attachments'] as List)
            .whereType<Map>()
            .map((e) => AttachmentItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : null;

    final bool isEphemeralSchedule = sessionId.startsWith('schedule_');

    // Chặn trùng lặp đồng thời trên cùng 1 hộp hội thoại (App Chính hoặc App Phụ khác đang hỏi Agent)
    if (!isEphemeralSchedule && isSessionBusy(sessionId)) {
      await _sendJson(res, HttpStatus.conflict, {
        'error': 'Hộp hội thoại này đang được Agent xử lý. Vui lòng đợi hoàn tất trước khi gửi câu hỏi mới.',
      });
      return;
    }

    res.statusCode = HttpStatus.ok;
    res.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform');
    res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    res.headers.set('X-Accel-Buffering', 'no');
    res.bufferOutput = false;

    final initialSubscriber = _RemoteSseSubscriber(clientId, res);
    _chatSseSubscribers.putIfAbsent(sessionId, () => <_RemoteSseSubscriber>{}).add(initialSubscriber);

    bool runFinished = false;
    StreamSubscription<String>? sub;

    Future<void> finishRun({
      RemoteChatSyncType? syncEndType,
      String? finalReply,
      String? errorMessage,
      bool cancelAiSub = false,
    }) async {
      if (runFinished) return;
      runFinished = true;
      if (_activeChatStreams[sessionId] == sub) {
        _activeChatStreams.remove(sessionId);
      }
      _activeChatStoppers.remove(sessionId);
      _activeRemoteChatSnapshots.remove(sessionId);
      final ownerClientId = _activeChatClientIds.remove(sessionId);
      if (ownerClientId != null) {
        _recomputeClientActivity(ownerClientId);
      }
      if (cancelAiSub && sub != null) {
        try {
          await sub.cancel();
        } catch (_) {}
      }
      await _closeChatSseSubscribers(sessionId);
      if (!isEphemeralSchedule) {
        if (syncEndType != null) {
          _emitRemoteChatSync(
            RemoteChatSyncEvent(
              sessionId: sessionId,
              type: syncEndType,
              reply: finalReply,
              error: errorMessage,
            ),
          );
        }
        _emitMutation('chat:$sessionId');
      }
    }

    // Với schedule ephemeral (tạo lịch), cho phép huỷ phiên schedule cũ cùng ID nếu còn chạy
    if (isEphemeralSchedule) {
      final prev = _activeChatStreams.remove(sessionId);
      _activeChatStoppers.remove(sessionId);
      if (prev != null) {
        try {
          await prev.cancel();
        } catch (_) {}
      }
    }

    RemoteChatLiveSnapshot? liveSnapshot;
    if (!isEphemeralSchedule) {
      liveSnapshot = RemoteChatLiveSnapshot(
        sessionId: sessionId,
        userMessage: message,
        model: (model != null && model.isNotEmpty) ? model : 'glm-5.3',
        attachments: attachments,
      );
      _activeRemoteChatSnapshots[sessionId] = liveSnapshot;
    }

    _activeChatStoppers[sessionId] = (String reason) async {
      _broadcastChatSse(sessionId, {'type': 'done', 'reply': reason});
      await finishRun(
        syncEndType: RemoteChatSyncType.stop,
        finalReply: reason,
        cancelAiSub: true,
      );
    };

    // Thông báo ngay cho UI App Chính trước khi nhận bất kỳ callback onStatus/onToken nào
    if (!isEphemeralSchedule) {
      _emitRemoteChatSync(
        RemoteChatSyncEvent(
          sessionId: sessionId,
          type: RemoteChatSyncType.start,
          userMessage: message,
          model: (model != null && model.isNotEmpty) ? model : 'glm-5.3',
          attachments: attachments,
          status: 'App Phụ đang hỏi Agent...',
        ),
      );
    }

    sub = _ai.streamChatMessage(
      sessionId: sessionId,
      message: message,
      model: model,
      attachments: attachments,
      history: history,
      workingDir: workingDir,
      docFiles: docFiles,
      targetServer: targetServer,
      targetServers: targetServers,
      onToken: (token) {
        _broadcastChatSse(sessionId, {'type': 'token', 'delta': token});
        if (!isEphemeralSchedule && liveSnapshot != null) {
          if (token == '__CLEAR_INTERMEDIATE_THOUGHTS__') {
            liveSnapshot.content = '';
          } else {
            liveSnapshot.content += token;
          }
          _emitRemoteChatSync(
            RemoteChatSyncEvent(
              sessionId: sessionId,
              type: RemoteChatSyncType.token,
              token: token,
            ),
          );
        }
      },
      onStatus: (status) {
        _broadcastChatSse(sessionId, {'type': 'status', 'message': status});
        if (!isEphemeralSchedule && liveSnapshot != null) {
          liveSnapshot.status = status;
          _emitRemoteChatSync(
            RemoteChatSyncEvent(
              sessionId: sessionId,
              type: RemoteChatSyncType.status,
              status: status,
            ),
          );
        }
      },
      onTool: (tool) {
        _broadcastChatSse(sessionId, {'type': 'tool', 'tool': tool.toJson()});
        if (!isEphemeralSchedule && liveSnapshot != null) {
          final cappedOutput = tool.output.length > 4000
              ? '${tool.output.substring(0, 4000)}\n... [Đã rút gọn ${tool.output.length - 4000} ký tự]'
              : tool.output;
          final cappedTool = ToolExecutionItem(
            tool: tool.tool,
            command: tool.command,
            output: cappedOutput,
          );
          var existingIdx = liveSnapshot.toolExecutions.lastIndexWhere(
            (t) => t.tool == tool.tool && t.command == tool.command && t.output == 'Đang thực thi...',
          );
          if (existingIdx == -1 && tool.output != 'Đang thực thi...') {
            existingIdx = liveSnapshot.toolExecutions.lastIndexWhere(
              (t) => t.tool == tool.tool && t.command == tool.tool && t.output == 'Đang thực thi...',
            );
          }
          if (existingIdx != -1) {
            liveSnapshot.toolExecutions[existingIdx] = cappedTool;
          } else {
            liveSnapshot.toolExecutions.add(cappedTool);
          }
          if (liveSnapshot.toolExecutions.length > 30) {
            liveSnapshot.toolExecutions.removeRange(0, liveSnapshot.toolExecutions.length - 30);
          }
          _emitRemoteChatSync(
            RemoteChatSyncEvent(
              sessionId: sessionId,
              type: RemoteChatSyncType.tool,
              tool: cappedTool,
            ),
          );
        }
      },
      onDone: (fullReply) {
        _broadcastChatSse(sessionId, {'type': 'done', 'reply': fullReply});
        unawaited(
          finishRun(
            syncEndType: RemoteChatSyncType.done,
            finalReply: fullReply,
          ),
        );
      },
      onError: (err) {
        _broadcastChatSse(sessionId, {'type': 'error', 'message': err.toString()});
        unawaited(
          finishRun(
            syncEndType: RemoteChatSyncType.error,
            errorMessage: err.toString(),
          ),
        );
      },
    );
    _activeChatStreams[sessionId] = sub;
    _activeChatClientIds[sessionId] = clientId;
    _recomputeClientActivity(clientId);

    // Tách vòng đời tiến trình AI khỏi kết nối HTTP của App Phụ:
    // - Với hội thoại thật: khi điện thoại ẩn app / tắt màn hình / rớt mạng tạm thời làm đứt socket,
    //   chỉ gỡ subscriber SSE đã chết, KHÔNG huỷ Agent trên App Chính để câu trả lời chạy xong và lưu SQLite.
    // - Chỉ hủy Agent khi bấm Dừng (/api/chat/stop), App Chính bấm Dừng, hoặc bị thu hồi quyền thiết bị.
    res.done.whenComplete(() {
      initialSubscriber.detach();
      _chatSseSubscribers[sessionId]?.remove(initialSubscriber);
      if (isEphemeralSchedule && !runFinished) {
        unawaited(finishRun(cancelAiSub: true));
      }
    });

    await initialSubscriber.done.future;
  }

  void _broadcastChatSse(String sessionId, Map<String, dynamic> payload) {
    final subs = _chatSseSubscribers[sessionId];
    if (subs == null || subs.isEmpty) return;
    for (final s in subs.toList()) {
      s.sendEvent(payload);
      if (s.closed) {
        subs.remove(s);
      }
    }
  }

  Future<void> _closeChatSseSubscribers(String sessionId) async {
    final subs = _chatSseSubscribers.remove(sessionId);
    if (subs == null || subs.isEmpty) return;
    for (final s in subs.toList()) {
      await s.finishAndClose();
    }
  }

  /// Cho phép App Phụ kiểm tra trạng thái hộp hội thoại và bám nối lại luồng SSE live
  /// nếu Agent trên App Chính vẫn đang trả lời (ví dụ sau khi ẩn app hoặc chuyển mạng).
  Future<void> _handleChatLive(HttpRequest req, String clientId) async {
    final res = req.response;
    final sessionId = (req.uri.queryParameters['session_id'] ?? '').trim();
    if (sessionId.isEmpty) {
      await _sendJson(res, HttpStatus.badRequest, {'error': 'Missing session_id'});
      return;
    }

    final liveSnapshot = _activeRemoteChatSnapshots[sessionId];
    if (liveSnapshot != null && _activeChatStreams.containsKey(sessionId)) {
      res.statusCode = HttpStatus.ok;
      res.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8');
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform');
      res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
      res.headers.set('X-Accel-Buffering', 'no');
      res.bufferOutput = false;

      final subscriber = _RemoteSseSubscriber(clientId, res);
      _chatSseSubscribers.putIfAbsent(sessionId, () => <_RemoteSseSubscriber>{}).add(subscriber);

      // Gửi ngay snapshot hiện có để App Phụ đồng bộ toàn bộ token/tool đã sinh trong lúc ẩn app
      subscriber.sendEvent({
        'type': 'snapshot',
        'session_id': sessionId,
        'user_message': liveSnapshot.userMessage,
        'model': liveSnapshot.model,
        'content': liveSnapshot.content,
        'status': liveSnapshot.status,
        'tools': liveSnapshot.toolExecutions.map((t) => t.toJson()).toList(),
      });

      res.done.whenComplete(() {
        subscriber.detach();
        _chatSseSubscribers[sessionId]?.remove(subscriber);
      });

      await subscriber.done.future;
      return;
    }

    if (isLocalSessionGenerating?.call(sessionId) == true) {
      await _sendJson(res, HttpStatus.ok, {
        'active': true,
        'local': true,
        'session_id': sessionId,
        'status': 'App Chính đang xử lý câu hỏi trên hộp hội thoại này...',
      });
      return;
    }

    await _sendJson(res, HttpStatus.ok, {
      'active': false,
      'session_id': sessionId,
    });
  }

  Future<void> _handleDeployStream(HttpRequest req) async {
    final res = req.response;
    res.statusCode = HttpStatus.ok;
    res.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform');
    res.headers.set('X-Accel-Buffering', 'no');
    res.bufferOutput = false;

    final completer = Completer<void>();
    bool closed = false;

    Future<void> finish() async {
      if (closed) return;
      closed = true;
      try {
        await res.close();
      } catch (_) {}
      if (!completer.isCompleted) completer.complete();
    }

    try {
      await _ssh.streamDeploy(
        onStep: (step) {
          if (!closed) {
            try {
              res.write('data: $step\n\n');
            } catch (_) {}
          }
        },
        onDone: () => unawaited(finish()),
        onError: (e) {
          if (!closed) {
            try {
              res.write('data: Lỗi deploy: $e\n\n');
            } catch (_) {}
          }
          unawaited(finish());
        },
      );
    } catch (_) {
      await finish();
    }
    await completer.future;
  }

  Future<void> _handleTerminalWebSocket(
    HttpRequest req,
    String clientId, {
    String clientWorkspaceDir = '',
  }) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      await _sendJson(req.response, HttpStatus.badRequest, {'error': 'WebSocket upgrade required'});
      return;
    }

    final socket = await WebSocketTransformer.upgrade(req);
    socket.pingInterval = const Duration(seconds: 20);
    _activeTerminalSockets++;
    _clientTerminalSockets.putIfAbsent(clientId, () => <WebSocket>{}).add(socket);
    _recomputeClientActivity(clientId);

    if (Platform.isIOS) {
      socket.add('\x1b[33mApp Chính trên iOS không hỗ trợ PTY cục bộ.\x1b[0m\r\n');
      await socket.close();
      _clientTerminalSockets[clientId]?.remove(socket);
      _recomputeClientActivity(clientId);
      _activeTerminalSockets = (_activeTerminalSockets - 1).clamp(0, 999);
      return;
    }

    Pty? pty;
    try {
      final isWin = Platform.isWindows;
      final isAndroid = Platform.isAndroid;
      final shell = isAndroid
          ? (File('/system/bin/sh').existsSync() ? '/system/bin/sh' : '/bin/sh')
          : (Platform.environment['SHELL'] ??
              (isWin ? 'cmd.exe' : (File('/bin/bash').existsSync() ? '/bin/bash' : '/bin/sh')));
      final defaultHome = isAndroid
          ? Directory.systemTemp.path
          : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? (isWin ? 'C:\\' : '/'));

      final reqCwd = req.uri.queryParameters['cwd']?.trim() ?? '';
      String workingDir;
      if (clientWorkspaceDir.isNotEmpty) {
        final scoped = _resolveClientScopedPath(clientWorkspaceDir, reqCwd) ?? clientWorkspaceDir;
        workingDir = Directory(scoped).existsSync() ? scoped : clientWorkspaceDir;
      } else {
        workingDir = (reqCwd.isNotEmpty && Directory(reqCwd).existsSync()) ? reqCwd : defaultHome;
      }
      final cols = (int.tryParse(req.uri.queryParameters['cols'] ?? '80') ?? 80).clamp(20, 400);
      final rows = (int.tryParse(req.uri.queryParameters['rows'] ?? '24') ?? 24).clamp(5, 200);

      pty = Pty.start(
        shell,
        arguments: (isWin || isAndroid) ? [] : ['-l'],
        workingDirectory: workingDir,
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'LANG': Platform.environment['LANG'] ?? 'en_US.UTF-8',
          if (clientWorkspaceDir.isNotEmpty) 'AGENT_CLIENT_WORKSPACE_DIR': clientWorkspaceDir,
        },
        columns: cols,
        rows: rows,
      );

      final outSub = pty.output.listen(
        (data) {
          if (socket.readyState == WebSocket.open) {
            socket.add(utf8.decode(data, allowMalformed: true));
          }
        },
        onDone: () {
          try {
            socket.close();
          } catch (_) {}
        },
      );

      await for (final incoming in socket) {
        if (incoming is String) {
          if (incoming.startsWith('{') && incoming.endsWith('}')) {
            try {
              final ctrl = jsonDecode(incoming);
              if (ctrl is Map && ctrl['type'] == 'resize') {
                final c = int.tryParse(ctrl['cols']?.toString() ?? '') ?? cols;
                final r = int.tryParse(ctrl['rows']?.toString() ?? '') ?? rows;
                pty.resize(r.clamp(5, 200), c.clamp(20, 400));
                continue;
              }
            } catch (_) {}
          }
          pty.write(utf8.encode(incoming));
        } else if (incoming is List<int>) {
          pty.write(Uint8List.fromList(incoming));
        }
      }

      await outSub.cancel();
    } catch (e) {
      try {
        if (socket.readyState == WebSocket.open) {
          socket.add('\x1b[31m[Lỗi khởi tạo Terminal trên App Chính]: $e\x1b[0m\r\n');
        }
      } catch (_) {}
    } finally {
      try {
        pty?.kill();
      } catch (_) {}
      try {
        await socket.close();
      } catch (_) {}
      final set = _clientTerminalSockets[clientId];
      set?.remove(socket);
      if (set != null && set.isEmpty) {
        _clientTerminalSockets.remove(clientId);
      }
      _recomputeClientActivity(clientId);
      _activeTerminalSockets = (_activeTerminalSockets - 1).clamp(0, 999);
    }
  }

  Future<List<String>> _listLocalOrSshDirectories(
    String prefix, {
    String rootConstraint = '',
  }) async {
    try {
      if (rootConstraint.isNotEmpty) {
        final normRoot = p.normalize(p.absolute(rootConstraint));
        final rootDir = Directory(normRoot);
        if (!rootDir.existsSync()) {
          rootDir.createSync(recursive: true);
        }

        final rawPrefix = prefix.trim();
        Directory targetDir = rootDir;
        String filter = '';
        if (rawPrefix.isNotEmpty) {
          final candidate = p.isAbsolute(rawPrefix)
              ? p.normalize(rawPrefix)
              : p.normalize(p.join(normRoot, rawPrefix));
          if (isPathWithinRoot(candidate, normRoot)) {
            final checkDir = Directory(candidate);
            if (checkDir.existsSync()) {
              targetDir = checkDir;
            } else {
              final parent = File(candidate).parent;
              if (parent.existsSync() && isPathWithinRoot(parent.path, normRoot)) {
                targetDir = parent;
                filter = p.basename(candidate).toLowerCase();
              }
            }
          }
        }

        final results = <String>[];
        if (p.normalize(targetDir.path) == normRoot && filter.isEmpty) {
          results.add(normRoot);
        }
        for (final entity in targetDir.listSync(followLinks: false)) {
          if (entity is Directory) {
            final entityPath = p.normalize(p.absolute(entity.path));
            if (!isPathWithinRoot(entityPath, normRoot)) continue;
            final dirName = p.basename(entityPath);
            if (dirName.startsWith('.') && !filter.startsWith('.')) continue;
            if (filter.isEmpty ||
                dirName.toLowerCase().contains(filter) ||
                entityPath.toLowerCase().contains(filter)) {
              results.add(entityPath);
            }
          }
        }
        results.sort((a, b) {
          if (a == normRoot) return -1;
          if (b == normRoot) return 1;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        return results.take(35).toList();
      }

      final cfg = await _config.loadConfig();
      final serverIp = cfg['server_ip']?.toString() ?? '127.0.0.1';
      final isRemote = serverIp.isNotEmpty && serverIp != '127.0.0.1' && serverIp != 'localhost';
      if (isRemote) {
        return await _ssh.listRemoteDirs(prefix);
      }

      var searchPath = prefix.trim();
      final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';
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
      for (final entity in targetDir.listSync(followLinks: false)) {
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
}
