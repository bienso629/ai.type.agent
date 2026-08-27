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

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  Process? _process;
  SSHClient? _sshClient;
  SSHSession? _sshSession;
  bool _isRemoteSshMode = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _showVirtualKeyboard = false;

  static final _localTerminalTheme = TerminalTheme(
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

  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _terminal = Terminal(
      maxLines: 3000,
    );
    _connectTerminal();
  }

  void _cleanupConnections() {
    try {
      _process?.kill();
      _process = null;
    } catch (_) {}
    try {
      _sshSession?.close();
      _sshSession = null;
    } catch (_) {}
    try {
      _sshClient?.close();
      _sshClient = null;
    } catch (_) {}
  }

  Future<void> _connectTerminal() async {
    _cleanupConnections();
    setState(() {
      _isConnecting = true;
    });

    if (_isRemoteSshMode) {
      await _connectSshTerminal();
    } else {
      await _connectLocalTerminal();
    }
  }

  Future<void> _connectLocalTerminal() async {
    _terminal.write('\r\n\x1b[36m⚡ Đang mở Local Interactive Terminal...\x1b[0m\r\n');

    try {
      final isWin = Platform.isWindows;
      final shell = Platform.environment['SHELL'] ??
          (isWin ? 'cmd.exe' : (File('/bin/bash').existsSync() ? '/bin/bash' : '/bin/sh'));
      final args = isWin ? <String>[] : <String>['-i'];

      _process = await Process.start(
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

      _terminal.write('\x1b[32m✔ Đã sẵn sàng Terminal Local: $shell (${Platform.operatingSystem})\x1b[0m\r\n\r\n');

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      _process!.stdout.listen(
        (data) {
          final decoded = utf8.decode(data, allowMalformed: true);
          _terminal.write(_normalizeNewlines(decoded));
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
          _terminal.write('\r\n\x1b[33m[Tiến trình Terminal đã thoát]\x1b[0m\r\n');
        },
        onError: (err) {
          if (mounted) setState(() => _isConnected = false);
          _terminal.write('\r\n\x1b[31m[Lỗi Terminal]: $err\x1b[0m\r\n');
        },
      );

      _process!.stderr.listen((data) {
        final decoded = utf8.decode(data, allowMalformed: true);
        _terminal.write(_normalizeNewlines(decoded));
      });

      _terminal.onOutput = (data) {
        if (_process != null) {
          try {
            _process!.stdin.add(utf8.encode(data));
          } catch (_) {}
        }
      };
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
        });
      }
      _terminal.write('\r\n\x1b[31m[Lỗi mở Terminal cục bộ]: $e\x1b[0m\r\n');
    }
  }

  Future<void> _connectSshTerminal() async {
    final serverProvider = context.read<ServerProvider>();
    final serverName = serverProvider.selectedServer?.name ?? 'Remote Server';
    final serverIp = serverProvider.selectedServer?.serverIp ?? '127.0.0.1';

    _terminal.write('\r\n\x1b[36m⚡ Đang kết nối SSH Interactive Terminal tới $serverName ($serverIp)...\x1b[0m\r\n');

    try {
      _sshClient = await NativeSshService().getClient();
      _sshSession = await _sshClient!.shell(
        pty: const SSHPtyConfig(
          width: 100,
          height: 30,
        ),
      );

      _terminal.write('\x1b[32m✔ Đã kết nối SSH thành công tới $serverName ($serverIp)!\x1b[0m\r\n\r\n');

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      _sshSession!.stdout.listen(
        (data) {
          _terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
          _terminal.write('\r\n\x1b[33m[Phiên SSH Terminal đã đóng]\x1b[0m\r\n');
        },
        onError: (err) {
          if (mounted) setState(() => _isConnected = false);
          _terminal.write('\r\n\x1b[31m[Lỗi SSH]: $err\x1b[0m\r\n');
        },
      );

      _sshSession!.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });

      _terminal.onOutput = (data) {
        _sshSession?.stdin.add(utf8.encode(data));
      };
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
        });
      }
      _terminal.write('\r\n\x1b[31m[Lỗi kết nối SSH Terminal]: $e\x1b[0m\r\n');
    }
  }

  void _sendCmd(String cmd) {
    if (_isConnected) {
      if (_isRemoteSshMode && _sshSession != null) {
        _sshSession!.stdin.add(utf8.encode('$cmd\n'));
      } else if (_process != null) {
        try {
          _process!.stdin.add(utf8.encode('$cmd\n'));
        } catch (_) {}
      }
    }
  }

  void _sendKey(String code) {
    if (_isConnected) {
      if (_isRemoteSshMode && _sshSession != null) {
        _sshSession!.stdin.add(utf8.encode(code));
      } else if (_process != null) {
        try {
          _process!.stdin.add(utf8.encode(code));
        } catch (_) {}
      }
    }
  }

  String _normalizeNewlines(String text) {
    return text.replaceAll(RegExp(r'(?<!\r)\n'), '\r\n');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _cleanupConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. Topbar Header (Height 66px)
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
                Row(
                  children: [
                    Icon(
                      _isRemoteSshMode ? Icons.dns_rounded : Icons.terminal_rounded,
                      color: _isRemoteSshMode ? AppColors.primaryLight : AppColors.accent,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _isRemoteSshMode
                                  ? 'SSH Remote Terminal (${serverProvider.selectedServer?.name ?? 'Server'})'
                                  : 'Local Terminal Console',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (_isConnected ? AppColors.accent : AppColors.danger).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: _isConnected ? AppColors.accent : AppColors.danger),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: _isConnected ? AppColors.accent : AppColors.danger,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isConnected
                                        ? (_isRemoteSshMode ? 'SSH CONNECTED' : 'LOCAL READY')
                                        : (_isConnecting ? 'CONNECTING...' : 'OFFLINE'),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: _isConnected ? AppColors.accent : AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _isRemoteSshMode
                            ? 'Phiên làm việc SSH PTY trực tiếp với ${serverProvider.selectedServer?.serverIp ?? 'Server'}'
                            : 'Thực thi toàn bộ lệnh shell trực tiếp trên máy cục bộ (${Platform.operatingSystem})',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Mode Switcher (Local vs SSH)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              if (_isRemoteSshMode) {
                                setState(() => _isRemoteSshMode = false);
                                _connectTerminal();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: !_isRemoteSshMode ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.laptop_chromebook_rounded, size: 13, color: !_isRemoteSshMode ? Colors.white : AppColors.textDim),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Local',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: !_isRemoteSshMode ? FontWeight.bold : FontWeight.normal,
                                      color: !_isRemoteSshMode ? Colors.white : AppColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              if (!_isRemoteSshMode) {
                                setState(() => _isRemoteSshMode = true);
                                _connectTerminal();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isRemoteSshMode ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.dns_rounded, size: 13, color: _isRemoteSshMode ? Colors.white : AppColors.textDim),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SSH Server',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: _isRemoteSshMode ? FontWeight.bold : FontWeight.normal,
                                      color: _isRemoteSshMode ? Colors.white : AppColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isRemoteSshMode && serverProvider.servers.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<ServerModel>(
                        tooltip: 'Chọn máy chủ SSH để mở Terminal',
                        offset: const Offset(0, 36),
                        color: AppColors.cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                          side: const BorderSide(color: AppColors.borderDark),
                        ),
                        onSelected: (srv) async {
                          await serverProvider.selectServer(srv);
                          _connectTerminal();
                        },
                        itemBuilder: (ctx) => serverProvider.servers.map((s) {
                          final isSel = s.id == serverProvider.selectedServer?.id || s.serverIp == serverProvider.selectedServer?.serverIp;
                          return PopupMenuItem<ServerModel>(
                            value: s,
                            child: Row(
                              children: [
                                const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      Text('${s.sshUser}@${s.serverIp}:${s.sshPort}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                                if (isSel) const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryLight),
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: Text(
                                  serverProvider.selectedServer?.name ?? 'Chọn Server',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down_rounded, size: 14, color: AppColors.primaryLight),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
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
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                            )
                          : Icon(
                              _isConnected ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                              color: _isConnected ? AppColors.accent : AppColors.warning,
                              size: 18,
                            ),
                      tooltip: 'Khởi động lại Terminal',
                      onPressed: _connectTerminal,
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBg,
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.cleaning_services_rounded, size: 14),
                      label: const Text('Xoá màn hình', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        _terminal.write('\x1b[2J\x1b[H');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Quick Action Chips Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Lệnh nhanh: ', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  _buildQuickActionBtn('ls -la', 'ls -la', Icons.folder_open_rounded),
                  _buildQuickActionBtn('pwd', 'pwd', Icons.location_on_outlined),
                  _buildQuickActionBtn('df -h', 'df -h', Icons.storage_rounded),
                  _buildQuickActionBtn('free -m', 'free -m', Icons.memory_rounded),
                  _buildQuickActionBtn('top / htop', 'htop || top', Icons.speed_rounded),
                  _buildQuickActionBtn('git status', 'git status', Icons.commit_rounded),
                  _buildQuickActionBtn('ps aux', 'ps aux', Icons.list_alt_rounded),
                  _buildQuickActionBtn('clear', 'clear', Icons.cleaning_services_outlined),
                ],
              ),
            ),
          ),

          // 3. Virtual Key Bar (if enabled)
          if (_showVirtualKeyboard)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: AppColors.cardBg,
                border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildKeyBtn('ESC', '\x1b'),
                    _buildKeyBtn('TAB', '\t'),
                    _buildKeyBtn('CTRL+C', '\x03', isHighlight: true),
                    _buildKeyBtn('CTRL+D', '\x04'),
                    _buildKeyBtn('CTRL+Z', '\x1a'),
                    _buildKeyBtn('↑', '\x1b[A'),
                    _buildKeyBtn('↓', '\x1b[B'),
                    _buildKeyBtn('←', '\x1b[D'),
                    _buildKeyBtn('→', '\x1b[C'),
                    _buildKeyBtn('HOME', '\x1b[H'),
                    _buildKeyBtn('END', '\x1b[F'),
                    _buildKeyBtn('PAGE UP', '\x1b[5~'),
                    _buildKeyBtn('PAGE DOWN', '\x1b[6~'),
                  ],
                ),
              ),
            ),

          // 4. Main Terminal View
          Expanded(
            child: Container(
              color: AppColors.bgDark,
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: GestureDetector(
                  onTap: () {
                    _focusNode.requestFocus();
                  },
                  child: TerminalView(
                    _terminal,
                    focusNode: _focusNode,
                    theme: _localTerminalTheme,
                    textStyle: const TerminalStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    autofocus: true,
                  ),
                ),
              ),
            ),
          ),
        ],
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
          onTap: () => _sendCmd(cmd),
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
            _sendKey(code);
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
