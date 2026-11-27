import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../core/services/primary_host_server_service.dart';
import '../core/services/remote_tunnel_service.dart';
import '../core/services/storage_service.dart';

enum GatewayStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class GatewayProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final ApiService _api = ApiService();
  final PrimaryHostServerService _hostServer = PrimaryHostServerService.instance;
  final RemoteTunnelService _tunnelService = RemoteTunnelService.instance;

  StreamSubscription<RemoteTunnelSnapshot>? _tunnelSub;

  AppRole _role = AppRole.primary;

  // Cấu hình máy chủ điều khiển từ xa (khi thiết bị là App Chính)
  bool _primaryHostEnabled = false;
  int _primaryHostPort = ApiConstants.defaultPrimaryHostPort;
  String _primaryHostToken = '';
  String _primaryHostName = '';
  List<String> _lanIps = [];
  List<String> _vpnIps = [];
  String _hostErrorMessage = '';

  // Cấu hình đường hầm Internet toàn cầu (kết nối mọi nơi 4G/5G / khác mạng)
  RemoteTunnelMode _tunnelMode = RemoteTunnelMode.off;
  RemoteTunnelState _tunnelState = RemoteTunnelState.stopped;
  String _publicTunnelUrl = '';
  String _tunnelStatusMessage = '';
  String _tunnelErrorMessage = '';
  String _tunnelNamedToken = '';
  String _tunnelCustomUrl = '';
  bool _hasCloudflaredBinary = false;
  double _cloudflaredDownloadProgress = 0.0;

  // Cấu hình kết nối tới App Chính (khi thiết bị là App Phụ)
  String _gatewayUrl = '';
  String _secretToken = '';
  GatewayStatus _status = GatewayStatus.disconnected;
  String _errorMessage = '';
  int _pingMs = 0;
  String _remoteHostName = '';
  String _remoteHostOs = '';
  String _remoteAppVersion = '';

  // Tự tìm máy tính App Chính gần đây & Ghép nối 1 chạm (App Phụ)
  List<DiscoveredPrimaryHost> _discoveredHosts = [];
  bool _isDiscoveringHosts = false;
  bool _isWaitingPairingApproval = false;
  bool _pairingCancelled = false;
  String _activePairingPin = '';
  String _pairingTargetName = '';
  String _pairingStatusMessage = '';

  AppRole get role => _role;
  bool get isPrimary => _role == AppRole.primary;
  bool get isSecondary => _role == AppRole.secondary;

  bool get primaryHostEnabled => _primaryHostEnabled;
  int get primaryHostPort => _primaryHostPort;
  String get primaryHostToken => _primaryHostToken;
  String get primaryHostName => _primaryHostName;
  List<String> get lanIps => _lanIps;
  List<String> get vpnIps => _vpnIps;
  List<String> get localIps => [..._lanIps, ..._vpnIps];
  bool get isHostRunning => _hostServer.isRunning;
  int get hostBoundPort => _hostServer.boundPort;
  String get hostErrorMessage => _hostErrorMessage;

  RemoteTunnelMode get tunnelMode => _tunnelMode;
  RemoteTunnelState get tunnelState => _tunnelState;
  String get publicTunnelUrl => _publicTunnelUrl;
  String get tunnelStatusMessage => _tunnelStatusMessage;
  String get tunnelErrorMessage => _tunnelErrorMessage;
  String get tunnelNamedToken => _tunnelNamedToken;
  String get tunnelCustomUrl => _tunnelCustomUrl;
  bool get hasCloudflaredBinary => _hasCloudflaredBinary;
  double get cloudflaredDownloadProgress => _cloudflaredDownloadProgress;
  bool get isInternetTunnelRunning =>
      _tunnelState == RemoteTunnelState.running && _publicTunnelUrl.isNotEmpty;
  bool get isInternetTunnelBusy =>
      _tunnelState == RemoteTunnelState.starting || _tunnelState == RemoteTunnelState.installing;

  String get gatewayUrl => _gatewayUrl;
  String get secretToken => _secretToken;
  GatewayStatus get status => _status;
  String get errorMessage => _errorMessage;
  int get pingMs => _pingMs;
  bool get isConnected => _status == GatewayStatus.connected;
  String get remoteHostName => _remoteHostName;
  String get remoteHostOs => _remoteHostOs;
  String get remoteAppVersion => _remoteAppVersion;

  List<DiscoveredPrimaryHost> get discoveredHosts => _discoveredHosts;
  bool get isDiscoveringHosts => _isDiscoveringHosts;
  bool get isWaitingPairingApproval => _isWaitingPairingApproval;
  String get activePairingPin => _activePairingPin;
  String get pairingTargetName => _pairingTargetName;
  String get pairingStatusMessage => _pairingStatusMessage;

  /// Kiểm tra kết nối App Phụ hiện tại có phải qua Internet công khai (`https://` / tên miền) hay LAN.
  bool get isSecondaryOverInternet {
    final u = _gatewayUrl.trim().toLowerCase();
    if (u.startsWith('https://')) return true;
    final uri = Uri.tryParse(u);
    final host = uri?.host ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host.startsWith('127.') ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(host)) {
      return false;
    }
    return true;
  }

  /// Chuỗi ghép nối Internet toàn cầu (mọi nơi) nếu người dùng đang bật Internet Tunnel / Domain / Tailscale.
  String get primaryInternetPairingString {
    if (_publicTunnelUrl.isNotEmpty) {
      final lanBase = _lanIps.isNotEmpty
          ? 'http://${_lanIps.first}:${_hostServer.isRunning ? _hostServer.boundPort : _primaryHostPort}'
          : '';
      if (lanBase.isNotEmpty && lanBase != _publicTunnelUrl) {
        return '$_publicTunnelUrl#$_primaryHostToken&lan=${Uri.encodeComponent(lanBase)}';
      }
      return '$_publicTunnelUrl#$_primaryHostToken';
    }
    return '';
  }

  /// Chuỗi ghép nối nội bộ LAN `http://<LAN_IP>:<PORT>#<TOKEN>`.
  String get primaryLanPairingString {
    final ip = _lanIps.isNotEmpty ? _lanIps.first : '127.0.0.1';
    final port = _hostServer.isRunning ? _hostServer.boundPort : _primaryHostPort;
    return 'http://$ip:$port#$_primaryHostToken';
  }

  /// Chuỗi ghép nối nhanh tôn trọng chế độ người dùng đã chọn:
  /// - Nếu đang bật đường hầm Internet / URL tùy chọn (Tailscale / Cloudflare / Domain) -> ưu tiên địa chỉ đó + kèm LAN dự phòng.
  /// - Nếu đang ở chế độ Chỉ LAN -> luôn dùng đúng IP LAN (`192.168.x.x`), không tự ép IP Tailscale gây lỗi trên điện thoại chưa bật VPN.
  String get primaryPairingString {
    if (_tunnelMode != RemoteTunnelMode.off && _publicTunnelUrl.isNotEmpty) {
      return primaryInternetPairingString;
    }
    return primaryLanPairingString;
  }

  void _syncFromTunnelSnapshot([RemoteTunnelSnapshot? snap]) {
    final s = snap ?? _tunnelService.snapshot;
    _tunnelState = s.state;
    _publicTunnelUrl = s.publicUrl;
    _tunnelStatusMessage = s.statusMessage;
    _tunnelErrorMessage = s.errorMessage;
    _cloudflaredDownloadProgress = s.installProgress;
    _hostServer.updateRuntimeMetadata(publicUrl: _publicTunnelUrl);
  }

  GatewayProvider() {
    _tunnelSub = _tunnelService.onStateChanged.listen((snap) {
      _syncFromTunnelSnapshot(snap);
      notifyListeners();
    });
    init();
  }

  @override
  void dispose() {
    _tunnelSub?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    _role = await _storage.getAppRole();
    _primaryHostEnabled = await _storage.getPrimaryHostEnabled();
    _primaryHostPort = await _storage.getPrimaryHostPort();
    _primaryHostToken = await _storage.getPrimaryHostToken();
    _primaryHostName = await _storage.getPrimaryHostName();
    _tunnelMode = RemoteTunnelService.parseMode(await _storage.getPrimaryTunnelMode());
    _tunnelNamedToken = await _storage.getPrimaryTunnelNamedToken();
    _tunnelCustomUrl = await _storage.getPrimaryTunnelCustomUrl();
    _gatewayUrl = await _storage.getGatewayUrl();
    _secretToken = await _storage.getSecretToken();

    final endpoints = await PrimaryHostServerService.getNetworkEndpoints();
    _lanIps = endpoints.lanIps;
    _vpnIps = endpoints.vpnIps;
    _hasCloudflaredBinary = (await RemoteTunnelService.findCloudflaredBinary()) != null;

    // Đồng bộ lại trạng thái hiện thời nếu dịch vụ tunnel đã chạy sẵn
    final snap = _tunnelService.snapshot;
    if (snap.state != RemoteTunnelState.stopped) {
      _tunnelState = snap.state;
      _publicTunnelUrl = snap.publicUrl;
      _tunnelStatusMessage = snap.statusMessage;
      _tunnelErrorMessage = snap.errorMessage;
    }
    notifyListeners();

    if (_role == AppRole.primary) {
      if (_primaryHostEnabled) {
        final started = await _startPrimaryHost();
        if (started && _tunnelMode != RemoteTunnelMode.off) {
          unawaited(_applyCurrentTunnelMode());
        }
      }
      _status = GatewayStatus.connected;
      notifyListeners();
    } else {
      await _tunnelService.stop(resetModeToOff: false);
      await _hostServer.stop();
      if (_gatewayUrl.trim().isNotEmpty) {
        await testConnection();
      } else {
        _status = GatewayStatus.disconnected;
        notifyListeners();
      }
    }
  }

  Future<void> refreshLocalIps() async {
    final endpoints = await PrimaryHostServerService.getNetworkEndpoints();
    _lanIps = endpoints.lanIps;
    _vpnIps = endpoints.vpnIps;
    _hasCloudflaredBinary = (await RemoteTunnelService.findCloudflaredBinary()) != null;
    notifyListeners();
  }

  Future<bool> _startPrimaryHost() async {
    _hostErrorMessage = '';
    final ok = await _hostServer.start(
      port: _primaryHostPort,
      token: _primaryHostToken,
      deviceName: _primaryHostName,
      publicUrl: _publicTunnelUrl,
    );
    if (!ok) {
      _hostErrorMessage = _hostServer.lastError ?? 'Không thể khởi chạy máy chủ điều khiển từ xa.';
    }
    notifyListeners();
    return ok;
  }

  /// Quét tự động các máy tính App Chính đang bật trong cùng mạng Wi-Fi / LAN.
  Future<List<DiscoveredPrimaryHost>> discoverNearbyPrimaryHosts() async {
    _isDiscoveringHosts = true;
    _pairingStatusMessage = 'Đang tìm máy tính App Chính trong mạng gần đây...';
    notifyListeners();
    try {
      final list = await PrimaryHostServerService.discoverNearbyHosts();
      _discoveredHosts = list;
      _pairingStatusMessage = list.isEmpty
          ? 'Không thấy máy tính nào cùng Wi-Fi. Hãy đảm bảo máy tính đã bật "Cho phép App Phụ điều khiển" hoặc dùng Quét mã QR.'
          : 'Tìm thấy ${list.length} máy tính App Chính sẵn sàng kết nối.';
      return list;
    } finally {
      _isDiscoveringHosts = false;
      notifyListeners();
    }
  }

  void cancelOneTapPairing() {
    _pairingCancelled = true;
    _isWaitingPairingApproval = false;
    _activePairingPin = '';
    _pairingTargetName = '';
    _pairingStatusMessage = 'Đã hủy yêu cầu ghép nối.';
    notifyListeners();
  }

  /// Gửi yêu cầu ghép nối 1 chạm tới máy tính App Chính vừa tìm thấy và chờ người dùng bấm "Chấp nhận" trên PC.
  Future<bool> requestOneTapPairing(DiscoveredPrimaryHost host) async {
    _pairingCancelled = false;
    _isWaitingPairingApproval = true;
    _activePairingPin = '';
    _pairingTargetName = host.deviceName;
    _pairingStatusMessage = 'Đang gửi yêu cầu ghép nối tới ${host.deviceName}...';
    _errorMessage = '';
    notifyListeners();

    final client = http.Client();
    try {
      String localName = 'Thiết bị App Phụ';
      try {
        final h = Platform.localHostname.trim();
        if (h.isNotEmpty && h.toLowerCase() != 'localhost') {
          localName = h;
        } else {
          localName = Platform.isAndroid ? 'Điện thoại Android' : Platform.operatingSystem.toUpperCase();
        }
      } catch (_) {}

      final reqRes = await client
          .post(
            Uri.parse('${host.lanUrl}${ApiConstants.epPairRequest}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_name': localName,
              'os': Platform.operatingSystem,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (reqRes.statusCode != 200) {
        _errorMessage = 'Máy tính ${host.deviceName} không phản hồi yêu cầu ghép nối (HTTP ${reqRes.statusCode}).';
        return false;
      }

      final reqData = jsonDecode(utf8.decode(reqRes.bodyBytes)) as Map<String, dynamic>;
      final reqId = reqData['request_id']?.toString() ?? '';
      final pin = reqData['pin']?.toString() ?? '';
      if (reqId.isEmpty) {
        _errorMessage = 'Phản hồi ghép nối không hợp lệ.';
        return false;
      }

      _activePairingPin = pin;
      _pairingStatusMessage = 'Hãy bấm "Chấp nhận" trên màn hình máy tính ${host.deviceName} (Mã đối chiếu: $pin)';
      notifyListeners();

      // Chờ người dùng bấm Chấp nhận trên màn hình máy tính (tối đa 60 giây)
      for (var i = 0; i < 60; i++) {
        if (_pairingCancelled) return false;
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_pairingCancelled) return false;

        try {
          final statusRes = await client
              .get(Uri.parse('${host.lanUrl}${ApiConstants.epPairStatus}?id=${Uri.encodeQueryComponent(reqId)}'))
              .timeout(const Duration(seconds: 4));
          if (statusRes.statusCode != 200) continue;

          final statusData = jsonDecode(utf8.decode(statusRes.bodyBytes)) as Map<String, dynamic>;
          final st = statusData['status']?.toString() ?? 'pending';
          if (st == 'rejected') {
            _errorMessage = 'Yêu cầu kết nối đã bị từ chối trên máy tính ${host.deviceName}.';
            return false;
          }
          if (st == 'expired') {
            _errorMessage = 'Hết thời gian chờ duyệt trên máy tính. Hãy thử bấm Kết nối lại.';
            return false;
          }
          if (st == 'approved') {
            final token = statusData['token']?.toString().trim() ?? '';
            final preferredUrl = statusData['preferred_url']?.toString().trim() ?? '';
            final lanUrl = statusData['lan_url']?.toString().trim() ?? host.lanUrl;

            // Ưu tiên kết nối bằng địa chỉ Internet/Tailscale để ra ngoài dùng 4G vẫn chạy; nếu chưa chạm được thì fallback LAN ngay
            if (preferredUrl.isNotEmpty && preferredUrl != lanUrl) {
              final okPreferred = await setGatewayConfig(preferredUrl, token);
              if (okPreferred) return true;
            }
            return await setGatewayConfig(lanUrl, token);
          }
        } catch (_) {}
      }

      _errorMessage = 'Hết 60 giây chờ duyệt trên máy tính ${host.deviceName}.';
      return false;
    } catch (e) {
      _errorMessage = 'Không thể liên lạc với ${host.deviceName}: $e';
      return false;
    } finally {
      client.close();
      _isWaitingPairingApproval = false;
      _activePairingPin = '';
      notifyListeners();
    }
  }

  Future<void> _applyCurrentTunnelMode({bool autoInstallIfMissing = false}) async {
    if (_role != AppRole.primary || !_primaryHostEnabled || !_hostServer.isRunning) {
      await _tunnelService.stop(resetModeToOff: false);
      return;
    }

    final boundPort = _hostServer.boundPort > 0 ? _hostServer.boundPort : _primaryHostPort;
    switch (_tunnelMode) {
      case RemoteTunnelMode.off:
        await _tunnelService.stop(resetModeToOff: true);
        break;
      case RemoteTunnelMode.cloudflareQuick:
        await _tunnelService.startQuickTunnel(
          localPort: boundPort,
          verifyToken: _primaryHostToken,
          autoInstallIfMissing: autoInstallIfMissing,
        );
        _hasCloudflaredBinary = (await RemoteTunnelService.findCloudflaredBinary()) != null;
        break;
      case RemoteTunnelMode.cloudflareNamed:
        if (_tunnelNamedToken.trim().isNotEmpty && _tunnelCustomUrl.trim().isNotEmpty) {
          await _tunnelService.startNamedTunnel(
            tunnelToken: _tunnelNamedToken,
            publicUrl: _tunnelCustomUrl,
            verifyToken: _primaryHostToken,
            autoInstallIfMissing: autoInstallIfMissing,
          );
          _hasCloudflaredBinary = (await RemoteTunnelService.findCloudflaredBinary()) != null;
        } else {
          await _tunnelService.stop(resetModeToOff: false);
        }
        break;
      case RemoteTunnelMode.customUrl:
        await _tunnelService.activateCustomPublicUrl(_tunnelCustomUrl);
        break;
    }
    _syncFromTunnelSnapshot();
    notifyListeners();
  }

  /// Thay đổi chế độ truy cập Internet toàn cầu (Chỉ LAN / Quick Tunnel 1 chạm / Named Domain / Custom URL).
  Future<void> setTunnelMode(RemoteTunnelMode mode, {bool autoStart = true}) async {
    _tunnelMode = mode;
    _tunnelErrorMessage = '';
    await _storage.setPrimaryTunnelMode(RemoteTunnelService.serializeMode(mode));
    notifyListeners();

    if (mode == RemoteTunnelMode.off) {
      await _tunnelService.stop(resetModeToOff: true);
      _syncFromTunnelSnapshot();
      notifyListeners();
      return;
    }

    if (!autoStart) {
      await _tunnelService.stop(resetModeToOff: false);
      _syncFromTunnelSnapshot();
      notifyListeners();
      return;
    }

    // Nếu người dùng bật đường hầm Internet mà chưa bật Host cục bộ -> tự bật Host luôn cho mượt
    if (_role == AppRole.primary && !_primaryHostEnabled) {
      final hostOk = await setPrimaryHostEnabled(true, triggerTunnel: false);
      if (!hostOk) return;
    }

    await _applyCurrentTunnelMode();
  }

  /// Lưu và khởi chạy Cloudflare Named Tunnel (tên miền cố định mãi mãi).
  Future<bool> applyNamedTunnel({
    required String tunnelToken,
    required String publicUrl,
  }) async {
    _tunnelNamedToken = tunnelToken.trim();
    _tunnelCustomUrl = RemoteTunnelService.normalizePublicUrl(publicUrl);
    _tunnelMode = RemoteTunnelMode.cloudflareNamed;
    await _storage.setPrimaryTunnelNamedToken(_tunnelNamedToken);
    await _storage.setPrimaryTunnelCustomUrl(_tunnelCustomUrl);
    await _storage.setPrimaryTunnelMode(RemoteTunnelService.serializeMode(_tunnelMode));
    notifyListeners();

    if (_role == AppRole.primary && !_primaryHostEnabled) {
      final hostOk = await setPrimaryHostEnabled(true, triggerTunnel: false);
      if (!hostOk) return false;
    }

    final ok = await _tunnelService.startNamedTunnel(
      tunnelToken: _tunnelNamedToken,
      publicUrl: _tunnelCustomUrl,
      verifyToken: _primaryHostToken,
    );
    _hasCloudflaredBinary = (await RemoteTunnelService.findCloudflaredBinary()) != null;
    _syncFromTunnelSnapshot();
    notifyListeners();
    return ok;
  }

  /// Lưu và áp dụng Địa chỉ công khai tùy chọn (Tailscale VPN, Reverse Proxy, Nginx, VPS Tunnel).
  Future<bool> applyCustomPublicUrl(String rawUrl) async {
    _tunnelCustomUrl = RemoteTunnelService.normalizePublicUrl(rawUrl);
    _tunnelMode = RemoteTunnelMode.customUrl;
    await _storage.setPrimaryTunnelCustomUrl(_tunnelCustomUrl);
    await _storage.setPrimaryTunnelMode(RemoteTunnelService.serializeMode(_tunnelMode));
    notifyListeners();

    if (_role == AppRole.primary && !_primaryHostEnabled) {
      final hostOk = await setPrimaryHostEnabled(true, triggerTunnel: false);
      if (!hostOk) return false;
    }

    final ok = await _tunnelService.activateCustomPublicUrl(_tunnelCustomUrl);
    _syncFromTunnelSnapshot();
    notifyListeners();
    return ok;
  }

  /// Khởi động lại đường hầm Internet hiện tại (ví dụ để xin địa chỉ Quick Tunnel mới).
  Future<void> restartTunnel() async {
    await _applyCurrentTunnelMode();
  }

  /// Tự động tải và cài đặt `cloudflared` chính chủ về thư mục dữ liệu người dùng.
  Future<bool> installCloudflared({bool startAfterInstall = true}) async {
    final path = await _tunnelService.installCloudflared();
    _hasCloudflaredBinary = path != null;
    notifyListeners();
    if (path != null && startAfterInstall && _role == AppRole.primary && _primaryHostEnabled) {
      await _applyCurrentTunnelMode();
    }
    return path != null;
  }

  /// Chuyển đổi vai trò thiết bị giữa App Chính (Primary) và App Phụ (Secondary).
  Future<void> setAppRole(AppRole newRole) async {
    if (_role == newRole) return;
    _role = newRole;
    await _storage.setAppRole(newRole);
    _errorMessage = '';
    _hostErrorMessage = '';

    if (newRole == AppRole.primary) {
      _remoteHostName = '';
      _remoteHostOs = '';
      _remoteAppVersion = '';
      _status = GatewayStatus.connected;
      if (_primaryHostEnabled) {
        final started = await _startPrimaryHost();
        if (started && _tunnelMode != RemoteTunnelMode.off) {
          unawaited(_applyCurrentTunnelMode());
        }
      }
    } else {
      await _tunnelService.stop(resetModeToOff: false);
      await _hostServer.stop();
      _status = GatewayStatus.disconnected;
      if (_gatewayUrl.trim().isNotEmpty) {
        unawaited(testConnection());
      }
    }
    notifyListeners();
  }

  /// Bật / tắt dịch vụ cho phép App Phụ điều khiển trên App Chính.
  Future<bool> setPrimaryHostEnabled(bool enabled, {bool triggerTunnel = true}) async {
    _primaryHostEnabled = enabled;
    await _storage.setPrimaryHostEnabled(enabled);
    _hostErrorMessage = '';
    if (enabled && _role == AppRole.primary) {
      await refreshLocalIps();
      final ok = await _startPrimaryHost();
      if (ok && triggerTunnel && _tunnelMode != RemoteTunnelMode.off) {
        unawaited(_applyCurrentTunnelMode());
      }
      return ok;
    } else {
      await _tunnelService.stop(resetModeToOff: false);
      await _hostServer.stop();
      notifyListeners();
      return true;
    }
  }

  /// Cập nhật cổng lắng nghe và tên thiết bị cho App Chính.
  Future<bool> updatePrimaryHostSettings({int? port, String? deviceName, String? token}) async {
    final portChanged = port != null && port != _primaryHostPort;
    if (port != null && port >= 1024 && port <= 65535) {
      _primaryHostPort = port;
      await _storage.setPrimaryHostPort(port);
    }
    if (deviceName != null && deviceName.trim().isNotEmpty) {
      _primaryHostName = deviceName.trim();
      await _storage.setPrimaryHostName(_primaryHostName);
    }
    if (token != null && token.trim().isNotEmpty) {
      _primaryHostToken = token.trim();
      await _storage.setPrimaryHostToken(_primaryHostToken);
    }
    if (_role == AppRole.primary && _primaryHostEnabled) {
      final ok = await _startPrimaryHost();
      if (ok && portChanged && _tunnelMode == RemoteTunnelMode.cloudflareQuick) {
        unawaited(_applyCurrentTunnelMode());
      }
      return ok;
    }
    notifyListeners();
    return true;
  }

  Future<String> regeneratePrimaryToken() async {
    _primaryHostToken = await _storage.regeneratePrimaryHostToken();
    if (_hostServer.isRunning) {
      _hostServer.updateRuntimeMetadata(token: _primaryHostToken);
    }
    notifyListeners();
    return _primaryHostToken;
  }

  /// Cấu hình URL + Token của App Chính (cho App Phụ) và kiểm tra kết nối ngay.
  /// Hỗ trợ tự động thử danh sách `fallbackUrls` (ví dụ fallback sang LAN khi điện thoại chưa bật Tailscale).
  Future<bool> setGatewayConfig(
    String url,
    String token, {
    List<String> fallbackUrls = const [],
  }) async {
    final parsed = StorageService.parsePairingString(url);
    final effectiveToken = token.trim().isNotEmpty ? token.trim() : parsed.token;
    final candidates = <String>[
      if (parsed.url.isNotEmpty) parsed.url,
      ...parsed.fallbackUrls,
      ...fallbackUrls,
    ];
    final uniqueCandidates = <String>[];
    for (final c in candidates) {
      final clean = c.trim();
      if (clean.isNotEmpty && !uniqueCandidates.contains(clean)) {
        uniqueCandidates.add(clean);
      }
    }

    if (uniqueCandidates.isEmpty) {
      _status = GatewayStatus.error;
      _errorMessage = 'Vui lòng nhập địa chỉ App Chính hợp lệ.';
      notifyListeners();
      return false;
    }

    if (_role != AppRole.secondary) {
      _role = AppRole.secondary;
      await _storage.setAppRole(AppRole.secondary);
      await _tunnelService.stop(resetModeToOff: false);
      await _hostServer.stop();
    }

    _secretToken = effectiveToken;
    await _storage.setSecretToken(_secretToken);

    String firstError = '';
    for (final candidateUrl in uniqueCandidates) {
      _gatewayUrl = candidateUrl;
      await _storage.setGatewayUrl(_gatewayUrl);
      notifyListeners();
      final ok = await testConnection();
      if (ok) return true;
      if (firstError.isEmpty) firstError = _errorMessage;
    }

    // Khôi phục lại URL chính ban đầu để hiển thị đúng cho người dùng
    _gatewayUrl = uniqueCandidates.first;
    await _storage.setGatewayUrl(_gatewayUrl);
    if (firstError.isNotEmpty) _errorMessage = firstError;
    notifyListeners();
    return false;
  }

  Future<bool> connectWithPairingString(String pairingString) async {
    final parsed = StorageService.parsePairingString(pairingString);
    if (parsed.url.isEmpty) {
      _status = GatewayStatus.error;
      _errorMessage = 'Chuỗi ghép nối không hợp lệ.';
      notifyListeners();
      return false;
    }
    return await setGatewayConfig(
      parsed.url,
      parsed.token,
      fallbackUrls: parsed.fallbackUrls,
    );
  }

  /// Ngắt kết nối App Phụ khỏi App Chính hiện tại và xóa thông tin ghép nối đã lưu.
  Future<void> disconnectFromPrimary({bool clearSavedCredentials = true}) async {
    cancelOneTapPairing();
    _status = GatewayStatus.disconnected;
    _pingMs = 0;
    _remoteHostName = '';
    _remoteHostOs = '';
    _remoteAppVersion = '';
    _errorMessage = '';
    if (clearSavedCredentials) {
      _gatewayUrl = '';
      _secretToken = '';
      await _storage.setGatewayUrl('');
      await _storage.setSecretToken('');
    }
    notifyListeners();
  }

  Future<bool> testConnection() async {
    if (_role == AppRole.primary) {
      _status = GatewayStatus.connected;
      _errorMessage = '';
      _pingMs = 0;
      notifyListeners();
      return true;
    }

    if (_gatewayUrl.trim().isEmpty) {
      _status = GatewayStatus.disconnected;
      _errorMessage = 'Chưa nhập địa chỉ App Chính.';
      notifyListeners();
      return false;
    }

    _status = GatewayStatus.connecting;
    _errorMessage = '';
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      final info = await _api.getRemoteHostInfo();
      stopwatch.stop();

      if (info != null && info['ok'] == true) {
        _status = GatewayStatus.connected;
        _pingMs = stopwatch.elapsedMilliseconds;
        _remoteHostName = info['device_name']?.toString() ?? _gatewayUrl;
        _remoteHostOs = info['os']?.toString() ?? '';
        _remoteAppVersion = info['app_version']?.toString() ?? '';
        notifyListeners();
        return true;
      }

      // Fallback tương thích với Gateway bên ngoài chỉ có /api/config
      final healthy = await _api.checkHealth();
      stopwatch.stop();
      if (healthy) {
        _status = GatewayStatus.connected;
        _pingMs = stopwatch.elapsedMilliseconds;
        _remoteHostName = _gatewayUrl;
        notifyListeners();
        return true;
      }

      _status = GatewayStatus.error;
      final parsedHost = Uri.tryParse(_gatewayUrl)?.host ?? '';
      if (PrimaryHostServerService.isTailscaleOrCgnatIp(parsedHost)) {
        _errorMessage =
            'Không chạm được IP Tailscale ($parsedHost). Hãy bật app Tailscale trên điện thoại, hoặc dùng IP LAN (192.168.x.x) / bật "Internet 1 chạm" trên máy tính.';
      } else {
        _errorMessage =
            'Không thể kết nối hoặc sai Mã ghép nối tới $_gatewayUrl. Kiểm tra máy tính đã bật App Chính và đúng địa chỉ/mã chưa.';
      }
      notifyListeners();
      return false;
    } catch (e) {
      stopwatch.stop();
      _status = GatewayStatus.error;
      _errorMessage = 'Lỗi kết nối App Chính: $e';
      notifyListeners();
      return false;
    }
  }
}
