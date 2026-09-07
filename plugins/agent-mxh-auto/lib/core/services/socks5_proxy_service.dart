import 'dart:async';
import 'dart:io';
import '../../models/server_model.dart';

class Socks5Session {
  final int localPort;
  final ServerModel server;
  final String ip;
  final Process sshProcess;
  final File? askpassFile;
  Process? browserProcess;

  Socks5Session({
    required this.localPort,
    required this.server,
    required this.ip,
    required this.sshProcess,
    this.askpassFile,
  });

  Future<void> stop() async {
    try {
      sshProcess.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      if (askpassFile != null && askpassFile!.existsSync()) {
        askpassFile!.deleteSync();
      }
    } catch (_) {}
    try {
      browserProcess?.kill();
    } catch (_) {}
  }
}

class Socks5ProxyService {
  static final Socks5ProxyService _instance = Socks5ProxyService._internal();
  factory Socks5ProxyService() => _instance;
  Socks5ProxyService._internal();

  final Map<String, Socks5Session> _activeSessions = {};

  bool isIpRunning(String ip) => _activeSessions.containsKey(ip);

  Socks5Session? getSession(String ip) => _activeSessions[ip];

  /// Khởi tạo Dynamic SOCKS5 Proxy thông qua OpenSSH native tunnel (-D)
  /// Đảm bảo hỗ trợ hoàn hảo cả TCP lẫn phân giải tên miền (DNS remote)
  Future<Socks5Session> startSocks5Server({
    required ServerModel server,
    required String ip,
  }) async {
    // 1. Nếu đã có session đang chạy và còn sống thì tái sử dụng
    if (_activeSessions.containsKey(ip)) {
      final existing = _activeSessions[ip]!;
      try {
        final check = await Socket.connect('127.0.0.1', existing.localPort, timeout: const Duration(milliseconds: 500));
        await check.close();
        return existing;
      } catch (_) {
        await existing.stop();
        _activeSessions.remove(ip);
      }
    }

    // 2. Tìm cổng local còn trống
    final tempServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final localPort = tempServer.port;
    await tempServer.close();

    // 3. Chuẩn bị file script Askpass để cấp mật khẩu tự động cho lệnh ssh
    final homeDir = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final runDir = Directory('$homeDir/.tadu_ai_agent/tmp');
    if (!runDir.existsSync()) {
      runDir.createSync(recursive: true);
    }

    final askpassPath = '${runDir.path}/ssh_askpass_${DateTime.now().millisecondsSinceEpoch}_$localPort.sh';
    final askpassFile = File(askpassPath);

    // Escape ký tự an toàn cho shell script
    final escapedPass = server.sshPass.replaceAll(r'\', r'\\').replaceAll(r'"', r'\"').replaceAll(r'$', r'\$');
    askpassFile.writeAsStringSync('#!/bin/sh\necho "$escapedPass"\n');
    await Process.run('chmod', ['700', askpassPath]);

    // 4. Khởi chạy tiến trình OpenSSH với cờ Dynamic SOCKS5 (-D)
    final environment = Map<String, String>.from(Platform.environment);
    environment['SSH_ASKPASS'] = askpassPath;
    environment['SSH_ASKPASS_REQUIRE'] = 'force';
    if (!environment.containsKey('DISPLAY') || environment['DISPLAY']!.isEmpty) {
      environment['DISPLAY'] = ':0';
    }

    // SSH server luôn kết nối vào server.serverIp với port và user chính xác của máy chủ
    final sshHost = server.serverIp;

    // Tính toán remote socks5 port dựa theo IP nếu là Server hỗ trợ Multi-IP Proxy (Server 100)
    final parts = ip.split('.');
    int? remoteSocksPort;
    if (parts.length == 4) {
      final p2 = int.tryParse(parts[2]);
      final p3 = int.tryParse(parts[3]);
      if (p2 != null && p3 != null) {
        remoteSocksPort = 20000 + (p2 * 256 + p3) % 10000;
      }
    }

    final isAlias = ip != server.serverIp;
    final useRemoteSocks = remoteSocksPort != null && (isAlias || server.serverIp == '103.74.116.119');
    final List<String> forwardArgs;
    if (useRemoteSocks) {
      // Forward cổng local tới đúng SOCKS5 Proxy trên VPS đã bind riêng cho IP Alias này
      forwardArgs = ['-L', '127.0.0.1:$localPort:127.0.0.1:$remoteSocksPort'];
    } else {
      // Fallback mặc định dùng OpenSSH native Dynamic SOCKS5 (-D)
      forwardArgs = ['-D', '127.0.0.1:$localPort'];
    }

    final sshArgs = [
      '-N',
      ...forwardArgs,
      '-p',
      server.sshPort.toString(),
      '-o',
      'StrictHostKeyChecking=no',
      '-o',
      'UserKnownHostsFile=/dev/null',
      '-o',
      'ExitOnForwardFailure=yes',
      '-o',
      'ServerAliveInterval=15',
      '-o',
      'ServerAliveCountMax=3',
      '${server.sshUser}@$sshHost',
    ];

    final sshProcess = await Process.start(
      'ssh',
      sshArgs,
      environment: environment,
      mode: ProcessStartMode.normal,
    );

    // Xử lý khi tiến trình kết thúc
    sshProcess.exitCode.then((code) {
      if (askpassFile.existsSync()) {
        try {
          askpassFile.deleteSync();
        } catch (_) {}
      }
      _activeSessions.remove(ip);
    });

    // 5. Chờ socket SOCKS5 sẵn sàng chấp nhận kết nối (tối đa 15 giây do SSH GSSAPI/Kerberos có thể trễ vài giây)
    bool ready = false;
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        final testSock = await Socket.connect('127.0.0.1', localPort, timeout: const Duration(milliseconds: 300));
        await testSock.close();
        ready = true;
        break;
      } catch (_) {}
    }

