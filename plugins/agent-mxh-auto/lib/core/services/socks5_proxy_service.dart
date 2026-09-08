import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/server_model.dart';
import 'adb_manager_service.dart';

class Socks5Session {
  final int localPort;
  final ServerModel server;
  final String ip;
  final Process sshProcess;
  final File? askpassFile;
  Process? browserProcess;
  Process? deviceProcess;
  Process? httpBridgeProcess;
  int? emulatorPort;
  String? remoteDeviceAddress;

  Socks5Session({
    required this.localPort,
    required this.server,
    required this.ip,
    required this.sshProcess,
    this.askpassFile,
    this.remoteDeviceAddress,
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
    try {
      deviceProcess?.kill();
    } catch (_) {}
    try {
      httpBridgeProcess?.kill();
    } catch (_) {}
  }
}

class Socks5ProxyService extends ChangeNotifier {
  static final Socks5ProxyService _instance = Socks5ProxyService._internal();
  factory Socks5ProxyService() => _instance;
  Timer? _watchdogTimer;

  Socks5ProxyService._internal() {
    _startWatchdog();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    // Quét định kỳ mỗi 1.5 giây để phát hiện ngay khi trình duyệt bị tắt bằng tay (tắt cứng)
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _checkTerminatedBrowsers();
    });
  }

  /// Kiểm tra các session đang ghi nhận, nếu cả trình duyệt lẫn mobile device của session không còn tiến trình nào chạy thì dọn dẹp
  void _checkTerminatedBrowsers() {
    if (_activeSessions.isEmpty) return;
    final deadIps = <String>[];
    for (final entry in _activeSessions.entries) {
      final ip = entry.key;
      // Kiểm tra thực tế trên hệ thống xem profile IP này còn tiến trình trình duyệt hoặc device nào không
      if (!_isSystemProcessAliveForIp(ip) && !_isDeviceProcessAliveForIp(ip)) {
        deadIps.add(ip);
      }
    }

    if (deadIps.isNotEmpty) {
      for (final ip in deadIps) {
        final session = _activeSessions.remove(ip);
        session?.stop();
      }
      notifyListeners();
    }
  }

  final Map<String, Socks5Session> _activeSessions = {};

  bool isIpRunning(String ip) => _activeSessions.containsKey(ip);

  Socks5Session? getSession(String ip) => _activeSessions[ip];

  /// Quét xem trên hệ thống OS có tiến trình trình duyệt nào đang chạy profile của IP này không
  bool _isSystemProcessAliveForIp(String ip) {
    try {
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final needle = 'browser_profiles/ip_$sanitizedIp';
      final procDir = Directory('/proc');
      if (procDir.existsSync()) {
        final myPid = pid;
        for (final entity in procDir.listSync(followLinks: false)) {
          final baseName = entity.path.split('/').last;
          final p = int.tryParse(baseName);
          if (p == null || p == myPid) continue;
          try {
            final cmdFile = File('${entity.path}/cmdline');
            if (cmdFile.existsSync()) {
              final bytes = cmdFile.readAsBytesSync();
              final cmd = String.fromCharCodes(bytes);
              if (cmd.contains(needle) && !cmd.contains('device_profiles') && !cmd.contains('python') && !cmd.contains('pgrep')) {
                return true;
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return false;
  }

  /// Quét xem trên hệ thống OS có tiến trình mobile device nào đang chạy cho IP này không
  bool _isDeviceProcessAliveForIp(String ip) {
    try {
      final session = _activeSessions[ip];
      final port = session?.emulatorPort;
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final needleProfile = 'device_profiles/ip_$sanitizedIp';
      final needlePort = port != null ? '-port\x00$port' : null;
      final procDir = Directory('/proc');
      if (procDir.existsSync()) {
        final myPid = pid;
        for (final entity in procDir.listSync(followLinks: false)) {
          final baseName = entity.path.split('/').last;
          final p = int.tryParse(baseName);
          if (p == null || p == myPid) continue;
          try {
            final cmdFile = File('${entity.path}/cmdline');
            if (cmdFile.existsSync()) {
              final bytes = cmdFile.readAsBytesSync();
              final cmd = String.fromCharCodes(bytes);
              final matchesProfile = cmd.contains(needleProfile);
              final matchesPort = needlePort != null && cmd.contains(needlePort);
              if ((matchesProfile || matchesPort) && !cmd.contains('python') && !cmd.contains('pgrep')) {
                return true;
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return false;
  }

  /// Kiểm tra xem trình duyệt gắn với IP này có đang mở hay không
  bool isBrowserRunningForIp(String ip) {
    return _isSystemProcessAliveForIp(ip);
  }

  /// Kiểm tra xem mobile device gắn với IP này có đang chạy hay không
  bool isDeviceRunningForIp(String ip) {
    final session = _activeSessions[ip];
    if (session?.remoteDeviceAddress != null) {
      return true;
    }
    return _isDeviceProcessAliveForIp(ip);
  }

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
      notifyListeners();
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
    notifyListeners();
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

    // Tắt translate option trong file cấu hình Preferences của profile Chrome
    try {
      final defaultDir = Directory('${profileDir.path}/Default');
      if (!defaultDir.existsSync()) {
        defaultDir.createSync(recursive: true);
      }
      final prefFile = File('${defaultDir.path}/Preferences');
      Map<String, dynamic> prefData = {};
      if (prefFile.existsSync()) {
        try {
          final content = prefFile.readAsStringSync();
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic>) {
              prefData = decoded;
            }
          }
        } catch (_) {}
      }
      prefData['translate'] = {'enabled': false};
      prefData['translate_blocked_hosts'] = [];
      prefFile.writeAsStringSync(jsonEncode(prefData));
    } catch (_) {}

    final targetUrl = (startUrl != null && startUrl.isNotEmpty) ? startUrl : 'https://type.vn';

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
      // Tắt triệt để tính năng Translate và thanh thông báo "You are using an unsupported command-line flag..."
      args = [
        '--test-type',
        '--disable-features=Translate,TranslateUI',
        '--disable-translate',
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
      notifyListeners();
      return true;
    } catch (e) {
      throw Exception('Lỗi khi mở trình duyệt: $e');
    }
  }

  /// Tìm binary Android Emulator trên hệ thống
  String? _findAndroidEmulatorExecutable() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/Android/Sdk/emulator/emulator',
      '$home/android-sdk/emulator/emulator',
      '/opt/android-sdk/emulator/emulator',
      '/usr/bin/emulator',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }
    return null;
  }

  /// Tìm danh sách AVD khả dụng trên máy tính
  Future<List<String>> getAvailableAvds() async {
    final emulatorBin = _findAndroidEmulatorExecutable();
    if (emulatorBin == null) return [];
    try {
      final res = await Process.run(emulatorBin, ['-list-avds']);
      if (res.exitCode == 0) {
        final lines = (res.stdout as String).split('\n');
        return lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Khởi chạy thiết bị Android (Emulator chuẩn Android Studio hoặc Kết nối Ngoại vi ADB WiFi)
  /// Định tuyến toàn bộ lưu lượng mạng máy ảo qua proxy SOCKS5 của chính IP đó
  Future<bool> launchDeviceWithSocks5({
    required ServerModel server,
    required String ip,
    String? avdName,
    String? startUrl,
    String? remoteDeviceAddress,
    String deviceType = 'mobile',
  }) async {
    final session = await startSocks5Server(server: server, ip: ip);

    // TRƯỜNG HỢP 1: Kết nối thiết bị Android ngoại vi qua WiFi/TCP-IP và ép HTTP Proxy vào máy
    if (remoteDeviceAddress != null && remoteDeviceAddress.trim().isNotEmpty) {
      final addr = remoteDeviceAddress.trim();
      try {
        await connectRemoteDevice(addr);
        session.remoteDeviceAddress = addr;

        // 1. Khởi tạo HTTP Bridge cho phép truy cập từ mạng LAN (0.0.0.0) chuyển tiếp vào SOCKS5 của IP này
        final bridgeScript = File('${Directory.current.path}/lib/core/services/scripts/socks2http_bridge.py');
        if (bridgeScript.existsSync()) {
          final tempSocket = await ServerSocket.bind('0.0.0.0', 0);
          final httpProxyPort = tempSocket.port;
          await tempSocket.close();

          try {
            session.httpBridgeProcess?.kill();
          } catch (_) {}

          final bridgeProc = await Process.start(
            'python3',
            [
              bridgeScript.path,
              httpProxyPort.toString(),
              '127.0.0.1',
              session.localPort.toString(),
              '0.0.0.0',
            ],
            mode: ProcessStartMode.normal,
          );
          session.httpBridgeProcess = bridgeProc;

          final completer = Completer<void>();
          bridgeProc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
            if (line.contains('READY') && !completer.isCompleted) {
              completer.complete();
            }
          });
          bridgeProc.stderr.transform(utf8.decoder).listen((_) {});

          await Future.any([
            completer.future,
            Future.delayed(const Duration(seconds: 3)),
          ]);

          // 2. Lấy địa chỉ IP mạng LAN của máy host để điện thoại có thể bắt sóng
          final hostLanIp = await _getLocalHostIp();

          // 3. Ép HTTP Proxy vào hệ thống Android qua lệnh ADB
          await setAdbGlobalProxy(addr, hostLanIp, httpProxyPort);
        }

        notifyListeners();
        return true;
      } catch (e) {
        throw Exception('Không thể kết nối thiết bị ngoại vi $addr: $e');
      }
    }

    // TRƯỜNG HỢP 2: Khởi chạy Android Emulator chuẩn Android Studio trên máy Local
    // 1. Kiểm tra Android Emulator binary
    final emulatorBin = _findAndroidEmulatorExecutable();
    if (emulatorBin == null) {
      throw Exception('Không tìm thấy Android Emulator trên hệ thống (~/Android/Sdk/emulator/emulator).');
    }

    // 2. Xác định tên AVD để khởi chạy
    String targetAvd = avdName ?? '';
    if (targetAvd.isEmpty) {
      final avds = await getAvailableAvds();
      if (avds.isEmpty) {
        throw Exception('Chưa tạo bất kỳ thiết bị Android ảo (AVD) nào trong Android Studio.');
      }
      targetAvd = avds.first;
    }

    // 3. Khởi tạo cổng HTTP Proxy cục bộ thông qua python bridge tới SOCKS5 port của IP
    final bridgeScript = File('${Directory.current.path}/lib/core/services/scripts/socks2http_bridge.py');
    if (!bridgeScript.existsSync()) {
      throw Exception('Không tìm thấy script cầu nối proxy: ${bridgeScript.path}');
    }

    // Cấp phát một cổng ngẫu nhiên khả dụng cho HTTP Proxy
    final tempSocket = await ServerSocket.bind('127.0.0.1', 0);
    final httpProxyPort = tempSocket.port;
    await tempSocket.close();

    // Dừng bridge cũ nếu có
    try {
      session.httpBridgeProcess?.kill();
    } catch (_) {}

    final bridgeProc = await Process.start(
      'python3',
      [
        bridgeScript.path,
        httpProxyPort.toString(),
        '127.0.0.1',
        session.localPort.toString(),
      ],
      mode: ProcessStartMode.normal,
    );
    session.httpBridgeProcess = bridgeProc;

    // Đợi bridge sẵn sàng
    final completer = Completer<void>();
    bridgeProc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.contains('READY') && !completer.isCompleted) {
        completer.complete();
      }
    });
    bridgeProc.stderr.transform(utf8.decoder).listen((_) {});

    await Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 3)),
    ]);

    // 4. Dọn dẹp các file lock rác (nếu phiên trước bị tắt đột ngột)
    final homeDir = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    try {
      final avdDir = Directory('$homeDir/.android/avd/$targetAvd.avd');
      if (avdDir.existsSync()) {
        for (final f in avdDir.listSync()) {
          if (f.path.endsWith('.lock')) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 5. Cấp phát console port (chẵn) cho emulator từ 5554 đến 5584
    int consolePort = 5554;
    for (int p = 5554; p <= 5584; p += 2) {
      if (!_isPortInUse(p) && !_isPortInUse(p + 1)) {
        consolePort = p;
        break;
      }
    }
    session.emulatorPort = consolePort;

    final emulatorArgs = [
      '-avd', targetAvd,
      '-http-proxy', 'http://127.0.0.1:$httpProxyPort',
      '-port', consolePort.toString(),
      '-netdelay', 'none',
      '-netspeed', 'full',
      '-gpu', 'host',
      '-no-boot-anim',
      '-no-snapshot-load',
      if (deviceType == 'tablet') ...[
        '-skin', '1200x1920',
      ],
    ];

    try {
      final proc = await Process.start(
        emulatorBin,
        emulatorArgs,
        mode: ProcessStartMode.detached,
      );
      session.deviceProcess = proc;

      // Đánh thức màn hình và mở khóa AVD tự động ngầm để tránh màn hình ngủ đen ngòm
      _autoWakeAndUnlockAvd(consolePort);

      notifyListeners();
      return true;
    } catch (e) {
      session.httpBridgeProcess?.kill();
      throw Exception('Lỗi khi khởi chạy Android Emulator: $e');
    }
  }

  /// Tự động kiểm tra và đánh thức, mở khóa màn hình AVD tránh màn hình đen ngủ
  void _autoWakeAndUnlockAvd(int consolePort) {
    Future.microtask(() async {
      try {
        final adbBin = await _findAdbExecutable();
        final serial = 'emulator-$consolePort';

        // Đợi thiết bị boot xong và sẵn sàng nhận input (tối đa 40 giây)
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(seconds: 2));
          final res = await Process.run(adbBin, ['-s', serial, 'shell', 'getprop', 'sys.boot_completed']);
          if ((res.stdout as String).trim() == '1') {
            break;
          }
        }

        // 1. Gửi phím WAKEUP (224) và POWER (26) để bật sáng màn hình
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'keyevent', '224']);
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'keyevent', '26']);
        await Future.delayed(const Duration(milliseconds: 400));
        // 2. Gửi phím MENU (82) để mở khóa màn hình
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'keyevent', '82']);
        // 3. Vuốt nhẹ lên mở khóa phòng trường hợp màn hình khóa cần vuốt
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'swipe', '500', '1500', '500', '500', '200']);
      } catch (_) {}
    });
  }

  bool _isPortInUse(int port) {
    try {
      for (final s in _activeSessions.values) {
        if (s.emulatorPort == port) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Đóng trình duyệt và dừng toàn bộ kết nối SOCKS5 của IP
  Future<void> stopSession(String ip) async {
    final session = _activeSessions.remove(ip);
    if (session != null) {
      if (session.remoteDeviceAddress != null) {
        await disconnectRemoteDevice(session.remoteDeviceAddress!);
      }
      await session.stop();
    }
    // Dừng triệt để các tiến trình trình duyệt và device gắn với profile của IP này nếu còn chạy ngầm
    try {
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await Process.run('pkill', ['-f', 'browser_profiles/ip_$sanitizedIp']);
      await Process.run('pkill', ['-f', 'device_profiles/ip_$sanitizedIp']);
      await Process.run('pkill', ['-f', 'ip_$sanitizedIp']);
    } catch (_) {}
    notifyListeners();
  }

  /// Đóng riêng trình duyệt của IP mà không làm mất hầm SOCKS5 nếu device vẫn đang chạy
  Future<void> closeBrowserForIp(String ip) async {
    final session = _activeSessions[ip];
    if (session?.browserProcess != null) {
      try {
        session!.browserProcess!.kill();
      } catch (_) {}
      session?.browserProcess = null;
    }
    try {
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await Process.run('pkill', ['-f', 'browser_profiles/ip_$sanitizedIp']);
    } catch (_) {}

    // Nếu device cũng không còn chạy thì giải phóng hoàn toàn session SOCKS5
    if (!_isDeviceProcessAliveForIp(ip)) {
      final s = _activeSessions.remove(ip);
      if (s != null) {
        await s.stop();
      }
    }

    notifyListeners();
  }

  /// Đóng riêng mobile device của IP mà không làm mất hầm SOCKS5 nếu trình duyệt vẫn đang chạy
  Future<void> closeDeviceForIp(String ip) async {
    final session = _activeSessions[ip];
    if (session?.remoteDeviceAddress != null) {
      try {
        await disconnectRemoteDevice(session!.remoteDeviceAddress!);
      } catch (_) {}
      session?.remoteDeviceAddress = null;
    }
    if (session?.deviceProcess != null) {
      try {
        session!.deviceProcess!.kill();
      } catch (_) {}
      session?.deviceProcess = null;
    }
    if (session?.httpBridgeProcess != null) {
      try {
        session!.httpBridgeProcess!.kill();
      } catch (_) {}
      session?.httpBridgeProcess = null;
    }
    try {
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await Process.run('pkill', ['-f', 'device_profiles/ip_$sanitizedIp']);
      // Dừng emulator của port đó qua adb nếu có
      if (session?.emulatorPort != null) {
        final adbBin = await _findAdbExecutable();
        await Process.run(adbBin, ['-s', 'emulator-${session!.emulatorPort}', 'emu', 'kill']);
      }
    } catch (_) {}

    // Nếu browser cũng không còn chạy thì giải phóng hoàn toàn session SOCKS5
    if (!_isSystemProcessAliveForIp(ip)) {
      final s = _activeSessions.remove(ip);
      if (s != null) {
        await s.stop();
      }
    }

    notifyListeners();
  }

  /// Tìm và cung cấp đường dẫn binary adb (tự động tải và nhúng nếu hệ thống chưa có)
  Future<String> _findAdbExecutable() async {
    return await AdbManagerService().resolveAdbPath();
  }

  /// Kết nối tới một thiết bị Android ngoại vi qua mạng WiFi / TCP IP (ví dụ: 192.168.1.227:38233)
  Future<String> connectRemoteDevice(String address) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) {
      throw Exception('Địa chỉ thiết bị không được để trống.');
    }
    final adbBin = await _findAdbExecutable();
    final res = await Process.run(adbBin, ['connect', cleanAddress]);
    final output = ((res.stdout as String) + (res.stderr as String)).trim();

    if (output.toLowerCase().contains('connected to') || output.toLowerCase().contains('already connected to')) {
      notifyListeners();
      return output;
    } else {
      throw Exception(output.isNotEmpty ? output : 'Không thể kết nối tới thiết bị $cleanAddress');
    }
  }

  /// Lấy địa chỉ IP nội bộ (LAN) của máy tính trạm đang kết nối cùng dải mạng với thiết bị
  Future<String> _getLocalHostIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        // Ưu tiên interface WiFi hoặc Ethernet LAN (bỏ qua loopback và docker/br/tun)
        final name = iface.name.toLowerCase();
        if (name.contains('lo') || name.contains('docker') || name.contains('br-') || name.contains('tun')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Ép cấu hình HTTP Proxy vào thiết bị Android qua lệnh ADB
  Future<void> setAdbGlobalProxy(String serial, String host, int port) async {
    final adbBin = await _findAdbExecutable();
    final cleanSerial = serial.trim();
    try {
      // 1. Cấu hình định dạng chuẩn http_proxy
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'http_proxy', '$host:$port']);
      // 2. Cấu hình thêm host và port riêng lẻ (cho các dòng máy OEM như Samsung, Xiaomi, Pixel)
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'global_http_proxy_host', host]);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'global_http_proxy_port', port.toString()]);
      // 3. Khởi động lại các trình duyệt nền để nhận diện proxy mới ngay lập tức
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'am', 'force-stop', 'com.android.chrome']);
    } catch (_) {}
  }

  /// Gỡ bỏ cấu hình HTTP Proxy khỏi thiết bị Android qua ADB về mặc định
  Future<void> clearAdbGlobalProxy(String serial) async {
    final adbBin = await _findAdbExecutable();
    final cleanSerial = serial.trim();
    try {
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'http_proxy', ':0']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'delete', 'global', 'http_proxy']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'delete', 'global', 'global_http_proxy_host']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'delete', 'global', 'global_http_proxy_port']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'am', 'force-stop', 'com.android.chrome']);
    } catch (_) {}
  }

  /// Ngắt kết nối một thiết bị ngoại vi qua ADB và gỡ proxy
  Future<void> disconnectRemoteDevice(String address) async {
    final adbBin = await _findAdbExecutable();
    final cleanAddr = address.trim();
    await clearAdbGlobalProxy(cleanAddr);
    await Process.run(adbBin, ['disconnect', cleanAddr]);
    notifyListeners();
  }

  /// Lấy danh sách các thiết bị ngoại vi / vật lý đang kết nối qua ADB
  Future<List<Map<String, String>>> getConnectedAdbDevices() async {
    final adbBin = await _findAdbExecutable();
    final res = await Process.run(adbBin, ['devices', '-l']);

    final lines = (res.stdout as String).split('\n');
    final List<Map<String, String>> devices = [];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('List of devices')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final serial = parts[0];
        final state = parts[1];
        String model = 'Unknown';
        for (final p in parts) {
          if (p.startsWith('model:')) {
            model = p.replaceFirst('model:', '');
            break;
          }
        }
        final isWifi = serial.contains(':');
        devices.add({
          'serial': serial,
          'state': state,
          'model': model,
          'type': isWifi ? 'WiFi Remote' : (serial.startsWith('emulator-') ? 'Local AVD' : 'USB Device'),
        });
      }
    }
    return devices;
  }
}
