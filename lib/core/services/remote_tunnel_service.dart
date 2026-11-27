import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../constants/api_constants.dart';

/// Chế độ mở truy cập Internet từ xa cho App Chính.
enum RemoteTunnelMode {
  /// Chỉ dùng mạng nội bộ LAN (không mở đường hầm Internet).
  off,

  /// Cloudflare Quick Tunnel 1 chạm miễn phí (tự cấp địa chỉ https://*.trycloudflare.com, không cần tài khoản).
  cloudflareQuick,

  /// Cloudflare Named Tunnel dùng mãi mãi với tên miền cố định không đổi khi khởi động lại máy.
  cloudflareNamed,

  /// Tự nhập địa chỉ công khai (VPS Reverse Proxy, Nginx, Tailscale VPN hoặc Port Forwarding).
  customUrl,
}

/// Trạng thái hoạt động hiện tại của đường hầm Internet.
enum RemoteTunnelState {
  stopped,
  installing,
  starting,
  running,
  error,
}

/// Ảnh chụp trạng thái đường hầm để phát cho UI/Provider.
class RemoteTunnelSnapshot {
  final RemoteTunnelMode mode;
  final RemoteTunnelState state;
  final String publicUrl;
  final String statusMessage;
  final String errorMessage;
  final double installProgress;

  const RemoteTunnelSnapshot({
    this.mode = RemoteTunnelMode.off,
    this.state = RemoteTunnelState.stopped,
    this.publicUrl = '',
    this.statusMessage = '',
    this.errorMessage = '',
    this.installProgress = 0.0,
  });

  bool get isRunning => state == RemoteTunnelState.running && publicUrl.isNotEmpty;
}

/// Dịch vụ tạo và duy trì đường hầm Internet HTTPS/WSS công khai cho **App Chính**,
/// giúp **App Phụ** kết nối từ bất kỳ đâu (4G/5G, Wi-Fi khác mạng, sau NAT/CGNAT)
/// mà không cần mở cổng router hay cấu hình phức tạp.
class RemoteTunnelService {
  static final RemoteTunnelService instance = RemoteTunnelService._internal();
  factory RemoteTunnelService() => instance;