    if (!ready) {
      sshProcess.kill(ProcessSignal.sigterm);
      if (askpassFile.existsSync()) {
        try {
          askpassFile.deleteSync();
        } catch (_) {}
      }
      throw Exception('Không thể khởi tạo đường hầm SOCKS5 tới máy chủ $sshHost:${server.sshPort}. Vui lòng kiểm tra lại thông tin đăng nhập SSH.');
    }

    final session = Socks5Session(
      localPort: localPort,
      server: server,
      ip: ip,
      sshProcess: sshProcess,
      askpassFile: askpassFile,
    );

    _activeSessions[ip] = session;
    return session;
  }

  /// Mở trình duyệt trên máy local với cấu hình SOCKS5 trỏ qua SSH Server
  Future<bool> launchBrowserWithSocks5({
    required ServerModel server,
    required String ip,
    String? startUrl,
  }) async {
    final session = await startSocks5Server(server: server, ip: ip);
    final socks5Proxy = 'socks5://127.0.0.1:${session.localPort}';

    // Đường dẫn thư mục dữ liệu riêng cho từng IP để cô lập profile không ảnh hưởng trình duyệt gốc
    final homeDir = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final profileDir = Directory('$homeDir/.tadu_ai_agent/browser_profiles/ip_$sanitizedIp');
    if (!profileDir.existsSync()) {
      profileDir.createSync(recursive: true);
    }

    final targetUrl = (startUrl != null && startUrl.isNotEmpty) ? startUrl : 'https://whoer.net';

    // Ưu tiên tìm trình duyệt khả dụng trên hệ thống Linux
    final browserCandidates = [
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/opera-gx',
      '/usr/bin/opera',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/usr/bin/brave-browser',
      '/snap/bin/firefox',
      '/usr/bin/firefox',
    ];

    String? executable;
    for (final b in browserCandidates) {
      if (File(b).existsSync()) {
        executable = b;
        break;
      }
    }

    if (executable == null) {
      throw Exception('Không tìm thấy trình duyệt khả dụng (Chrome, Opera, Chromium, Firefox) trên hệ thống local.');
    }

    final isFirefox = executable.contains('firefox');

    List<String> args;
    if (isFirefox) {
      args = [
        '-new-tab',
        targetUrl,
      ];
    } else {
      // Chrome / Chromium / Opera: Sử dụng cờ socks5 chính xác và cô lập hồ sơ trình duyệt
      args = [
        '--proxy-server=$socks5Proxy',
        '--user-data-dir=${profileDir.path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--ignore-certificate-errors',
        '--disable-blink-features=AutomationControlled',
        targetUrl,
      ];
    }

    try {
      final proc = await Process.start(
        executable,
        args,
        mode: ProcessStartMode.detached,
      );
      session.browserProcess = proc;
      return true;
    } catch (e) {
      throw Exception('Lỗi khi mở trình duyệt: $e');
    }
  }

  Future<void> stopSession(String ip) async {
    final session = _activeSessions.remove(ip);
    if (session != null) {
      await session.stop();
    }
  }
}
