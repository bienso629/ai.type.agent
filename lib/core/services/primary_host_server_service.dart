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
  final String clientDeviceName;
  final String clientOs;
  final String clientIp;
  final String pin;
  final DateTime createdAt;
  String status; // 'pending' | 'approved' | 'rejected'

  PendingPairingRequest({
    required this.id,
    required this.clientDeviceName,
    required this.clientOs,
    required this.clientIp,
    required this.pin,
    required this.createdAt,
    this.status = 'pending',
  });

  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(seconds: 65);
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
  String? _lastError;
  int _activeTerminalSockets = 0;

  final Map<String, StreamSubscription<String>> _activeChatStreams = {};
  final Map<String, Future<void> Function(String reason)> _activeChatStoppers = {};
  final Map<String, RemoteChatLiveSnapshot> _activeRemoteChatSnapshots = {};
  final Map<String, PendingPairingRequest> _pairingRequests = {};
  final StreamController<String> _mutationController = StreamController<String>.broadcast();
  final StreamController<RemoteChatSyncEvent> _remoteChatSyncController =
      StreamController<RemoteChatSyncEvent>.broadcast();
  final StreamController<PendingPairingRequest> _pairingRequestController =
      StreamController<PendingPairingRequest>.broadcast();

  /// Callback do `ChatProvider` trên App Chính đăng ký để kiểm tra phiên nào đang chạy cục bộ.
  bool Function(String sessionId)? isLocalSessionGenerating;

  bool get isRunning => _server != null;
  int get boundPort => _boundPort;
  String get token => _token;
  String get deviceName => _deviceName;
  String get publicUrl => _publicUrl;
  String? get lastError => _lastError;
  int get activeTerminalCount => _activeTerminalSockets;
  int get activeChatCount => _activeChatStreams.length;

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
      _lastError = null;

      srv.listen(
        _handleRequest,
        onError: (_) {},
      );
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
    await _stopDiscoveryResponder();
    _pairingRequests.clear();
    final activeIds = _activeChatStreams.keys.toList();
    for (final sId in activeIds) {
      await stopActiveChat(sId, reason: 'Máy chủ điều khiển từ xa đã dừng.');
    }
    _activeChatStreams.clear();
    _activeChatStoppers.clear();
    _activeRemoteChatSnapshots.clear();
    final srv = _server;
    _server = null;
    _boundPort = 0;
    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
    }
  }

  void updateRuntimeMetadata({String? token, String? deviceName, String? publicUrl}) {
    if (token != null && token.trim().isNotEmpty) {
      _token = token.trim();
    }
    if (deviceName != null && deviceName.trim().isNotEmpty) {
      _deviceName = deviceName.trim();
    }
    if (publicUrl != null) {
      _publicUrl = publicUrl.trim();
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
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Secret-Token, X-User-Email, X-User-Name');
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
      final clientName = body['device_name']?.toString().trim();
      final clientOs = body['os']?.toString().trim();
      final rng = Random.secure();
      final reqId = List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      final pin = (100000 + rng.nextInt(900000)).toString();
      final clientIp = req.connectionInfo?.remoteAddress.address ?? 'unknown';

      final pending = PendingPairingRequest(
        id: reqId,
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

    try {
      // 1. WebSocket Terminal trực tiếp trên App Chính
      if (path == ApiConstants.wsTerminal) {
        await _handleTerminalWebSocket(req);
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
          final created = await _db.createSession(
            title: body['title']?.toString() ?? 'Cuộc hội thoại mới',
            workingDir: body['working_dir']?.toString(),
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
              final scope = body['working_dir']?.toString();
              List<String>? docFiles;
              if (body['doc_files'] is List) {
                docFiles = (body['doc_files'] as List).map((e) => e.toString()).toList();
              }
              final ok = await _db.updateSessionScope(sessionId, scope, docFiles: docFiles);
              _emitMutation('sessions');
              await _sendJson(res, HttpStatus.ok, {'ok': ok});
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

      // 9. Chat Stream (SSE) thực thi trực tiếp trên App Chính
      if (method == 'POST' && path == ApiConstants.epChat) {
        await _handleChatStream(req);
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
        final dirs = await _listLocalOrSshDirectories(prefix);
        await _sendJson(res, HttpStatus.ok, {'directories': dirs});
        return;
      }

      if (method == 'POST' && path == ApiConstants.epFsUpload) {
        final body = await _readJsonBody(req);
        final fileName = (body['file_name']?.toString() ?? 'upload.bin').replaceAll(RegExp(r'[^\w\.\-\_]'), '_');
        final b64 = body['content_base64']?.toString() ?? '';
        final targetDir = body['target_dir']?.toString();
        final bytes = base64Decode(b64);

        var destDir = (targetDir != null && targetDir.trim().isNotEmpty && Directory(targetDir.trim()).existsSync())
            ? targetDir.trim()
            : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path);
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
        final file = File(filePath);
        if (filePath.isEmpty || !file.existsSync()) {
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

  Future<void> _handleChatStream(HttpRequest req) async {
    final res = req.response;
    final body = await _readJsonBody(req);
    final sessionId = body['session_id']?.toString() ?? 'default';
    final message = body['message']?.toString() ?? '';
    final model = body['model']?.toString();
    final workingDir = body['working_dir']?.toString();
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

    bool closed = false;
    final completer = Completer<void>();

    // Giữ kết nối SSE sống ổn định khi đi qua Cloudflare Tunnel / Nginx / mạng 4G-5G
    final keepAliveTimer = Timer.periodic(const Duration(seconds: 15), (t) {
      if (closed) {
        t.cancel();
        return;
      }
      try {
        res.write(': ping\n\n');
      } catch (_) {
        closed = true;
        t.cancel();
      }
    });

    void sendEvent(Map<String, dynamic> payload) {
      if (closed) return;
      try {
        res.write('data: ${jsonEncode(payload)}\n\n');
      } catch (_) {
        closed = true;
      }
    }

    StreamSubscription<String>? sub;

    Future<void> finishStream({
      RemoteChatSyncType? syncEndType,
      String? finalReply,
      String? errorMessage,
      bool cancelAiSub = false,
    }) async {
      if (closed) return;
      closed = true;
      keepAliveTimer.cancel();
      if (_activeChatStreams[sessionId] == sub) {
        _activeChatStreams.remove(sessionId);
      }
      _activeChatStoppers.remove(sessionId);
      _activeRemoteChatSnapshots.remove(sessionId);
      if (cancelAiSub && sub != null) {
        try {
          await sub.cancel();
        } catch (_) {}
      }
      try {
        res.write('data: [DONE]\n\n');
        await res.flush();
        await res.close();
      } catch (_) {}
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
      if (!completer.isCompleted) completer.complete();
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
      sendEvent({'type': 'done', 'reply': reason});
      await finishStream(
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
        sendEvent({'type': 'token', 'delta': token});
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
        sendEvent({'type': 'status', 'message': status});
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
        sendEvent({'type': 'tool', 'tool': tool.toJson()});
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
        sendEvent({'type': 'done', 'reply': fullReply});
        unawaited(
          finishStream(
            syncEndType: RemoteChatSyncType.done,
            finalReply: fullReply,
          ),
        );
      },
      onError: (err) {
        sendEvent({'type': 'error', 'message': err.toString()});
        unawaited(
          finishStream(
            syncEndType: RemoteChatSyncType.error,
            errorMessage: err.toString(),
          ),
        );
      },
    );
    _activeChatStreams[sessionId] = sub;

    // Nếu App Phụ ngắt kết nối giữa chừng -> huỷ tiến trình AI trên App Chính và giải phóng khóa UI
    res.done.whenComplete(() {
      keepAliveTimer.cancel();
      if (!closed) {
        closed = true;
        final active = _activeChatStreams[sessionId] == sub ? _activeChatStreams.remove(sessionId) : null;
        _activeChatStoppers.remove(sessionId);
        _activeRemoteChatSnapshots.remove(sessionId);
        active?.cancel();
        if (!isEphemeralSchedule) {
          _emitRemoteChatSync(
            RemoteChatSyncEvent(
              sessionId: sessionId,
              type: RemoteChatSyncType.stop,
              reply: 'App Phụ đã ngắt kết nối giữa chừng.',
            ),
          );
          _emitMutation('chat:$sessionId');
        }
        if (!completer.isCompleted) completer.complete();
      }
    });

    await completer.future;
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

  Future<void> _handleTerminalWebSocket(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      await _sendJson(req.response, HttpStatus.badRequest, {'error': 'WebSocket upgrade required'});
      return;
    }

    final socket = await WebSocketTransformer.upgrade(req);
    socket.pingInterval = const Duration(seconds: 20);
    _activeTerminalSockets++;

    if (Platform.isIOS) {
      socket.add('\x1b[33mApp Chính trên iOS không hỗ trợ PTY cục bộ.\x1b[0m\r\n');
      await socket.close();
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
      final workingDir = (reqCwd.isNotEmpty && Directory(reqCwd).existsSync()) ? reqCwd : defaultHome;
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
      _activeTerminalSockets = (_activeTerminalSockets - 1).clamp(0, 999);
    }
  }

  Future<List<String>> _listLocalOrSshDirectories(String prefix) async {
    try {
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
