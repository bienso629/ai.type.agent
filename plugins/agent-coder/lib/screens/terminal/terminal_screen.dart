import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

enum TerminalSplitDirection {
  none,
  horizontal,
  vertical,
}

class TerminalPaneItem {
  final String id;
  String title;
  bool isRemoteSsh;
  ServerModel? server;
  late final Terminal terminal;
  late final TerminalController controller;
  late final FocusNode focusNode;
  Pty? pty;
  Process? fallbackProcess;
  SSHClient? sshClient;
  SSHSession? sshSession;
  bool isConnected = false;
  bool isConnecting = false;

  String? workingDirectory;

  // Split state specifically for this window/pane
  TerminalSplitDirection splitDirection = TerminalSplitDirection.none;
  TerminalPaneItem? childPane;

  TerminalPaneItem({
    required this.id,
    required this.title,
    this.isRemoteSsh = false,
    this.server,
    this.workingDirectory,
  }) {
    focusNode = FocusNode();
    terminal = Terminal(
      maxLines: 10000,
    );
    controller = TerminalController();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isRemoteSsh': isRemoteSsh,
      'server': server?.toJson(),
      'workingDirectory': workingDirectory,
      'splitDirection': splitDirection.name,
      'childPane': childPane?.toJson(),
    };
  }

  static TerminalPaneItem fromJson(Map<String, dynamic> json) {
    ServerModel? srv;
    if (json['server'] != null) {
      try {
        srv = ServerModel.fromJson(Map<String, dynamic>.from(json['server']));
      } catch (_) {}
    }

    final item = TerminalPaneItem(
      id: json['id'] ?? 'pane_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] ?? (json['isRemoteSsh'] == true ? (srv?.name ?? 'SSH Server') : 'Local Machine'),
      isRemoteSsh: json['isRemoteSsh'] == true,
      server: srv,
      workingDirectory: json['workingDirectory'] as String?,
    );

    final splitName = json['splitDirection'] as String?;
    if (splitName != null) {
      item.splitDirection = TerminalSplitDirection.values.firstWhere(
        (e) => e.name == splitName,
        orElse: () => TerminalSplitDirection.none,
      );
    }

    if (json['childPane'] != null) {
      try {
        item.childPane = TerminalPaneItem.fromJson(Map<String, dynamic>.from(json['childPane']));
      } catch (_) {}
    }

    return item;
  }

  void cleanup() {
    try {
      pty?.kill();
      pty = null;
    } catch (_) {}
    try {
      fallbackProcess?.kill();
      fallbackProcess = null;
    } catch (_) {}
    try {
      sshSession?.close();
      sshSession = null;
    } catch (_) {}
    try {
      sshClient?.close();
      sshClient = null;
    } catch (_) {}

    childPane?.cleanup();
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
    cleanup();
    childPane?.dispose();
  }
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<TerminalPaneItem> _panes = [];
  int _activePaneIndex = 0;
  String? _activeSubPaneId;
  bool _showVirtualKeyboard = false;
  final StorageService _storage = StorageService();

  // Chuẩn bảng màu và thuộc tính Ubuntu GNOME Terminal (Canonical Ubuntu palette)
  static final _terminalTheme = TerminalTheme(
    cursor: const Color(0xFFFFFFFF),
    selection: const Color(0xFFE95420).withValues(alpha: 0.40),
    foreground: const Color(0xFFFFFFFF),
    background: const Color(0xFF300A24), // Màu tím đậm Dark Aubergine đặc trưng của Ubuntu Terminal
    black: const Color(0xFF2E3436),
    red: const Color(0xFFCC0000),
    green: const Color(0xFF4E9A06),
    yellow: const Color(0xFFC4A000),
    blue: const Color(0xFF3465A4),
    magenta: const Color(0xFF75507B),
    cyan: const Color(0xFF06989A),
    white: const Color(0xFFD3D7CF),
    brightBlack: const Color(0xFF555753),
    brightRed: const Color(0xFFEF2929),
    brightGreen: const Color(0xFF8AE234),
    brightYellow: const Color(0xFFFCE94F),
    brightBlue: const Color(0xFF729FCF),
    brightMagenta: const Color(0xFFAD7FA8),
    brightCyan: const Color(0xFF34E2E2),
    brightWhite: const Color(0xFFEEEEEC),
    searchHitBackground: const Color(0xFFFCE94F),
    searchHitBackgroundCurrent: const Color(0xFFE95420),
    searchHitForeground: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    _loadSavedTerminalSessions();
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
            if (!mounted) return;
            setState(() {
              _panes.clear();
              _panes.addAll(loadedPanes);
              _activePaneIndex = (decoded['activePaneIndex'] is int &&
                      decoded['activePaneIndex'] >= 0 &&
                      decoded['activePaneIndex'] < _panes.length)
                  ? decoded['activePaneIndex'] as int
                  : 0;
              _activeSubPaneId = decoded['activeSubPaneId'] as String?;
            });

            // Kết nối các pane và child pane
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

    // Fallback nếu không có cấu hình lưu trước, lấy thư mục gần nhất nếu có
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
    if (!mounted) return;
    setState(() {
      _panes.clear();
      _panes.add(firstPane);
      _activePaneIndex = 0;
      _activeSubPaneId = null;
    });
    _connectPane(firstPane);
  }

  Future<void> _saveTerminalSessions() async {
    try {
      final data = {
        'activePaneIndex': _activePaneIndex,
        'activeSubPaneId': _activeSubPaneId,
        'panes': _panes.map((p) => p.toJson()).toList(),
      };
      await _storage.setTerminalSessions(json.encode(data));
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final p in _panes) {
      p.dispose();
    }
    _panes.clear();
    super.dispose();
  }

  TerminalPaneItem? get _activeRootPane {
    if (_panes.isEmpty) return null;
    if (_activePaneIndex >= 0 && _activePaneIndex < _panes.length) {
      return _panes[_activePaneIndex];
    }
    return _panes.first;
  }

  TerminalPaneItem? get _activePane {
    final root = _activeRootPane;
    if (root == null) return null;
    if (_activeSubPaneId != null && root.childPane != null && root.childPane!.id == _activeSubPaneId) {
      return root.childPane;
    }
    return root;
  }

  Future<void> _connectPane(TerminalPaneItem pane) async {
    pane.cleanup();
    if (mounted) {
      setState(() {
        pane.isConnecting = true;
        pane.isConnected = false;
      });
    }

    if (pane.isRemoteSsh) {
      await _connectSshPane(pane);
    } else {
      await _connectLocalPane(pane);
    }
  }

  Future<void> _connectLocalPane(TerminalPaneItem pane) async {
    try {
      final isWin = Platform.isWindows;
      final shell = Platform.environment['SHELL'] ??
          (isWin ? 'cmd.exe' : (File('/bin/bash').existsSync() ? '/bin/bash' : '/bin/sh'));
      final defaultHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? (isWin ? 'C:\\' : '/');

      // Ưu tiên: pane.workingDirectory -> recent scope -> defaultHome
      String targetDir = defaultHome;
      if (pane.workingDirectory != null && pane.workingDirectory!.trim().isNotEmpty && Directory(pane.workingDirectory!.trim()).existsSync()) {
        targetDir = pane.workingDirectory!.trim();
      } else {
        try {
          final recents = await _storage.getRecentScopes();
          if (recents.isNotEmpty && Directory(recents.first).existsSync()) {
            targetDir = recents.first;
            pane.workingDirectory = targetDir;
            _saveTerminalSessions();
          }
        } catch (_) {}
      }

      final initialCols = pane.terminal.viewWidth > 0 ? pane.terminal.viewWidth : 80;
      final initialRows = pane.terminal.viewHeight > 0 ? pane.terminal.viewHeight : 24;

      // Khởi tạo tiến trình Pseudo-Terminal (PTY) với cấu hình môi trường chuẩn Ubuntu Linux
      pane.pty = Pty.start(
        shell,
        arguments: isWin ? [] : ['-l'],
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

      if (mounted) {
        setState(() {
          pane.isConnected = true;
          pane.isConnecting = false;
        });
      }

      pane.pty!.output.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          pane.terminal.write(decoded);

          // Phát hiện OSC 7 escape sequence: OSC 7 ; file://hostname/path ST / BEL
          // Ví dụ: \x1b]7;file://localhost/home/yenai/Documents\x07 hoặc \x1b\x5c
          final osc7Match = RegExp(r'\x1b\]7;file://(?:[^/]+)?(/.*?)(?:\x07|\x1b\\)').firstMatch(decoded);
          if (osc7Match != null) {
            var rawPath = osc7Match.group(1);
            if (rawPath != null) {
              try {
                rawPath = Uri.decodeFull(rawPath);
                if (Directory(rawPath).existsSync() && rawPath != pane.workingDirectory) {
                  pane.workingDirectory = rawPath;
                  _storage.addRecentScope(rawPath);
                  _saveTerminalSessions();
                  if (mounted) setState(() {});
                }
              } catch (_) {}
            }
          }
        },
        onDone: () {
          if (mounted) setState(() => pane.isConnected = false);
          pane.terminal.write('\r\n\x1b[33m[Tiến trình Terminal đã thoát]\x1b[0m\r\n');
        },
        onError: (err) {
          if (mounted) setState(() => pane.isConnected = false);
          pane.terminal.write('\r\n\x1b[31m[Lỗi Terminal]: $err\x1b[0m\r\n');
        },
      );

      pane.terminal.onOutput = (data) {
        if (pane.pty != null) {
          try {
            pane.pty!.write(utf8.encode(data));

            // Kiểm tra lệnh cd trực tiếp khi người dùng gõ
            if (data == '\r' || data == '\n') {
              Future.delayed(const Duration(milliseconds: 300), () {
                _syncCurrentWorkingDirectory(pane);
              });
            }
          } catch (_) {}
        }
      };

      pane.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (width > 0 && height > 0) {
          try {
            pane.pty?.resize(height, width);
          } catch (_) {}
        }
      };
    } catch (e) {
      if (mounted) {
        setState(() {
          pane.isConnecting = false;
          pane.isConnected = false;
        });
      }
      pane.terminal.write('\r\n\x1b[31m[Lỗi mở Terminal cục bộ]: $e\x1b[0m\r\n');
    }
  }

  void _syncCurrentWorkingDirectory(TerminalPaneItem pane) {
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
            _saveTerminalSessions();
            if (mounted) setState(() {});
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _connectSshPane(TerminalPaneItem pane) async {
    final serverProvider = context.read<ServerProvider>();
    final server = pane.server ?? (serverProvider.selectedServer?.serverIp != '127.0.0.1' ? serverProvider.selectedServer : null) ?? (serverProvider.servers.isNotEmpty ? serverProvider.servers.first : null);

    pane.server = server;
    if (server != null) {
      pane.title = server.name;
    }

    try {
      final cols = pane.terminal.viewWidth > 0 ? pane.terminal.viewWidth : 80;
      final rows = pane.terminal.viewHeight > 0 ? pane.terminal.viewHeight : 24;

      pane.sshClient = await NativeSshService().getClient(server: server);
      pane.sshSession = await pane.sshClient!.shell(
        pty: SSHPtyConfig(
          width: cols,
          height: rows,
        ),
      );

      if (mounted) {
        setState(() {
          pane.isConnected = true;
          pane.isConnecting = false;
        });
      }

      // Nếu có workingDirectory từ trước trên SSH server, tự động chuyển vào thư mục đó
      if (pane.workingDirectory != null && pane.workingDirectory!.trim().isNotEmpty) {
        final dir = pane.workingDirectory!.trim();
        pane.sshSession?.stdin.add(utf8.encode('cd "$dir" 2>/dev/null || true\n'));
      }

      pane.sshSession!.stdout.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          pane.terminal.write(decoded);

          // Nhận diện OSC 7 qua SSH
          final osc7Match = RegExp(r'\x1b\]7;file://(?:[^/]+)?(/.*?)(?:\x07|\x1b\\)').firstMatch(decoded);
          if (osc7Match != null) {
            var rawPath = osc7Match.group(1);
            if (rawPath != null) {
              try {
                rawPath = Uri.decodeFull(rawPath);
                if (rawPath.isNotEmpty && rawPath != pane.workingDirectory) {
                  pane.workingDirectory = rawPath;
                  _saveTerminalSessions();
                  if (mounted) setState(() {});
                }
              } catch (_) {}
            }
          }
        },
        onDone: () {
          if (mounted) setState(() => pane.isConnected = false);
          pane.terminal.write('\r\n\x1b[33m[Phiên SSH Terminal đã đóng]\x1b[0m\r\n');
        },
        onError: (err) {
          if (mounted) setState(() => pane.isConnected = false);
          pane.terminal.write('\r\n\x1b[31m[Lỗi SSH]: $err\x1b[0m\r\n');
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
        if (width > 0 && height > 0) {
          try {
            pane.sshSession?.resizeTerminal(width, height, pixelWidth, pixelHeight);
          } catch (_) {}
        }
      };
    } catch (e) {
      if (mounted) {
        setState(() {
          pane.isConnecting = false;
          pane.isConnected = false;
        });
      }
      pane.terminal.write('\r\n\x1b[31m[Lỗi kết nối SSH Terminal]: $e\x1b[0m\r\n');
    }
  }

  void _addWindow({bool isSsh = false, ServerModel? srv}) {
    if (_panes.length >= 6) return;
    final id = 'pane_${DateTime.now().millisecondsSinceEpoch}';
    final newPane = TerminalPaneItem(
      id: id,
      title: isSsh ? (srv?.name ?? 'SSH Server') : 'Local Machine',
      isRemoteSsh: isSsh,
      server: srv,
    );
    setState(() {
      _panes.add(newPane);
      _activePaneIndex = _panes.length - 1;
      _activeSubPaneId = null;
    });
    _connectPane(newPane);
    _saveTerminalSessions();
  }

  void _removeWindow(int index) {
    if (_panes.length <= 1) return;
    final removed = _panes.removeAt(index);
    removed.dispose();
    setState(() {
      if (_activePaneIndex >= _panes.length) {
        _activePaneIndex = _panes.length - 1;
      }
      _activeSubPaneId = null;
    });
    _saveTerminalSessions();
  }

  void _splitActiveWindow(TerminalSplitDirection direction, int windowIndex, TerminalPaneItem targetPane) {
    if (windowIndex < 0 || windowIndex >= _panes.length) return;
    final windowPane = _panes[windowIndex];

    if (direction == TerminalSplitDirection.none) {
      // Huỷ split của window này
      if (windowPane.childPane != null) {
        windowPane.childPane!.dispose();
        windowPane.childPane = null;
      }
      setState(() {
        windowPane.splitDirection = TerminalSplitDirection.none;
        _activePaneIndex = windowIndex;
        _activeSubPaneId = null;
      });
      _saveTerminalSessions();
      return;
    }

    // Split window này
    if (windowPane.childPane == null) {
      final id = 'subpane_${DateTime.now().millisecondsSinceEpoch}';
      final newSubPane = TerminalPaneItem(
        id: id,
        title: targetPane.isRemoteSsh ? (targetPane.server?.name ?? 'SSH Server') : 'Local Machine',
        isRemoteSsh: targetPane.isRemoteSsh,
        server: targetPane.server,
      );
      windowPane.childPane = newSubPane;
      _connectPane(newSubPane);
    }

    setState(() {
      windowPane.splitDirection = direction;
      _activePaneIndex = windowIndex;
      _activeSubPaneId = windowPane.childPane?.id;
    });
    _saveTerminalSessions();
  }

  void _closeChildPane(int windowIndex) {
    if (windowIndex < 0 || windowIndex >= _panes.length) return;
    final windowPane = _panes[windowIndex];
    if (windowPane.childPane != null) {
      windowPane.childPane!.dispose();
      windowPane.childPane = null;
      setState(() {
        windowPane.splitDirection = TerminalSplitDirection.none;
        _activeSubPaneId = null;
      });
      _saveTerminalSessions();
    }
  }

  void _sendCmdToActive(String cmd) {
    final pane = _activePane;
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

  void _sendKeyToActive(String code) {
    final pane = _activePane;
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

  Future<void> _showContextMenu(
    BuildContext context,
    Offset position,
    int windowIndex,
    TerminalPaneItem pane,
    ServerProvider serverProvider, {
    bool isChild = false,
  }) async {
    final windowPane = _panes[windowIndex];
    setState(() {
      _activePaneIndex = windowIndex;
      _activeSubPaneId = isChild ? pane.id : null;
    });
    pane.focusNode.requestFocus();

    final isCurrentlySplit = windowPane.splitDirection != TerminalSplitDirection.none && windowPane.childPane != null;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      elevation: 10,
      items: [
        // 1. SPLIT CHO CHÍNH CỬA SỔ HIỆN TẠI (WINDOW SPECIFIC)
        const PopupMenuItem<String>(
          enabled: false,
          height: 26,
          child: Text('CHIA KHUNG CỬA SỔ NÀY (SPLIT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
        ),
        PopupMenuItem<String>(
          value: 'split_none',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.crop_square_rounded, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Khung đơn (Không chia)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (!isCurrentlySplit) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split_horizontal',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.view_column_outlined, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Chia đôi: Trái / Phải', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (isCurrentlySplit && windowPane.splitDirection == TerminalSplitDirection.horizontal) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split_vertical',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.view_agenda_outlined, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Chia đôi: Trên / Dưới', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (isCurrentlySplit && windowPane.splitDirection == TerminalSplitDirection.vertical) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(height: 10),

        // 2. THAO TÁC TERMINAL
        PopupMenuItem<String>(
          value: 'set_directory',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 15, color: AppColors.accentCyan),
              const SizedBox(width: 8),
              Text(
                pane.workingDirectory != null && pane.workingDirectory!.isNotEmpty
                    ? 'Đổi thư mục: .../${pane.workingDirectory!.split(Platform.isWindows ? r'\' : '/').where((p) => p.isNotEmpty).last}'
                    : 'Chọn thư mục làm việc (cd)',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'restart_pane',
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.refresh_rounded, size: 15, color: AppColors.textDim),
              SizedBox(width: 8),
              Text('Khởi động lại Terminal này', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clear_pane',
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.cleaning_services_rounded, size: 15, color: AppColors.textDim),
              SizedBox(width: 8),
              Text('Xoá sạch màn hình (Clear)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
            ],
          ),
        ),

        // 3. ĐÓNG PANEL / WINDOW
        if (isChild) ...[
          const PopupMenuDivider(height: 10),
          const PopupMenuItem<String>(
            value: 'close_subpane',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.close_fullscreen_rounded, size: 15, color: AppColors.warning),
                SizedBox(width: 8),
                Text('Đóng khung phụ (Huỷ Split)', style: TextStyle(fontSize: 12, color: AppColors.warning)),
              ],
            ),
          ),
        ] else if (_panes.length > 1) ...[
          const PopupMenuDivider(height: 10),
          const PopupMenuItem<String>(
            value: 'close_window',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.close_rounded, size: 15, color: AppColors.danger),
                SizedBox(width: 8),
                Text('Đóng Tab cửa sổ này', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ],
    );

    if (result == null) return;

    if (result == 'set_directory') {
      _pickDirectoryForPane(pane);
    } else if (result == 'split_none') {
      _splitActiveWindow(TerminalSplitDirection.none, windowIndex, pane);
    } else if (result == 'split_horizontal') {
      _splitActiveWindow(TerminalSplitDirection.horizontal, windowIndex, pane);
    } else if (result == 'split_vertical') {
      _splitActiveWindow(TerminalSplitDirection.vertical, windowIndex, pane);
    } else if (result == 'restart_pane') {
      _connectPane(pane);
    } else if (result == 'clear_pane') {
      pane.terminal.eraseDisplay();
      pane.terminal.setCursor(0, 0);
    } else if (result == 'close_subpane') {
      _closeChildPane(windowIndex);
    } else if (result == 'close_window') {
      _removeWindow(windowIndex);
    }
  }

  Future<void> _pickDirectoryForPane(TerminalPaneItem pane) async {
    try {
      final initial = (pane.workingDirectory != null && Directory(pane.workingDirectory!).existsSync())
          ? pane.workingDirectory
          : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Chọn thư mục làm việc cho Terminal',
        initialDirectory: initial,
      );
      if (selected != null && selected.isNotEmpty && mounted) {
        pane.workingDirectory = selected;
        await _storage.addRecentScope(selected);
        await _saveTerminalSessions();
        if (pane.isConnected) {
          _sendCmdToActive('cd "$selected"');
        } else {
          _connectPane(pane);
        }
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final activePane = _activePane;
    final activeRoot = _activeRootPane;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. Clean Minimal Topbar Header (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        (activePane?.isRemoteSsh == true) ? Icons.dns_rounded : Icons.terminal_rounded,
                        color: (activePane?.isRemoteSsh == true) ? AppColors.primaryLight : AppColors.accent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Terminal Console',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ((activePane?.isConnected ?? false) ? AppColors.accent : AppColors.danger).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: (activePane?.isConnected ?? false) ? AppColors.accent : AppColors.danger),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: (activePane?.isConnected ?? false) ? AppColors.accent : AppColors.danger,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        (activePane?.isConnected ?? false)
                                            ? (activePane!.isRemoteSsh ? 'SSH CONNECTED' : 'LOCAL READY')
                                            : (activePane?.isConnecting == true ? 'CONNECTING...' : 'OFFLINE'),
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: (activePane?.isConnected ?? false) ? AppColors.accent : AppColors.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              activeRoot?.splitDirection != TerminalSplitDirection.none
                                  ? 'Cửa sổ [${activeRoot?.title}] đang chia đôi (${activeRoot?.splitDirection == TerminalSplitDirection.horizontal ? 'Trái / Phải' : 'Trên / Dưới'}) • Nhấp chuột phải để đổi bố cục'
                                  : (activePane?.isRemoteSsh == true
                                      ? 'Phiên SSH với ${activePane?.server?.name ?? serverProvider.selectedServer?.name ?? 'Server'} • Nhấp chuột phải để chia màn hình'
                                      : 'Thực thi toàn bộ lệnh shell cục bộ (${Platform.operatingSystem}) • Nhấp chuột phải để chia màn hình'),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showVirtualKeyboard ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
                        color: _showVirtualKeyboard ? AppColors.accentCyan : AppColors.textDim,
                        size: 18,
                      ),
                      tooltip: _showVirtualKeyboard ? 'Ẩn thanh phím tắt ảo' : 'Hiện thanh phím tắt ảo (ESC, TAB, CTRL...)',
                      onPressed: () {
                        setState(() {
                          _showVirtualKeyboard = !_showVirtualKeyboard;
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: (activePane?.isConnecting == true)
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                            )
                          : Icon(
                              (activePane?.isConnected ?? false) ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                              color: (activePane?.isConnected ?? false) ? AppColors.accent : AppColors.warning,
                              size: 18,
                            ),
                      tooltip: 'Khởi động lại Terminal đang chọn',
                      onPressed: activePane != null ? () => _connectPane(activePane) : null,
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: AppColors.textDim),
                      label: const Text('Xoá màn hình', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                      onPressed: () {
                        _activePane?.terminal.eraseDisplay();
                        _activePane?.terminal.setCursor(0, 0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Window Tabs Bar (Khi có nhiều cửa sổ hoặc để tạo thêm cửa sổ)
          if (_panes.length > 1 || true)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: AppColors.cardBg,
                border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _panes.length,
                      itemBuilder: (ctx, index) {
                        final window = _panes[index];
                        final isWinActive = _activePaneIndex == index;
                        final isSplit = window.splitDirection != TerminalSplitDirection.none && window.childPane != null;

                        return Container(
                          margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                          child: Material(
                            color: isWinActive ? AppColors.bgDark : AppColors.sidebarBg,
                            borderRadius: BorderRadius.circular(4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                setState(() {
                                  _activePaneIndex = index;
                                  _activeSubPaneId = null;
                                });
                                window.focusNode.requestFocus();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isWinActive ? AppColors.accent : AppColors.borderDark,
                                    width: isWinActive ? 1.2 : 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: window.isConnected ? AppColors.accent : (window.isConnecting ? AppColors.warning : AppColors.danger),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      window.isRemoteSsh ? Icons.dns_rounded : Icons.laptop_chromebook_rounded,
                                      size: 13,
                                      color: window.isRemoteSsh ? AppColors.primaryLight : AppColors.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Tab ${index + 1}: ${window.title}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isWinActive ? FontWeight.bold : FontWeight.normal,
                                        color: isWinActive ? AppColors.textWhite : AppColors.textDim,
                                      ),
                                    ),
                                    if (isSplit) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentCyan.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          window.splitDirection == TerminalSplitDirection.horizontal ? 'SPLIT H' : 'SPLIT V',
                                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                                        ),
                                      ),
                                    ],
                                    if (_panes.length > 1) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => _removeWindow(index),
                                        borderRadius: BorderRadius.circular(10),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2),
                                          child: Icon(Icons.close_rounded, size: 12, color: AppColors.textDim),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Nút tạo Tab Cửa Sổ Mới
                  if (_panes.length < 6)
                    PopupMenuButton<String>(
                      tooltip: 'Mở thêm Tab Cửa Sổ Terminal mới',
                      offset: const Offset(0, 30),
                      color: AppColors.cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                      onSelected: (val) {
                        if (val == 'new_local') {
                          _addWindow(isSsh: false);
                        } else if (val.startsWith('new_ssh_')) {
                          final srvId = val.replaceFirst('new_ssh_', '');
                          final srv = serverProvider.servers.firstWhere((s) => s.id == srvId, orElse: () => serverProvider.servers.first);
                          _addWindow(isSsh: true, srv: srv);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem<String>(
                          value: 'new_local',
                          child: Row(
                            children: [
                              Icon(Icons.laptop_chromebook_rounded, size: 14, color: AppColors.accent),
                              SizedBox(width: 8),
                              Text('Thêm Tab Local Machine', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                            ],
                          ),
                        ),
                        for (final s in serverProvider.servers)
                          PopupMenuItem<String>(
                            value: 'new_ssh_${s.id}',
                            child: Row(
                              children: [
                                const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
                                const SizedBox(width: 8),
                                Text('Thêm Tab SSH: ${s.name}', style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 14, color: AppColors.primaryLight),
                            SizedBox(width: 4),
                            Text('Tab mới', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // 2. Quick Command Bar (Applies to active pane)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                const Text(
                  'Lệnh nhanh: ',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildQuickActionBtn('ls -la', 'ls -la', Icons.folder_open_rounded),
                        _buildQuickActionBtn('pwd', 'pwd', Icons.location_on_outlined),
                        _buildQuickActionBtn('df -h', 'df -h', Icons.storage_rounded),
                        _buildQuickActionBtn('free -m', 'free -m', Icons.memory_rounded),
                        _buildQuickActionBtn('top / htop', 'top', Icons.speed_rounded),
                        _buildQuickActionBtn('git status', 'git status', Icons.commit_rounded),
                        _buildQuickActionBtn('ps aux', 'ps aux', Icons.view_list_rounded),
                        _buildQuickActionBtn('clear', 'clear', Icons.cleaning_services_rounded),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Virtual Key Bar (Optional)
          if (_showVirtualKeyboard)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.cardBg,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildKeyBtn('ESC', '\x1b'),
                    _buildKeyBtn('TAB', '\t'),
                    _buildKeyBtn('CTRL+C', '\x03', isHighlight: true),
                    _buildKeyBtn('CTRL+D', '\x04'),
                    _buildKeyBtn('CTRL+Z', '\x1a'),
                    _buildKeyBtn('CTRL+L', '\x0c'),
                    _buildKeyBtn('▲', '\x1b[A'),
                    _buildKeyBtn('▼', '\x1b[B'),
                    _buildKeyBtn('◀', '\x1b[D'),
                    _buildKeyBtn('▶', '\x1b[C'),
                    _buildKeyBtn('HOME', '\x1b[H'),
                    _buildKeyBtn('END', '\x1b[F'),
                    _buildKeyBtn('PAGE UP', '\x1b[5~'),
                    _buildKeyBtn('PAGE DOWN', '\x1b[6~'),
                  ],
                ),
              ),
            ),

          // 4. MAIN TERMINAL SPLIT WORKSPACE
          Expanded(
            child: Container(
              color: AppColors.bgDark,
              padding: const EdgeInsets.all(8),
              child: _buildSplitWorkspace(serverProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitWorkspace(ServerProvider serverProvider) {
    if (_panes.isEmpty) {
      return const Center(child: Text('Không có Terminal nào', style: TextStyle(color: AppColors.textMuted)));
    }

    final activeIndex = (_activePaneIndex >= 0 && _activePaneIndex < _panes.length) ? _activePaneIndex : 0;
    final activeWindow = _panes[activeIndex];

    // Nếu active window không split
    if (activeWindow.splitDirection == TerminalSplitDirection.none || activeWindow.childPane == null) {
      return _buildPaneCard(
        activeWindow,
        activeIndex,
        serverProvider,
        isChild: false,
        isOnlyOne: true,
      );
    }

    // Nếu active window được split
    final mainCard = _buildPaneCard(activeWindow, activeIndex, serverProvider, isChild: false);
    final childCard = _buildPaneCard(activeWindow.childPane!, activeIndex, serverProvider, isChild: true);

    if (activeWindow.splitDirection == TerminalSplitDirection.horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: mainCard),
          const SizedBox(width: 8), // Gap 8px giữa 2 window ngang
          Expanded(child: childCard),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: mainCard),
        const SizedBox(height: 8), // Gap 8px giữa 2 window dọc
        Expanded(child: childCard),
      ],
    );
  }

  Widget _buildPaneCard(
    TerminalPaneItem pane,
    int windowIndex,
    ServerProvider serverProvider, {
    bool isChild = false,
    bool isOnlyOne = false,
  }) {
    final isThisPaneActive = isChild ? (_activeSubPaneId == pane.id) : (_activeSubPaneId == null);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_activePaneIndex != windowIndex || (isChild ? _activeSubPaneId != pane.id : _activeSubPaneId != null)) {
          setState(() {
            _activePaneIndex = windowIndex;
            _activeSubPaneId = isChild ? pane.id : null;
          });
        }
        if (!pane.focusNode.hasFocus) {
          pane.focusNode.requestFocus();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_activePaneIndex != windowIndex || (isChild ? _activeSubPaneId != pane.id : _activeSubPaneId != null)) {
            setState(() {
              _activePaneIndex = windowIndex;
              _activeSubPaneId = isChild ? pane.id : null;
            });
          }
          pane.focusNode.requestFocus();
        },
        onSecondaryTapDown: (details) => _showContextMenu(
          context,
          details.globalPosition,
          windowIndex,
          pane,
          serverProvider,
          isChild: isChild,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isThisPaneActive ? AppColors.accent : AppColors.borderDark,
              width: isThisPaneActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              // Sub-Header for each pane
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isThisPaneActive ? AppColors.accent.withValues(alpha: 0.12) : AppColors.cardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  border: Border(
                    bottom: BorderSide(
                      color: isThisPaneActive ? AppColors.accent.withValues(alpha: 0.35) : AppColors.borderDark,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: pane.isConnected ? AppColors.accent : (pane.isConnecting ? AppColors.warning : AppColors.danger),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Pane Mode Switcher Dropdown
                        PopupMenuButton<String>(
                          tooltip: 'Đổi môi trường cho Panel này',
                          offset: const Offset(0, 30),
                          color: AppColors.cardBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                            side: const BorderSide(color: AppColors.borderDark),
                          ),
                          onSelected: (val) {
                            setState(() {
                              _activePaneIndex = windowIndex;
                              _activeSubPaneId = isChild ? pane.id : null;
                              if (val == 'local') {
                                pane.isRemoteSsh = false;
                                pane.server = null;
                                pane.title = 'Local Machine';
                              } else {
                                final srv = serverProvider.servers.firstWhere((s) => s.id == val, orElse: () => serverProvider.servers.first);
                                pane.isRemoteSsh = true;
                                pane.server = srv;
                                pane.title = srv.name;
                              }
                            });
                            _connectPane(pane);
                          },
                          itemBuilder: (ctx) {
                            final items = <PopupMenuEntry<String>>[];
                            items.add(
                              PopupMenuItem<String>(
                                value: 'local',
                                child: Row(
                                  children: [
                                    const Icon(Icons.laptop_chromebook_rounded, size: 14, color: AppColors.accent),
                                    const SizedBox(width: 8),
                                    const Text('Local Machine', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                    if (!pane.isRemoteSsh) ...[
                                      const Spacer(),
                                      const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                                    ],
                                  ],
                                ),
                              ),
                            );
                            if (serverProvider.servers.isNotEmpty) {
                              items.add(const PopupMenuDivider());
                              for (final s in serverProvider.servers) {
                                final isSel = pane.isRemoteSsh && pane.server?.id == s.id;
                                items.add(
                                  PopupMenuItem<String>(
                                    value: s.id,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
                                        const SizedBox(width: 8),
                                        Text('SSH: ${s.name}', style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                        if (isSel) ...[
                                          const Spacer(),
                                          const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryLight),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }
                            }
                            return items;
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: pane.isRemoteSsh ? AppColors.primary.withValues(alpha: 0.2) : AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  pane.isRemoteSsh ? Icons.dns_rounded : Icons.laptop_chromebook_rounded,
                                  size: 12,
                                  color: pane.isRemoteSsh ? AppColors.primaryLight : AppColors.accent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  pane.isRemoteSsh ? 'SSH: ${pane.server?.name ?? 'Server'}' : 'Local Machine',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: pane.isRemoteSsh ? AppColors.primaryLight : AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.arrow_drop_down_rounded, size: 13, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        ),
                        if (pane.workingDirectory != null && pane.workingDirectory!.trim().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _pickDirectoryForPane(pane),
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.sidebarBg,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: AppColors.borderDark, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.folder_open_rounded, size: 11, color: AppColors.accentCyan),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      pane.workingDirectory!.split(Platform.isWindows ? r'\' : '/').where((p) => p.isNotEmpty).isEmpty
                                          ? pane.workingDirectory!
                                          : pane.workingDirectory!.split(Platform.isWindows ? r'\' : '/').where((p) => p.isNotEmpty).last,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: AppColors.textDim,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    Row(
                      children: [
                        if (isThisPaneActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.accent.withValues(alpha: 0.6), width: 0.8),
                            ),
                            child: const Text('ĐANG CHỌN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accent)),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, size: 14, color: AppColors.textDim),
                          tooltip: 'Menu tuỳ chọn (Chuột phải)',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () {
                            final RenderBox box = context.findRenderObject() as RenderBox;
                            final pos = box.localToGlobal(Offset.zero);
                            _showContextMenu(
                              context,
                              Offset(pos.dx + box.size.width - 200, pos.dy + 100),
                              windowIndex,
                              pane,
                              serverProvider,
                              isChild: isChild,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
                          tooltip: 'Khởi động lại terminal này',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () => _connectPane(pane),
                        ),
                        if (isChild)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                            tooltip: 'Đóng khung phụ này (Huỷ split)',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => _closeChildPane(windowIndex),
                          )
                        else if (!isOnlyOne && _panes.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                            tooltip: 'Đóng Tab cửa sổ này',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => _removeWindow(windowIndex),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Terminal View (Chuẩn cấu hình hiển thị và con trỏ Ubuntu Terminal)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: TerminalView(
                    pane.terminal,
                    controller: pane.controller,
                    focusNode: pane.focusNode,
                    theme: _terminalTheme,
                    cursorType: TerminalCursorType.block,
                    padding: const EdgeInsets.all(6),
                    textStyle: const TerminalStyle(
                      fontSize: 13.5,
                      fontFamily: 'Ubuntu Mono',
                      fontFamilyFallback: ['UbuntuMono', 'DejaVu Sans Mono', 'Liberation Mono', 'Courier New', 'monospace'],
                      height: 1.2,
                    ),
                    autofocus: isThisPaneActive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn(String label, String cmd, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _sendCmdToActive(cmd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: AppColors.accentCyan),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textWhite),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyBtn(String label, String code, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isHighlight ? AppColors.danger.withValues(alpha: 0.2) : AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            HapticFeedback.lightImpact();
            _sendKeyToActive(code);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isHighlight ? AppColors.danger : AppColors.borderDark,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: isHighlight ? AppColors.danger : AppColors.textWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
