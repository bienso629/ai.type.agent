import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pty_desktop/flutter_pty.dart';
import 'package:web_socket_channel/io.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../core/services/native_ssh_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';
import '../models/terminal_pane_model.dart';

export '../models/terminal_pane_model.dart';

class TerminalProvider extends ChangeNotifier {
  final List<TerminalPaneItem> _panes = [];
  int _activePaneIndex = 0;
  String? _activeSubPaneId;
  bool _showVirtualKeyboard = false;
  bool _isInitialized = false;
  final StorageService _storage = StorageService();

  List<TerminalPaneItem> get panes => List.unmodifiable(_panes);
  int get activePaneIndex => _activePaneIndex;
  String? get activeSubPaneId => _activeSubPaneId;
  bool get showVirtualKeyboard => _showVirtualKeyboard;
  bool get isInitialized => _isInitialized;

  TerminalPaneItem? get activeRootPane {
    if (_panes.isEmpty) return null;
    if (_activePaneIndex >= 0 && _activePaneIndex < _panes.length) {
      return _panes[_activePaneIndex];
    }
    return _panes.first;
  }

  TerminalPaneItem? get activePane {
    final root = activeRootPane;
    if (root == null) return null;
    if (_activeSubPaneId != null && root.childPane != null && root.childPane!.id == _activeSubPaneId) {
      return root.childPane;
    }
    return root;
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadSavedTerminalSessions();
  }

  @visibleForTesting
  void seedPanesForTest(
    List<TerminalPaneItem> seededPanes, {
    int activeIndex = 0,
    String? activeSubPaneId,
  }) {
    _isInitialized = true;
    _panes
      ..clear()
      ..addAll(seededPanes);
    _activePaneIndex = activeIndex;
    _activeSubPaneId = activeSubPaneId;
    notifyListeners();
  }

