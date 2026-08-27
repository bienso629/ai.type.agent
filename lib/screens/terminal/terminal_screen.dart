import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

enum TerminalSplitMode {
  single,
  horizontal,
  vertical,
}

class TerminalPaneItem {
  final String id;
  String title;
  bool isRemoteSsh;
  ServerModel? server;
  late final Terminal terminal;
  late final FocusNode focusNode;
  Process? process;
  SSHClient? sshClient;
  SSHSession? sshSession;
  bool isConnected = false;
  bool isConnecting = false;

  TerminalPaneItem({
    required this.id,
    required this.title,
    this.isRemoteSsh = false,
    this.server,
  }) {
    focusNode = FocusNode();
    terminal = Terminal(maxLines: 3000);
  }

  void cleanup() {
    try {
      process?.kill();
      process = null;
    } catch (_) {}
    try {
      sshSession?.close();
      sshSession = null;
    } catch (_) {}
    try {
      sshClient?.close();
      sshClient = null;
    } catch (_) {}
  }

  void dispose() {
    focusNode.dispose();
    cleanup();
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
  TerminalSplitMode _splitMode = TerminalSplitMode.single;
  bool _showVirtualKeyboard = false;

  static final _terminalTheme = TerminalTheme(
    cursor: AppColors.accentCyan,
    selection: AppColors.primary.withValues(alpha: 0.35),
    foreground: AppColors.textWhite,
    background: AppColors.bgDark,
    black: AppColors.bgDark,
    red: AppColors.danger,
    green: AppColors.accent,
    yellow: AppColors.warning,
    blue: AppColors.accentCyan,
    magenta: const Color(0xFFC084FC),
    cyan: AppColors.accentCyan,
    white: AppColors.textWhite,
    brightBlack: AppColors.borderLight,
    brightRed: AppColors.primaryLight,
    brightGreen: const Color(0xFF4ADE80),
    brightYellow: const Color(0xFFFDE047),
    brightBlue: const Color(0xFF38BDF8),
    brightMagenta: const Color(0xFFE879F9),
    brightCyan: const Color(0xFF67E8F9),
    brightWhite: Colors.white,
    searchHitBackground: AppColors.warning,
    searchHitBackgroundCurrent: AppColors.accent,
    searchHitForeground: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    // Initialize default primary pane (Local)
    final firstPane = TerminalPaneItem(
      id: 'pane_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Local Machine',
      isRemoteSsh: false,
    );
    _panes.add(firstPane);
    _connectPane(firstPane);
  }

  @override
  void dispose() {
    for (final p in _panes) {
      p.dispose();
    }
    _panes.clear();
    super.dispose();
  }

  TerminalPaneItem? get _activePane {
    if (_panes.isEmpty) return null;
    if (_activePaneIndex >= 0 && _activePaneIndex < _panes.length) {
      return _panes[_activePaneIndex];
    }
    return _panes.first;
  }

  String _normalizeNewlines(String text) {
    return text.replaceAll(RegExp(r'(?<!\r)\n'), '\r\n');
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
    pane.terminal.write('\r\n\x1b[36m⚡ Đang mở Local Interactive Terminal...\x1b[0m\r\n');

    try {
      final isWin = Platform.isWindows;
      final shell = Platform.environment['SHELL'] ??
          (isWin ? 'cmd.exe' : (File('/bin/bash').existsSync() ? '/bin/bash' : '/bin/sh'));
      final args = isWin ? <String>[] : <String>['-i'];

      pane.process = await Process.start(
        shell,
        args,
        workingDirectory: isWin ? 'C:\\' : '/',
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
        },
        mode: ProcessStartMode.normal,
      );

      pane.terminal.write('\x1b[32m✔ Đã sẵn sàng Terminal Local: $shell (${Platform.operatingSystem})\x1b[0m\r\n\r\n');

      if (mounted) {
        setState(() {
          pane.isConnected = true;
          pane.isConnecting = false;
        });
      }

      pane.process!.stdout.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          pane.terminal.write(_normalizeNewlines(decoded));
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

      pane.process!.stderr.listen((data) {
        final decoded = utf8.decode(data, allowMalformed: true);
        pane.terminal.write(_normalizeNewlines(decoded));
      });

      pane.terminal.onOutput = (data) {
        if (pane.process != null) {
          try {
            pane.process!.stdin.add(utf8.encode(data));
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

  Future<void> _connectSshPane(TerminalPaneItem pane) async {
    final serverProvider = context.read<ServerProvider>();
    final server = pane.server ?? (serverProvider.selectedServer?.serverIp != '127.0.0.1' ? serverProvider.selectedServer : null) ?? (serverProvider.servers.isNotEmpty ? serverProvider.servers.first : null);
    final serverName = server?.name ?? 'Remote Server';
    final serverIp = server?.serverIp ?? '127.0.0.1';
    final serverPort = server?.sshPort ?? 22;

    pane.server = server;
    if (server != null) {
      pane.title = server.name;
    }

    pane.terminal.write('\r\n\x1b[36m⚡ Đang kết nối SSH Interactive Terminal tới $serverName ($serverIp:$serverPort)...\x1b[0m\r\n');

    try {
      pane.sshClient = await NativeSshService().getClient(server: server);
      pane.sshSession = await pane.sshClient!.shell(
        pty: const SSHPtyConfig(
          width: 100,
          height: 30,
        ),
      );

      pane.terminal.write('\x1b[32m✔ Đã kết nối SSH thành công tới $serverName ($serverIp:$serverPort)!\x1b[0m\r\n\r\n');

      if (mounted) {
        setState(() {
          pane.isConnected = true;
          pane.isConnecting = false;
        });
      }

      pane.sshSession!.stdout.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          pane.terminal.write(_normalizeNewlines(decoded));
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
        pane.terminal.write(_normalizeNewlines(decoded));
      });

      pane.terminal.onOutput = (data) {
        pane.sshSession?.stdin.add(utf8.encode(data));
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

  void _addPane({bool isSsh = false, ServerModel? srv}) {
    if (_panes.length >= 4) return;
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
      if (_splitMode == TerminalSplitMode.single) {
        _splitMode = TerminalSplitMode.horizontal;
      }
    });
    _connectPane(newPane);
  }

  void _removePane(int index) {
    if (_panes.length <= 1) return;
    final removed = _panes.removeAt(index);
    removed.dispose();
    setState(() {
      if (_activePaneIndex >= _panes.length) {
        _activePaneIndex = _panes.length - 1;
      }
      if (_panes.length == 1) {
        _splitMode = TerminalSplitMode.single;
      }
    });
  }

  void _setSplitMode(TerminalSplitMode mode) {
    if (mode != TerminalSplitMode.single && _panes.length < 2) {
      final srvProvider = context.read<ServerProvider>();
      final srv = srvProvider.selectedServer;
      final shouldBeSsh = srv != null && srv.serverIp != '127.0.0.1' && srv.serverIp != 'localhost';
      _addPane(isSsh: shouldBeSsh, srv: shouldBeSsh ? srv : null);
    }
    setState(() {
      _splitMode = mode;
    });
  }

  void _sendCmdToActive(String cmd) {
    final pane = _activePane;
    if (pane != null && pane.isConnected) {
      if (pane.isRemoteSsh && pane.sshSession != null) {
        pane.sshSession!.stdin.add(utf8.encode('$cmd\n'));
      } else if (pane.process != null) {
        try {
          pane.process!.stdin.add(utf8.encode('$cmd\n'));
        } catch (_) {}
      }
    }
  }

  void _sendKeyToActive(String code) {
    final pane = _activePane;
    if (pane != null && pane.isConnected) {
      if (pane.isRemoteSsh && pane.sshSession != null) {
        pane.sshSession!.stdin.add(utf8.encode(code));
      } else if (pane.process != null) {
        try {
          pane.process!.stdin.add(utf8.encode(code));
        } catch (_) {}
      }
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset position, int paneIndex, ServerProvider serverProvider) async {
    final pane = _panes[paneIndex];
    setState(() {
      _activePaneIndex = paneIndex;
    });
    pane.focusNode.requestFocus();

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
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      elevation: 10,
      items: [
        // 1. SPLIT LAYOUT
        const PopupMenuItem<String>(
          enabled: false,
          height: 26,
          child: Text('BỐ CỤC MÀN HÌNH (SPLIT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
        ),
        PopupMenuItem<String>(
          value: 'split_single',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.crop_square_rounded, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Toàn màn hình (Đơn)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (_splitMode == TerminalSplitMode.single) ...[
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
              if (_splitMode == TerminalSplitMode.horizontal) ...[
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
              if (_splitMode == TerminalSplitMode.vertical) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(height: 10),

        // 2. ADD PANE
        if (_panes.length < 4) ...[
          const PopupMenuItem<String>(
            enabled: false,
            height: 26,
            child: Text('THÊM PANEL MỚI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
          ),
          const PopupMenuItem<String>(
            value: 'add_local',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.laptop_chromebook_rounded, size: 15, color: AppColors.accent),
                SizedBox(width: 8),
                Text('Thêm Local Terminal', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              ],
            ),
          ),
          for (final s in serverProvider.servers)
            PopupMenuItem<String>(
              value: 'add_ssh_${s.id}',
              height: 34,
              child: Row(
                children: [
                  const Icon(Icons.dns_rounded, size: 15, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Text('Thêm SSH: ${s.name}', style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                ],
              ),
            ),
          const PopupMenuDivider(height: 10),
        ],

        // 3. ACTION FOR THIS PANE
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

        // 4. CLOSE PANE (if > 1)
        if (_panes.length > 1) ...[
          const PopupMenuDivider(height: 10),
          PopupMenuItem<String>(
            value: 'close_pane',
            height: 34,
            child: const Row(
              children: [
                Icon(Icons.close_rounded, size: 15, color: AppColors.danger),
                SizedBox(width: 8),
                Text('Đóng Panel này', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ],
    );

    if (result == null) return;

    if (result == 'split_single') {
      _setSplitMode(TerminalSplitMode.single);
    } else if (result == 'split_horizontal') {
      _setSplitMode(TerminalSplitMode.horizontal);
    } else if (result == 'split_vertical') {
      _setSplitMode(TerminalSplitMode.vertical);
    } else if (result == 'add_local') {
      _addPane(isSsh: false);
    } else if (result.startsWith('add_ssh_')) {
      final srvId = result.replaceFirst('add_ssh_', '');
      final srv = serverProvider.servers.firstWhere((s) => s.id == srvId, orElse: () => serverProvider.servers.first);
      _addPane(isSsh: true, srv: srv);
    } else if (result == 'restart_pane') {
      _connectPane(pane);
    } else if (result == 'clear_pane') {
      pane.terminal.eraseDisplay();
      pane.terminal.setCursor(0, 0);
    } else if (result == 'close_pane') {
      _removePane(paneIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final activePane = _activePane;

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
                              _panes.length > 1
                                  ? 'Split Panel: ${_panes.length} cửa sổ song song (${_splitMode == TerminalSplitMode.horizontal ? 'Trái / Phải' : 'Trên / Dưới'}) • Nhấn chuột phải để tuỳ chỉnh'
                                  : (activePane?.isRemoteSsh == true
                                      ? 'Phiên SSH với ${activePane?.server?.name ?? serverProvider.selectedServer?.name ?? 'Server'} • Nhấn chuột phải để chia màn hình'
                                      : 'Thực thi toàn bộ lệnh shell cục bộ (${Platform.operatingSystem}) • Nhấn chuột phải để chia màn hình'),
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

    if (_splitMode == TerminalSplitMode.single || _panes.length == 1) {
      final pane = (_activePaneIndex >= 0 && _activePaneIndex < _panes.length)
          ? _panes[_activePaneIndex]
          : _panes.first;
      return _buildPaneCard(pane, 0, serverProvider, isOnlyOne: true);
    }

    if (_splitMode == TerminalSplitMode.horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _panes.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _buildPaneCard(_panes[i], i, serverProvider)),
          ],
        ],
      );
    }

    // Vertical Split
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _panes.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Expanded(child: _buildPaneCard(_panes[i], i, serverProvider)),
        ],
      ],
    );
  }

  Widget _buildPaneCard(TerminalPaneItem pane, int index, ServerProvider serverProvider, {bool isOnlyOne = false}) {
    final isActive = _activePaneIndex == index;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_activePaneIndex != index) {
          setState(() {
            _activePaneIndex = index;
          });
        }
        if (!pane.focusNode.hasFocus) {
          pane.focusNode.requestFocus();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_activePaneIndex != index) {
            setState(() {
              _activePaneIndex = index;
            });
          }
          pane.focusNode.requestFocus();
        },
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, index, serverProvider),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? AppColors.accent : AppColors.borderDark,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              // Sub-Header for each pane
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent.withValues(alpha: 0.12) : AppColors.cardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppColors.accent.withValues(alpha: 0.35) : AppColors.borderDark,
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
                              _activePaneIndex = index;
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
                      ],
                    ),

                    Row(
                      children: [
                        if (isActive)
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
                            _showContextMenu(context, Offset(pos.dx + box.size.width - 200, pos.dy + 100), index, serverProvider);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
                          tooltip: 'Khởi động lại terminal này',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () => _connectPane(pane),
                        ),
                        if (!isOnlyOne && _panes.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                            tooltip: 'Đóng panel này',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => _removePane(index),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Terminal View
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TerminalView(
                    pane.terminal,
                    focusNode: pane.focusNode,
                    theme: _terminalTheme,
                    textStyle: const TerminalStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    autofocus: isActive,
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
