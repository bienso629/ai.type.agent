import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/server_provider.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 1500,
    );
    _connectTerminal();
  }

  Future<void> _connectTerminal() async {
    final gateway = context.read<GatewayProvider>();
    final serverProvider = context.read<ServerProvider>();

    setState(() {
      _isConnecting = true;
    });

    _terminal.write('\r\n\x1b[36m⚡ Đang kết nối SSH WebSocket Terminal...\x1b[0m\r\n');

    try {
      final base = gateway.gatewayUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      final storage = StorageService();
      final userEmail = await storage.getUserEmail();
      var wsUrl = '$base${ApiConstants.wsTerminal}';
      final params = <String>[];
      if (userEmail != null && userEmail.isNotEmpty) {
        params.add('user_email=${Uri.encodeComponent(userEmail)}');
      }
      if (serverProvider.selectedServer?.id != null) {
        params.add('server_id=${Uri.encodeComponent(serverProvider.selectedServer!.id)}');
      }
      if (params.isNotEmpty) {
        wsUrl += '?${params.join('&')}';
      }
      final uri = Uri.parse(wsUrl);

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      _terminal.write('\x1b[32m✔ Kết nối thành công đến máy chủ: ${serverProvider.selectedServer?.name ?? "VPS"}\x1b[0m\r\n\r\n');

      _channel!.stream.listen(
        (data) {
          if (data is String) {
            _terminal.write(data);
          } else if (data is List<int>) {
            _terminal.write(utf8.decode(data, allowMalformed: true));
          }
        },
        onError: (err) {
          setState(() {
            _isConnected = false;
          });
          _terminal.write('\r\n\x1b[31m[Ngắt kết nối]: $err\x1b[0m\r\n');
        },
        onDone: () {
          setState(() {
            _isConnected = false;
          });
          _terminal.write('\r\n\x1b[33m[Phiên làm việc đã đóng]\x1b[0m\r\n');
        },
      );

      _terminal.onOutput = (data) {
        _channel?.sink.add(data);
      };
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
      _terminal.write('\r\n\x1b[31m[Lỗi kết nối]: $e\x1b[0m\r\n');
    }
  }

  void _sendCmd(String cmd) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add('$cmd\r');
    }
  }

  void _sendKey(String code) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(code);
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    const Icon(Icons.terminal_rounded, color: AppColors.accent, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Remote SSH Terminal Console',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
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
                                    _isConnected ? 'SSH ONLINE' : 'DISCONNECTED',
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
                        const Text(
                          'Thực thi toàn bộ lệnh shell Linux trực tiếp, duy trì phiên làm việc và môi trường Bash',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                            )
                          : Icon(
                              _isConnected ? Icons.refresh_rounded : Icons.link_rounded,
                              color: _isConnected ? AppColors.accent : AppColors.warning,
                              size: 18,
                            ),
                      tooltip: 'Kết nối lại',
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

          // 2. Exact Quick Action Chips from templates/index.html
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: AppColors.warning),
                      SizedBox(width: 4),
                      Text('Lệnh nhanh: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  _buildQuickBtn('top', 'top', Icons.show_chart_rounded, AppColors.accentCyan),
                  _buildQuickBtn('df -h', 'df -h', Icons.disc_full_rounded, AppColors.warning),
                  _buildQuickBtn('free -h', 'free -h', Icons.memory_rounded, AppColors.accent),
                  _buildQuickBtn('AI Status', 'systemctl status ai-agent.service', Icons.smart_toy_rounded, AppColors.primaryLight),
                  _buildQuickBtn('Log AI', 'journalctl -u ai-agent.service -n 50 --no-pager', Icons.description_rounded, AppColors.warning),
                  _buildQuickBtn('ss -tulnp', 'ss -tulnp', Icons.lan_rounded, AppColors.accentCyan),
                  _buildQuickBtn('Restart AI', 'systemctl restart ai-agent.service', Icons.restart_alt_rounded, AppColors.danger),
                ],
              ),
            ),
          ),

          // 3. XTerm Terminal View
          Expanded(
            child: Container(
              color: AppColors.terminalBg,
              padding: const EdgeInsets.all(8),
              child: TerminalView(
                _terminal,
                backgroundOpacity: 0.98,
                autofocus: true,
              ),
            ),
          ),

          // 4. Touch Keyboard Accessory Bar
          Container(
            color: AppColors.sidebarBg,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildKeyBtn('ESC', () => _sendKey('\x1b')),
                    _buildKeyBtn('TAB', () => _sendKey('\t')),
                    _buildKeyBtn('CTRL+C', () => _sendKey('\x03'), isAccent: true),
                    _buildKeyBtn('CTRL+D', () => _sendKey('\x04')),
                    _buildKeyBtn('CTRL+Z', () => _sendKey('\x1a')),
                    _buildKeyBtn('▲', () => _sendKey('\x1b[A')),
                    _buildKeyBtn('▼', () => _sendKey('\x1b[B')),
                    _buildKeyBtn('◀', () => _sendKey('\x1b[D')),
                    _buildKeyBtn('▶', () => _sendKey('\x1b[C')),
                    _buildKeyBtn('clear', () => _sendKey('clear\r')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBtn(String label, String command, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.borderDark),
          backgroundColor: AppColors.cardBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        icon: Icon(icon, size: 12, color: color),
        label: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textBody)),
        onPressed: () => _sendCmd(command),
      ),
    );
  }

  Widget _buildKeyBtn(String label, VoidCallback onTap, {bool isAccent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isAccent ? AppColors.danger.withValues(alpha: 0.3) : AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isAccent ? AppColors.danger : AppColors.borderDark,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isAccent ? AppColors.danger : AppColors.textWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