  Future<void> _loadSavedTerminalSessions() async {
    try {
      final savedData = await _storage.getTerminalSessions();
      if (savedData != null && savedData.isNotEmpty) {
        final decoded = json.decode(savedData);
        if (decoded is Map<String, dynamic> && decoded['panes'] is List) {
          final rawPanes = decoded['panes'] as List;
          final loadedPanes = <TerminalPaneItem>[];
          for (final raw in rawPanes) {
            if (raw is Map<String, dynamic>) {
              loadedPanes.add(TerminalPaneItem.fromJson(raw));
            }
          }

          if (loadedPanes.isNotEmpty) {
            _panes.clear();
            _panes.addAll(loadedPanes);
            _activePaneIndex = (decoded['activePaneIndex'] is int &&
                    decoded['activePaneIndex'] >= 0 &&
                    decoded['activePaneIndex'] < _panes.length)
                ? decoded['activePaneIndex'] as int
                : 0;
            _activeSubPaneId = decoded['activeSubPaneId'] as String?;
            notifyListeners();

            for (final pane in _panes) {
              _connectPane(pane);
              if (pane.childPane != null) {
                _connectPane(pane.childPane!);
              }
            }
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback: tạo tab đầu tiên với thư mục gần nhất
    String? initialDir;
    try {
      final recents = await _storage.getRecentScopes();
      if (recents.isNotEmpty && Directory(recents.first).existsSync()) {
        initialDir = recents.first;
      }
    } catch (_) {}

    final firstPane = TerminalPaneItem(
      id: 'pane_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Local Machine',
      isRemoteSsh: false,
      workingDirectory: initialDir,
    );
    _panes.clear();
    _panes.add(firstPane);
    _activePaneIndex = 0;
    _activeSubPaneId = null;
    notifyListeners();

    _connectPane(firstPane);
    saveTerminalSessions();
  }

  void syncCurrentWorkingDirectory(TerminalPaneItem pane) {
    if (pane.isRemoteSsh) return;
    try {
      final pid = pane.pty?.pid;
      if (pid != null && Platform.isLinux) {
        final link = Link('/proc/$pid/cwd');
        if (link.existsSync()) {
          final target = link.targetSync();
          if (target.isNotEmpty && Directory(target).existsSync() && target != pane.workingDirectory) {
            pane.workingDirectory = target;
            _storage.addRecentScope(target);
          }
        }
      }
    } catch (_) {}
  }

  void syncAllWorkingDirectories() {
    for (final p in _panes) {
      syncCurrentWorkingDirectory(p);
      if (p.childPane != null) {
        syncCurrentWorkingDirectory(p.childPane!);
      }
    }
  }

  Future<void> saveTerminalSessions() async {
    try {
      syncAllWorkingDirectories();
      final data = {
        'activePaneIndex': _activePaneIndex,
        'activeSubPaneId': _activeSubPaneId,
        'panes': _panes.map((p) => p.toJson()).toList(),
      };
      await _storage.setTerminalSessions(json.encode(data));
    } catch (_) {}
  }

  void setActivePaneIndex(int index) {
    if (index >= 0 && index < _panes.length && index != _activePaneIndex) {
      _activePaneIndex = index;
      _activeSubPaneId = null;
      saveTerminalSessions();
      notifyListeners();
    }
  }

  void setActiveSubPaneId(String? id) {
    _activeSubPaneId = id;
    saveTerminalSessions();
    notifyListeners();
  }

  void toggleVirtualKeyboard() {
    _showVirtualKeyboard = !_showVirtualKeyboard;
    notifyListeners();
  }

  void openPaneWithCommand(String command, String? workingDirectory) {
    if (_panes.length >= 6) {
      final pane = activePane;
      if (pane != null) {
        pane.terminal.write('$command\n');
        try {
          pane.pty?.write(utf8.encode('$command\n'));
          pane.sshSession?.stdin.add(utf8.encode('$command\n'));
          pane.remoteWs?.sink.add('$command\n');
        } catch (_) {}
      }
      return;
    }
    final id = 'pane_${DateTime.now().millisecondsSinceEpoch}';
    final targetDir = workingDirectory ?? activePane?.workingDirectory;
    final newPane = TerminalPaneItem(
      id: id,
      title: 'Local Machine',
      isRemoteSsh: false,
      workingDirectory: targetDir,
      initialCommand: command,
    );
    _panes.add(newPane);
    _activePaneIndex = _panes.length - 1;
    _activeSubPaneId = null;
    notifyListeners();

    _connectPane(newPane);
    saveTerminalSessions();
  }

  void addWindow({bool isSsh = false, ServerModel? srv, String? initialDirectory}) {
    if (_panes.length >= 6) return;
    final id = 'pane_${DateTime.now().millisecondsSinceEpoch}';

    String? targetDir = initialDirectory;
    if (!isSsh && (targetDir == null || targetDir.isEmpty)) {
      targetDir = activePane?.workingDirectory;
    }

    final newPane = TerminalPaneItem(
      id: id,
      title: isSsh ? (srv?.name ?? 'SSH Server') : 'Local Machine',
      isRemoteSsh: isSsh,
      server: srv,
      workingDirectory: targetDir,
    );
    _panes.add(newPane);
    _activePaneIndex = _panes.length - 1;
    _activeSubPaneId = null;
    notifyListeners();

    _connectPane(newPane);
    saveTerminalSessions();
  }

  void removeWindow(int index) {
    if (_panes.length <= 1) return;
    if (index < 0 || index >= _panes.length) return;
    final removed = _panes.removeAt(index);
    removed.dispose();

    if (_activePaneIndex >= _panes.length) {
      _activePaneIndex = _panes.length - 1;
    }
    _activeSubPaneId = null;
    saveTerminalSessions();
    notifyListeners();
  }

  void splitActiveWindow(TerminalSplitDirection direction, int windowIndex, TerminalPaneItem targetPane) {
    if (windowIndex < 0 || windowIndex >= _panes.length) return;
    final windowPane = _panes[windowIndex];

    if (direction == TerminalSplitDirection.none) {
      if (windowPane.childPane != null) {
        windowPane.childPane!.dispose();
        windowPane.childPane = null;
      }
      windowPane.splitDirection = TerminalSplitDirection.none;
      _activePaneIndex = windowIndex;
      _activeSubPaneId = null;
      saveTerminalSessions();
      notifyListeners();
      return;
    }

    if (windowPane.childPane == null) {
      final id = 'subpane_${DateTime.now().millisecondsSinceEpoch}';
      final newSubPane = TerminalPaneItem(
        id: id,
        title: targetPane.isRemoteSsh ? (targetPane.server?.name ?? 'SSH Server') : 'Local Machine',
        isRemoteSsh: targetPane.isRemoteSsh,
        server: targetPane.server,
        workingDirectory: targetPane.workingDirectory,
      );
      windowPane.childPane = newSubPane;
      _connectPane(newSubPane);
    }

    windowPane.splitDirection = direction;
    _activePaneIndex = windowIndex;
    _activeSubPaneId = windowPane.childPane?.id;
    saveTerminalSessions();
    notifyListeners();
  }

  void closeChildPane(int windowIndex) {
    if (windowIndex < 0 || windowIndex >= _panes.length) return;
    final windowPane = _panes[windowIndex];
    if (windowPane.childPane != null) {
      windowPane.childPane!.dispose();
      windowPane.childPane = null;
      windowPane.splitDirection = TerminalSplitDirection.none;
      _activeSubPaneId = null;
      saveTerminalSessions();
      notifyListeners();
    }
  }

  void renamePane(int index, String newTitle) {
    if (index < 0 || index >= _panes.length) return;
    final pane = _panes[index];
    if (newTitle.trim().isNotEmpty && newTitle.trim() != pane.title) {
      pane.title = newTitle.trim();
      saveTerminalSessions();
      notifyListeners();
    }
  }

  Future<void> setDirectoryForPane(TerminalPaneItem pane, String selectedDir) async {
    if (selectedDir.isEmpty || !Directory(selectedDir).existsSync()) return;
    pane.workingDirectory = selectedDir;
    await _storage.addRecentScope(selectedDir);
    await saveTerminalSessions();

    if (pane.isConnected) {
      sendCmdToActive('cd "$selectedDir"');
    } else {
      _connectPane(pane);
    }
    notifyListeners();
  }

  void sendCmdToActive(String cmd) {
    final pane = activePane;
    if (pane != null && pane.isConnected) {
      if (pane.isRemoteSsh && pane.sshSession != null) {
        pane.sshSession!.stdin.add(utf8.encode('$cmd\n'));
      } else if (pane.pty != null) {
        try {
          pane.pty!.write(utf8.encode('$cmd\n'));
        } catch (_) {}
      }
    }
  }

  void sendKeyToActive(String code) {
    final pane = activePane;
    if (pane != null && pane.isConnected) {
      if (pane.isRemoteSsh && pane.sshSession != null) {
        pane.sshSession!.stdin.add(utf8.encode(code));
      } else if (pane.pty != null) {
        try {
          pane.pty!.write(utf8.encode(code));
        } catch (_) {}
      }
    }
  }

  Future<void> connectPane(TerminalPaneItem pane) async {
    await _connectPane(pane);
  }

  Future<void> _connectPane(TerminalPaneItem pane) async {
    pane.cleanup();
    pane.isConnecting = true;
    pane.isConnected = false;
    notifyListeners();

    if (pane.isRemoteSsh) {
      await _connectSshPane(pane);
    } else {
      // Nếu thiết bị đang là App Phụ (Secondary) -> kết nối Terminal trực tiếp lên App Chính qua WebSocket
      if (!await ApiService().isNativeMode()) {
        await _connectRemotePrimaryPane(pane);
        return;
      }
      if (Platform.isIOS) {
        pane.isConnecting = false;
        pane.isConnected = false;
        pane.terminal.write('\x1b[33mMay iOS khong ho tro shell cuc bo. Hay mo ket noi SSH toi may chu tu xa de dung terminal.\x1b[0m\r\n');
        notifyListeners();
        return;
      }
      await _connectLocalPane(pane);
    }
  }

  /// Kết nối lại toàn bộ các tab Local Terminal (hữu ích khi chuyển đổi giữa App Chính và App Phụ).
  Future<void> reconnectLocalPanes() async {
    for (final pane in _panes) {
      if (!pane.isRemoteSsh) {
        await _connectPane(pane);
      }
      if (pane.childPane != null && !pane.childPane!.isRemoteSsh) {
        await _connectPane(pane.childPane!);
      }
    }
  }

  Future<void> _connectRemotePrimaryPane(TerminalPaneItem pane) async {
    try {
      final baseUrl = await _storage.getGatewayUrl();
      final token = await _storage.getSecretToken();
      if (baseUrl.trim().isEmpty) {
        pane.isConnecting = false;
        pane.isConnected = false;
        pane.terminal.write('\r\n\x1b[33m[App Phụ] Chưa cấu hình địa chỉ App Chính trong Cài đặt.\x1b[0m\r\n');
        notifyListeners();
        return;
      }

      final baseUri = Uri.parse(baseUrl);
      final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
      final initialCols = pane.terminal.viewWidth >= 10 ? pane.terminal.viewWidth : 80;
      final initialRows = pane.terminal.viewHeight >= 3 ? pane.terminal.viewHeight : 24;
      int lastAppliedCols = initialCols;
      int lastAppliedRows = initialRows;

      final clientId = await _storage.getClientDeviceId();
      final clientName = await _storage.getClientDeviceName();
      final basePath = baseUri.path.endsWith('/')
          ? baseUri.path.substring(0, baseUri.path.length - 1)
          : baseUri.path;
      final wsUri = baseUri.replace(
        scheme: wsScheme,
        path: '$basePath${ApiConstants.wsTerminal}',
        queryParameters: {
          if (token.isNotEmpty) 'token': token,
          'client_id': clientId,
          'client_name': clientName,
          'client_os': Platform.operatingSystem,
          if (pane.workingDirectory != null && pane.workingDirectory!.trim().isNotEmpty)
            'cwd': pane.workingDirectory!.trim(),
          'cols': '$initialCols',
          'rows': '$initialRows',
        },
      );

      final channel = IOWebSocketChannel.connect(
        wsUri,
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 12),
      );
      await channel.ready.timeout(const Duration(seconds: 12));
      pane.remoteWs = channel;
      pane.isConnected = true;
      pane.isConnecting = false;
      pane.title = 'App Chính (Remote)';
      notifyListeners();

      if (pane.initialCommand != null && pane.initialCommand!.trim().isNotEmpty) {
        final cmd = pane.initialCommand!;
        Future.delayed(const Duration(milliseconds: 450), () {
          try {
            pane.remoteWs?.sink.add('$cmd\r');
          } catch (_) {}
          pane.initialCommand = null;
        });
      }

      channel.stream.listen(
        (data) {
          if (data is String) {
            pane.terminal.write(data);
          } else if (data is List<int>) {
            pane.terminal.write(utf8.decode(data, allowMalformed: true));
          }
        },
        onDone: () {
          pane.isConnected = false;
          pane.terminal.write('\r\n\x1b[33m[Đã ngắt kết nối Terminal tới App Chính]\x1b[0m\r\n');
          notifyListeners();
        },
        onError: (err) {
          pane.isConnected = false;
          pane.terminal.write('\r\n\x1b[31m[Lỗi kết nối Terminal App Chính]: $err\x1b[0m\r\n');
          notifyListeners();
        },
      );

      pane.terminal.onOutput = (data) {
        try {
          pane.remoteWs?.sink.add(data);
        } catch (_) {}
      };

      pane.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (width >= 10 && height >= 3 && (width != lastAppliedCols || height != lastAppliedRows)) {
          lastAppliedCols = width;
          lastAppliedRows = height;
          try {
            pane.remoteWs?.sink.add(jsonEncode({'type': 'resize', 'cols': width, 'rows': height}));
          } catch (_) {}
        }
      };
    } catch (e) {
      pane.isConnecting = false;
      pane.isConnected = false;
      notifyListeners();
      pane.terminal.write('\r\n\x1b[31m[Không thể mở Terminal từ xa trên App Chính]: $e\x1b[0m\r\n');
    }
  }

  Future<void> _connectLocalPane(TerminalPaneItem pane) async {
    if (Platform.isIOS) return;
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

      String targetDir = defaultHome;
      if (pane.workingDirectory != null &&
          pane.workingDirectory!.trim().isNotEmpty &&
          Directory(pane.workingDirectory!.trim()).existsSync()) {
        targetDir = pane.workingDirectory!.trim();
      } else if (!isAndroid) {
        try {
          final recents = await _storage.getRecentScopes();
          if (recents.isNotEmpty && Directory(recents.first).existsSync()) {
            targetDir = recents.first;
            pane.workingDirectory = targetDir;
            saveTerminalSessions();
          }
        } catch (_) {}
      }

      final initialCols = pane.terminal.viewWidth >= 10 ? pane.terminal.viewWidth : 80;
      final initialRows = pane.terminal.viewHeight >= 3 ? pane.terminal.viewHeight : 24;
      int lastAppliedCols = initialCols;
      int lastAppliedRows = initialRows;

      pane.pty = Pty.start(
        shell,
        arguments: (isWin || isAndroid) ? [] : ['-l'],
        workingDirectory: targetDir,
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'LANG': Platform.environment['LANG'] ?? 'en_US.UTF-8',
          'LC_ALL': Platform.environment['LC_ALL'] ?? 'en_US.UTF-8',
          'VTE_VERSION': '6800',
        },
        columns: initialCols,
        rows: initialRows,
      );

      pane.isConnected = true;
      pane.isConnecting = false;
      notifyListeners();

      if (pane.initialCommand != null && pane.initialCommand!.trim().isNotEmpty) {
        final cmd = pane.initialCommand!;
        Future.delayed(const Duration(milliseconds: 450), () {
          if (pane.pty == null) return;
          try {
            pane.terminal.write('$cmd\r');
            pane.pty!.write(utf8.encode('$cmd\r'));
          } catch (_) {}
          pane.initialCommand = null;
        });
      }

      pane.pty!.output.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          pane.terminal.write(decoded);

          final osc7Match = RegExp(r'\x1b\]7;file://(?:[^/]+)?(/.*?)(?:\x07|\x1b\\)').firstMatch(decoded);
          if (osc7Match != null) {
            var rawPath = osc7Match.group(1);
            if (rawPath != null) {
              try {
                rawPath = Uri.decodeFull(rawPath);
                if (Directory(rawPath).existsSync() && rawPath != pane.workingDirectory) {
                  pane.workingDirectory = rawPath;
                  _storage.addRecentScope(rawPath);
                  saveTerminalSessions();
                  notifyListeners();
                }
              } catch (_) {}
            }
          }
        },
        onDone: () {
          pane.isConnected = false;
          pane.terminal.write('\r\n\x1b[33m[Tiến trình Terminal đã thoát]\x1b[0m\r\n');
          notifyListeners();
        },
        onError: (err) {
          pane.isConnected = false;
          pane.terminal.write('\r\n\x1b[31m[Lỗi Terminal]: $err\x1b[0m\r\n');
          notifyListeners();
        },
      );