  RemoteTunnelService._internal({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  factory RemoteTunnelService.forTest({http.Client? httpClient}) =>
      RemoteTunnelService._internal(httpClient: httpClient);

  final http.Client _httpClient;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Timer? _reconnectTimer;

  RemoteTunnelMode _mode = RemoteTunnelMode.off;
  RemoteTunnelState _state = RemoteTunnelState.stopped;
  String _publicUrl = '';
  String _statusMessage = '';
  String _errorMessage = '';
  double _installProgress = 0.0;

  bool _intentionallyStopped = true;
  int _restartAttempts = 0;
  int _lastLocalPort = ApiConstants.defaultPrimaryHostPort;
  String _lastVerifyToken = '';
  String _lastNamedToken = '';
  String _lastNamedUrl = '';
  int _generation = 0;

  final StreamController<RemoteTunnelSnapshot> _stateController =
      StreamController<RemoteTunnelSnapshot>.broadcast();

  Stream<RemoteTunnelSnapshot> get onStateChanged => _stateController.stream;

  RemoteTunnelMode get mode => _mode;
  RemoteTunnelState get state => _state;
  String get publicUrl => _publicUrl;
  String get statusMessage => _statusMessage;
  String get errorMessage => _errorMessage;
  double get installProgress => _installProgress;
  bool get isRunning => _state == RemoteTunnelState.running && _publicUrl.isNotEmpty;

  static bool get isDesktopTunnelSupported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  RemoteTunnelSnapshot get snapshot => RemoteTunnelSnapshot(
        mode: _mode,
        state: _state,
        publicUrl: _publicUrl,
        statusMessage: _statusMessage,
        errorMessage: _errorMessage,
        installProgress: _installProgress,
      );

  void _emitState({
    RemoteTunnelMode? mode,
    RemoteTunnelState? state,
    String? publicUrl,
    String? statusMessage,
    String? errorMessage,
    double? installProgress,
  }) {
    if (mode != null) _mode = mode;
    if (state != null) _state = state;
    if (publicUrl != null) _publicUrl = publicUrl;
    if (statusMessage != null) _statusMessage = statusMessage;
    if (errorMessage != null) _errorMessage = errorMessage;
    if (installProgress != null) _installProgress = installProgress;
    if (!_stateController.isClosed) {
      _stateController.add(snapshot);
    }
  }

  static final RegExp _quickTunnelUrlRegex = RegExp(
    r'https://[a-zA-Z0-9-]+\.trycloudflare\.com',
    caseSensitive: false,
  );

  /// Trích xuất địa chỉ công khai `https://<slug>.trycloudflare.com` từ nhật ký `cloudflared`.
  static String? extractQuickTunnelUrl(String logLine) {
    final m = _quickTunnelUrlRegex.firstMatch(logLine);
    return m?.group(0)?.trim();
  }

  /// Chuẩn hóa URL công khai (tự bổ sung `https://` nếu là tên miền, bỏ dấu `/` cuối).
  static String normalizePublicUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('aitype://')) {
      text = 'https://${text.substring('aitype://'.length)}';
    }
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      // Nếu là IP thuần (VD Tailscale 100.x.x.x:8765 hoặc LAN 192.168.x.x:8765) -> http://
      final isIpLike = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$').hasMatch(text);
      text = isIpLike ? 'http://$text' : 'https://$text';
    }
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static RemoteTunnelMode parseMode(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'quick':
      case 'cloudflare_quick':
        return RemoteTunnelMode.cloudflareQuick;
      case 'named':
      case 'cloudflare_named':
        return RemoteTunnelMode.cloudflareNamed;
      case 'custom':
      case 'custom_url':
        return RemoteTunnelMode.customUrl;
      default:
        return RemoteTunnelMode.off;
    }
  }

  static String serializeMode(RemoteTunnelMode mode) {
    switch (mode) {
      case RemoteTunnelMode.cloudflareQuick:
        return 'quick';
      case RemoteTunnelMode.cloudflareNamed:
        return 'named';
      case RemoteTunnelMode.customUrl:
        return 'custom';
      case RemoteTunnelMode.off:
        return 'off';
    }
  }

  /// Đường dẫn binary `cloudflared` tự quản lý trong thư mục dữ liệu người dùng (không cần quyền sudo).
  static String get managedCloudflaredPath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final binName = Platform.isWindows ? 'cloudflared.exe' : 'cloudflared';
    return p.join(home, '.ai_type_agent', 'bin', binName);
  }

  /// Tìm tệp thực thi `cloudflared` có sẵn trên hệ thống hoặc trong thư mục tự quản lý của ứng dụng.
  static Future<String?> findCloudflaredBinary() async {
    if (!isDesktopTunnelSupported) return null;

    final candidates = <String>[
      managedCloudflaredPath,
      if (Platform.isLinux || Platform.isMacOS) ...[
        '/usr/local/bin/cloudflared',
        '/usr/bin/cloudflared',
        '/opt/homebrew/bin/cloudflared',
        '/snap/bin/cloudflared',
      ],
      if (Platform.isWindows) ...[
        r'C:\Program Files\cloudflared\cloudflared.exe',
        r'C:\Program Files (x86)\cloudflared\cloudflared.exe',
        if (Platform.environment['LOCALAPPDATA'] != null)
          p.join(Platform.environment['LOCALAPPDATA']!, 'cloudflared', 'cloudflared.exe'),
      ],
    ];

    for (final path in candidates) {
      try {
        if (File(path).existsSync()) return path;
      } catch (_) {}
    }

    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final res = await Process.run(cmd, ['cloudflared']).timeout(const Duration(seconds: 3));
      if (res.exitCode == 0) {
        final firstLine = res.stdout.toString().split(RegExp(r'[\r\n]+')).first.trim();
        if (firstLine.isNotEmpty && File(firstLine).existsSync()) {
          return firstLine;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Tải và cài đặt `cloudflared` chính chủ từ Cloudflare GitHub Releases vào `~/.ai_type_agent/bin/` (không cần sudo).
  Future<String?> installCloudflared({void Function(double progress)? onProgress}) async {
    if (!isDesktopTunnelSupported) {
      _emitState(
        state: RemoteTunnelState.error,
        errorMessage: 'Đường hầm Cloudflare chỉ hỗ trợ chạy trên máy tính (Linux, Windows, macOS).',
      );
      return null;
    }

    final existing = await findCloudflaredBinary();
    if (existing != null) return existing;

    String? downloadUrl;
    if (Platform.isLinux) {
      final arch = await _detectLinuxArch();
      downloadUrl = arch == 'arm64'
          ? 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64'
          : 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64';
    } else if (Platform.isWindows) {
      downloadUrl =
          'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe';
    } else if (Platform.isMacOS) {
      _emitState(
        state: RemoteTunnelState.error,
        errorMessage: 'Trên macOS, hãy cài đặt nhanh bằng lệnh: brew install cloudflared',
      );
      return null;
    }

    if (downloadUrl == null) return null;

    _emitState(
      state: RemoteTunnelState.installing,
      statusMessage: 'Đang tải công cụ đường hầm Cloudflare (cloudflared)...',
      errorMessage: '',
      installProgress: 0.05,
    );

    final targetPath = managedCloudflaredPath;
    final tmpPath = '$targetPath.download';
    try {
      final binDir = Directory(p.dirname(targetPath));
      if (!binDir.existsSync()) {
        binDir.createSync(recursive: true);
      }

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamed = await _httpClient.send(request).timeout(const Duration(seconds: 60));
      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode} khi tải cloudflared');
      }

      final totalBytes = streamed.contentLength ?? 0;
      int received = 0;
      final outFile = File(tmpPath);
      final sink = outFile.openWrite();
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          final pct = (received / totalBytes).clamp(0.05, 0.99);
          _installProgress = pct;
          onProgress?.call(pct);
          _emitState(
            state: RemoteTunnelState.installing,
            statusMessage: 'Đang tải cloudflared (${(pct * 100).round()}%)...',
            installProgress: pct,
          );
        }
      }
      await sink.flush();
      await sink.close();

      if (File(targetPath).existsSync()) {
        await File(targetPath).delete();
      }
      await outFile.rename(targetPath);

      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', targetPath]);
      }

      _emitState(
        state: RemoteTunnelState.stopped,
        statusMessage: 'Đã cài đặt cloudflared thành công.',
        installProgress: 1.0,
      );
      onProgress?.call(1.0);
      return targetPath;
    } catch (e) {
      try {
        if (File(tmpPath).existsSync()) File(tmpPath).deleteSync();
      } catch (_) {}
      _emitState(
        state: RemoteTunnelState.error,
        errorMessage: 'Không thể tải cloudflared tự động: $e',
        installProgress: 0.0,
      );
      return null;
    }
  }

  Future<String> _detectLinuxArch() async {
    try {
      final res = await Process.run('uname', ['-m']).timeout(const Duration(seconds: 2));
      final out = res.stdout.toString().trim().toLowerCase();
      if (out.contains('aarch64') || out.contains('arm64')) return 'arm64';
    } catch (_) {}
    return 'amd64';
  }

  /// Đường dẫn tệp YAML rỗng cô lập cho Quick Tunnel để `cloudflared` không nạp nhầm `~/.cloudflared/config.yml` cũ.
  static Future<String> _ensureIsolatedQuickConfigPath() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
    final binDir = Directory(p.join(home, '.ai_type_agent', 'bin'));
    if (!binDir.existsSync()) {
      binDir.createSync(recursive: true);
    }
    final cfgFile = File(p.join(binDir.path, 'quick_tunnel_isolated.yml'));
    if (!cfgFile.existsSync()) {
      await cfgFile.writeAsString('# Isolated empty config for AI Type Agent Quick Tunnel\n');
    }
    return cfgFile.path;
  }

  /// Khởi động **Cloudflare Quick Tunnel** (1 chạm, miễn phí, không cần tài khoản hay tên miền).
  /// Trả về địa chỉ `https://<slug>.trycloudflare.com` sau khi xác nhận đường hầm đã đăng ký
  /// với Cloudflare Edge và DNS công khai đã sẵn sàng trên toàn cầu.
  Future<String?> startQuickTunnel({
    required int localPort,
    String? verifyToken,
    bool autoInstallIfMissing = false,
  }) async {
    if (!isDesktopTunnelSupported) {
      _emitState(
        mode: RemoteTunnelMode.cloudflareQuick,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Đường hầm Internet tự động chỉ hỗ trợ khi App Chính chạy trên máy tính (Linux, Windows, macOS).',
      );
      return null;
    }

    await _terminateProcessOnly();
    final gen = ++_generation;
    _intentionallyStopped = false;
    _restartAttempts = 0;
    _lastLocalPort = localPort;
    _lastVerifyToken = verifyToken ?? '';

    var binary = await findCloudflaredBinary();
    if (binary == null && autoInstallIfMissing) {
      binary = await installCloudflared();
    }
    if (binary == null) {
      _emitState(
        mode: RemoteTunnelMode.cloudflareQuick,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Chưa cài đặt cloudflared trên máy tính. Nhấn "Tải cloudflared tự động" để cài đặt 1 chạm.',
      );
      return null;
    }

    _emitState(
      mode: RemoteTunnelMode.cloudflareQuick,
      state: RemoteTunnelState.starting,
      publicUrl: '',
      statusMessage: 'Đang khởi tạo đường hầm HTTPS Cloudflare (cổng cục bộ $localPort)...',
      errorMessage: '',
    );

    try {
      final isolatedCfgPath = await _ensureIsolatedQuickConfigPath();
      final proc = await Process.start(
        binary,
        [
          'tunnel',
          '--config',
          isolatedCfgPath,
          '--url',
          'http://127.0.0.1:$localPort',
          '--no-autoupdate',
        ],
        runInShell: false,
      );
      if (gen != _generation) {
        proc.kill();
        return null;
      }
      _process = proc;

      final urlCompleter = Completer<String>();
      final registeredCompleter = Completer<void>();
      final errorTail = <String>[];

      void handleLine(String line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        final lower = trimmed.toLowerCase();
        if (lower.contains('err') || lower.contains('failed')) {
          errorTail.add(trimmed);
          if (errorTail.length > 5) errorTail.removeAt(0);
        }
        if (!urlCompleter.isCompleted) {
          final found = extractQuickTunnelUrl(trimmed);
          if (found != null && found.isNotEmpty) {
            urlCompleter.complete(found);
          }
        }
        if (!registeredCompleter.isCompleted &&
            (lower.contains('registered tunnel connection') || lower.contains('connection registered'))) {
          registeredCompleter.complete();
        }
      }

      _stdoutSub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(handleLine);
      _stderrSub = proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(handleLine);

      unawaited(proc.exitCode.then((code) {
        if (gen != _generation) return;
        if (!urlCompleter.isCompleted) {
          final detail = errorTail.isNotEmpty ? errorTail.last : 'Mã thoát $code';
          urlCompleter.completeError(Exception('cloudflared dừng sớm: $detail'));
        }
        if (!registeredCompleter.isCompleted) {
          registeredCompleter.complete();
        }
        if (!_intentionallyStopped) {
          _scheduleReconnect(gen);
        }
      }));

      final tunnelUrl = await urlCompleter.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException('Quá 25 giây chưa nhận được địa chỉ đường hầm Cloudflare.'),
      );

      if (gen != _generation || _intentionallyStopped) return null;

      _emitState(
        mode: RemoteTunnelMode.cloudflareQuick,
        state: RemoteTunnelState.starting,
        publicUrl: tunnelUrl,
        statusMessage: 'Đã cấp $tunnelUrl • Đang đăng ký kết nối Cloudflare Edge...',
      );

      // Chờ cloudflared xác nhận Registered tunnel connection với Edge gần nhất
      await registeredCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );

      if (gen != _generation || _intentionallyStopped) return null;

      _emitState(
        mode: RemoteTunnelMode.cloudflareQuick,
        state: RemoteTunnelState.starting,
        publicUrl: tunnelUrl,
        statusMessage: 'Đang xác minh DNS Internet toàn cầu cho $tunnelUrl...',
      );

      // Chờ bản ghi DNS xuất hiện trên Cloudflare DoH (1.1.1.1) trước khi probe HTTP
      // để tránh làm nhiễm bộ nhớ đệm NXDOMAIN của DNS cục bộ trên máy tính
      await _waitForCloudflareDohReady(tunnelUrl, generation: gen);
      await _waitForPublicEndpointReady(tunnelUrl, verifyToken: verifyToken, generation: gen);

      if (gen != _generation || _intentionallyStopped) return null;

      _emitState(
        mode: RemoteTunnelMode.cloudflareQuick,
        state: RemoteTunnelState.running,
        publicUrl: tunnelUrl,
        statusMessage: 'Đường hầm Internet HTTPS đã sẵn sàng — App Phụ có thể kết nối từ mọi nơi (4G/5G/Wi-Fi).',
        errorMessage: '',
      );
      return tunnelUrl;
    } catch (e) {
      if (gen != _generation) return null;
      await _terminateProcessOnly();
      _emitState(
        mode: RemoteTunnelMode.cloudflareQuick,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Không thể tạo đường hầm Cloudflare: $e',
      );
      return null;
    }
  }

  /// Khởi động **Cloudflare Named Tunnel** cho địa chỉ tên miền cố định (không đổi sau khi khởi động lại máy).
  Future<bool> startNamedTunnel({
    required String tunnelToken,
    required String publicUrl,
    String? verifyToken,
    bool autoInstallIfMissing = false,
  }) async {
    if (!isDesktopTunnelSupported) {
      _emitState(
        mode: RemoteTunnelMode.cloudflareNamed,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Cloudflare Named Tunnel chỉ hỗ trợ khi App Chính chạy trên máy tính.',
      );
      return false;
    }

    final cleanToken = tunnelToken.trim();
    final cleanUrl = normalizePublicUrl(publicUrl);
    if (cleanToken.isEmpty || cleanUrl.isEmpty) {
      _emitState(
        mode: RemoteTunnelMode.cloudflareNamed,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Vui lòng nhập đầy đủ Cloudflare Tunnel Token và Địa chỉ tên miền cố định (https://...).',
      );
      return false;
    }

    await _terminateProcessOnly();
    final gen = ++_generation;
    _intentionallyStopped = false;
    _restartAttempts = 0;
    _lastNamedToken = cleanToken;
    _lastNamedUrl = cleanUrl;
    _lastVerifyToken = verifyToken ?? '';

    var binary = await findCloudflaredBinary();
    if (binary == null && autoInstallIfMissing) {
      binary = await installCloudflared();
    }
    if (binary == null) {
      _emitState(
        mode: RemoteTunnelMode.cloudflareNamed,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Chưa cài đặt cloudflared trên máy tính. Nhấn "Tải cloudflared tự động" để cài đặt.',
      );
      return false;
    }

    _emitState(
      mode: RemoteTunnelMode.cloudflareNamed,
      state: RemoteTunnelState.starting,
      publicUrl: cleanUrl,
      statusMessage: 'Đang kết nối Cloudflare Named Tunnel ($cleanUrl)...',
      errorMessage: '',
    );

    try {
      final proc = await Process.start(
        binary,
        [
          'tunnel',
          '--no-autoupdate',
          'run',
          '--token',
          cleanToken,
        ],
        runInShell: false,
      );
      if (gen != _generation) {
        proc.kill();
        return false;
      }
      _process = proc;

      final connectedCompleter = Completer<void>();
      final errorTail = <String>[];

      void handleLine(String line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        final lower = trimmed.toLowerCase();
        if (lower.contains('registered tunnel connection') || lower.contains('connection registered')) {
          if (!connectedCompleter.isCompleted) connectedCompleter.complete();
        }
        if (lower.contains('err') || lower.contains('failed') || lower.contains('invalid')) {
          errorTail.add(trimmed);
          if (errorTail.length > 5) errorTail.removeAt(0);
        }
      }

      _stdoutSub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(handleLine);
      _stderrSub = proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(handleLine);

      unawaited(proc.exitCode.then((code) {
        if (gen != _generation) return;
        if (!connectedCompleter.isCompleted) {
          final detail = errorTail.isNotEmpty ? errorTail.last : 'Mã thoát $code';
          connectedCompleter.completeError(Exception('Named Tunnel dừng sớm: $detail'));
        }
        if (!_intentionallyStopped) {
          _scheduleReconnect(gen);
        }
      }));

      await connectedCompleter.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          // Một số phiên bản cloudflared in log ngắn gọn hơn -> vẫn kiểm tra bằng HTTP probe bên dưới
        },
      );

      if (gen != _generation || _intentionallyStopped) return false;

      _emitState(
        mode: RemoteTunnelMode.cloudflareNamed,
        state: RemoteTunnelState.running,
        publicUrl: cleanUrl,
        statusMessage: 'Tên miền cố định $cleanUrl đang hoạt động qua Cloudflare Tunnel.',
        errorMessage: '',
      );
      return true;
    } catch (e) {
      if (gen != _generation) return false;
      await _terminateProcessOnly();
      _emitState(
        mode: RemoteTunnelMode.cloudflareNamed,
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Không thể kết nối Named Tunnel: $e',
      );
      return false;
    }
  }

  /// Kích hoạt chế độ địa chỉ công khai tùy chọn (Tailscale VPN, Reverse Proxy, Nginx, VPS Tunnel).
  Future<bool> activateCustomPublicUrl(String rawUrl) async {
    await _terminateProcessOnly();
    ++_generation;
    _intentionallyStopped = true;
    final normalized = normalizePublicUrl(rawUrl);
    if (normalized.isEmpty) {
      _emitState(
        mode: RemoteTunnelMode.customUrl,
        state: RemoteTunnelState.stopped,
        publicUrl: '',
        statusMessage: 'Chưa nhập địa chỉ công khai hoặc IP Tailscale.',
        errorMessage: '',
      );
      return false;
    }
    _emitState(
      mode: RemoteTunnelMode.customUrl,
      state: RemoteTunnelState.running,
      publicUrl: normalized,
      statusMessage: 'Đang sử dụng địa chỉ truy cập từ xa: $normalized',
      errorMessage: '',
    );
    return true;
  }

  /// Tắt đường hầm Internet và giải phóng hoàn toàn tiến trình con.
  Future<void> stop({bool resetModeToOff = true}) async {
    _intentionallyStopped = true;
    ++_generation;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _terminateProcessOnly();
    _emitState(
      mode: resetModeToOff ? RemoteTunnelMode.off : _mode,
      state: RemoteTunnelState.stopped,
      publicUrl: '',
      statusMessage: '',
      errorMessage: '',
      installProgress: 0.0,
    );
  }

  Future<void> _terminateProcessOnly() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final stdoutSub = _stdoutSub;
    final stderrSub = _stderrSub;
    _stdoutSub = null;
    _stderrSub = null;
    try {
      await stdoutSub?.cancel();
    } catch (_) {}
    try {
      await stderrSub?.cancel();
    } catch (_) {}

    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            try {
              proc.kill(ProcessSignal.sigkill);
            } catch (_) {}
            return -1;
          },
        );
      } catch (_) {
        try {
          proc.kill();
        } catch (_) {}
      }
    }
  }

  void _scheduleReconnect(int expectedGeneration) {
    if (_intentionallyStopped || expectedGeneration != _generation) return;
    if (_restartAttempts >= 3) {
      _emitState(
        state: RemoteTunnelState.error,
        publicUrl: '',
        errorMessage: 'Đường hầm Internet bị ngắt kết nối nhiều lần. Hãy nhấn khởi động lại.',
      );
      return;
    }
    _restartAttempts++;
    final delaySec = _restartAttempts * 3;
    _emitState(
      state: RemoteTunnelState.starting,
      statusMessage: 'Đường hầm vừa ngắt, tự kết nối lại sau ${delaySec}s (lần $_restartAttempts/3)...',
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (_intentionallyStopped || expectedGeneration != _generation) return;
      if (_mode == RemoteTunnelMode.cloudflareQuick) {
        unawaited(startQuickTunnel(localPort: _lastLocalPort, verifyToken: _lastVerifyToken));
      } else if (_mode == RemoteTunnelMode.cloudflareNamed) {
        unawaited(startNamedTunnel(
          tunnelToken: _lastNamedToken,
          publicUrl: _lastNamedUrl,
          verifyToken: _lastVerifyToken,
        ));
      }
    });
  }

  /// Kiểm tra bản ghi DNS công khai qua Cloudflare DoH (`1.1.1.1`) để không gây nhiễm NXDOMAIN cache cục bộ.
  Future<bool> _waitForCloudflareDohReady(
    String tunnelUrl, {
    required int generation,
  }) async {
    final host = Uri.tryParse(tunnelUrl)?.host ?? '';
    if (host.isEmpty) return false;
    final dohUri = Uri.parse('https://1.1.1.1/dns-query?name=${Uri.encodeQueryComponent(host)}&type=A');
    for (var attempt = 0; attempt < 12; attempt++) {
      if (_intentionallyStopped || generation != _generation) return false;
      try {
        final res = await _httpClient
            .get(dohUri, headers: {'Accept': 'application/dns-json'})
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data is Map && data['Status'] == 0 && data['Answer'] is List && (data['Answer'] as List).isNotEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            return true;
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }
    return false;
  }

  /// Chờ Cloudflare Edge định tuyến xong và xác nhận yêu cầu đi qua Internet chạm được App Chính.
  Future<bool> _waitForPublicEndpointReady(
    String tunnelUrl, {
    String? verifyToken,
    required int generation,
  }) async {
    final uri = Uri.parse('$tunnelUrl${ApiConstants.epRemoteInfo}');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (verifyToken != null && verifyToken.isNotEmpty) 'Authorization': 'Bearer $verifyToken',
    };
    for (var attempt = 0; attempt < 6; attempt++) {
      if (_intentionallyStopped || generation != _generation) return false;
      try {
        final res = await _httpClient.get(uri, headers: headers).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200 || res.statusCode == 401) {
          return true;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return false;
  }
}