      pane.terminal.onOutput = (data) {
        if (pane.pty != null) {
          try {
            pane.pty!.write(utf8.encode(data));

            if (data == '\r' || data == '\n') {
              Future.delayed(const Duration(milliseconds: 300), () {
                final oldDir = pane.workingDirectory;
                syncCurrentWorkingDirectory(pane);
                if (oldDir != pane.workingDirectory) {
                  saveTerminalSessions();
                  notifyListeners();
                }
              });
            }
          } catch (_) {}
        }
      };

      pane.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (width >= 10 && height >= 3 && (width != lastAppliedCols || height != lastAppliedRows)) {
          lastAppliedCols = width;
          lastAppliedRows = height;
          try {
            pane.pty?.resize(height, width);
          } catch (_) {}
        }
      };
    } catch (e) {
      pane.isConnecting = false;
      pane.isConnected = false;
      notifyListeners();
      pane.terminal.write('\r\n\x1b[31m[Lỗi mở Terminal cục bộ]: $e\x1b[0m\r\n');
    }
  }

  Future<void> _connectSshPane(TerminalPaneItem pane) async {
    try {
      final cols = pane.terminal.viewWidth >= 10 ? pane.terminal.viewWidth : 80;
      final rows = pane.terminal.viewHeight >= 3 ? pane.terminal.viewHeight : 24;
      int lastAppliedCols = cols;
      int lastAppliedRows = rows;

      pane.sshClient = await NativeSshService().getClient(server: pane.server);
      pane.sshSession = await pane.sshClient!.shell(
        pty: SSHPtyConfig(
          width: cols,
          height: rows,
        ),
      );

      pane.isConnected = true;
      pane.isConnecting = false;
      notifyListeners();

      if (pane.workingDirectory != null && pane.workingDirectory!.trim().isNotEmpty) {
        final dir = pane.workingDirectory!.trim();
        pane.sshSession?.stdin.add(utf8.encode('cd "$dir" 2>/dev/null || true\n'));
      }

      pane.sshSession!.stdout.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          pane.terminal.write(decoded);

          final osc7Match = RegExp(r'\x1b\]7;file://(?:[^/]+)?(/.*?)(?:\x07|\x1b\\)').firstMatch(decoded);
          if (osc7Match != null) {
            var rawPath = osc7Match.group(1);
            if (rawPath != null) {
              try {
                rawPath = Uri.decodeFull(rawPath);
                if (rawPath.isNotEmpty && rawPath != pane.workingDirectory) {
                  pane.workingDirectory = rawPath;
                  saveTerminalSessions();
                  notifyListeners();
                }
              } catch (_) {}
            }
          }
        },
        onDone: () {
          pane.isConnected = false;
          pane.terminal.write('\r\n\x1b[33m[Phiên SSH Terminal đã đóng]\x1b[0m\r\n');
          notifyListeners();
        },
        onError: (err) {
          pane.isConnected = false;
          pane.terminal.write('\r\n\x1b[31m[Lỗi SSH]: $err\x1b[0m\r\n');
          notifyListeners();
        },
      );

      pane.sshSession!.stderr.listen((data) {
        final decoded = utf8.decode(data, allowMalformed: true);
        pane.terminal.write(decoded);
      });

      pane.terminal.onOutput = (data) {
        pane.sshSession?.stdin.add(utf8.encode(data));
      };

      pane.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (width >= 10 && height >= 3 && (width != lastAppliedCols || height != lastAppliedRows)) {
          lastAppliedCols = width;
          lastAppliedRows = height;
          try {
            pane.sshSession?.resizeTerminal(width, height, pixelWidth, pixelHeight);
          } catch (_) {}
        }
      };
    } catch (e) {
      pane.isConnecting = false;
      pane.isConnected = false;
      notifyListeners();
      pane.terminal.write('\r\n\x1b[31m[Lỗi kết nối SSH Terminal]: $e\x1b[0m\r\n');
    }
  }

  @override
  void dispose() {
    saveTerminalSessions();
    for (final p in _panes) {
      p.dispose();
    }
    _panes.clear();
    super.dispose();
  }
}
