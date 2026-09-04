import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, String> _testStatus = {}; // serverId -> 'testing' | 'success' | 'failed'
  final Set<String> _expandedServerIds = {};
  String? _deployingServerId;
  final Map<String, List<String>> _deployLogs = {};
  final Map<String, ScrollController> _deployScrollCtrls = {};
  final Map<String, StreamSubscription> _deploySubs = {};
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final sub in _deploySubs.values) {
      sub.cancel();
    }
    for (final ctrl in _deployScrollCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _testServerConnection(ServerModel server) async {
    setState(() {
      _testStatus[server.id] = 'testing';
    });

    final ok = await NativeSshService().testConnection(
      host: server.serverIp,
      port: server.sshPort,
      user: server.sshUser,
      pass: server.sshPass,
      key: server.sshKey,
    );

    if (mounted) {
      setState(() {
        _testStatus[server.id] = ok ? 'success' : 'failed';
      });
      if (ok) {
        AppToast.success(context, 'Kết nối thành công đến ${server.name} (${server.serverIp})');
      } else {
        AppToast.error(context, 'Không thể kết nối SSH đến ${server.serverIp}:${server.sshPort}');
      }
    }
  }


  Future<void> _switchToServer(ServerProvider serverProvider, ServerModel server) async {
    await serverProvider.selectServer(server);
    if (!mounted) return;
    AppToast.success(context, 'Đã kích hoạt máy chủ "${server.name}" (${server.serverIp})');
  }

  Future<bool> _executeSystemdAction(ServerModel server, String action, String actionName) async {
    try {
      final res = await _api.executeServiceAction('ai-agent', action, server: server);
      if (!mounted) return false;
      if (res['status'] == 'success' || res['status'] == 'ok') {
        AppToast.success(context, 'Đã gửi lệnh $actionName ai-agent.service trên máy chủ ${server.name}');
        return true;
      } else {
        AppToast.error(context, 'Lỗi $actionName trên máy chủ ${server.name}: ${res['error'] ?? 'Không thành công'}');
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      AppToast.error(context, 'Lỗi $actionName: $e');
      return false;
    }
  }

  Future<bool?> _showSystemdStatusModal(ServerModel server) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      ),
    );

    try {
      final res = await _api.executeServiceAction('ai-agent', 'status', server: server);
      final statusOutput = (res['output'] ?? res['message'] ?? 'Không nhận được thông tin trạng thái.').toString();
      final bool isActive = statusOutput.toLowerCase().contains('active (running)') || statusOutput.toLowerCase().contains('is-active: active');

      if (mounted) {
        Navigator.pop(context); // close loading
        showDialog(
          context: context,
          builder: (ctx) => TaduDialog(
            minWidth: 560,
            maxWidth: 760,
            title: Row(
              children: [
                const Icon(Icons.terminal_rounded, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 8),
                Text('Trạng Thái Systemd: ${server.name} (ai-agent.service)'),
              ],
            ),
            content: Container(
              width: double.infinity,
              height: 320,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.terminalBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  statusOutput,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.terminalGreen,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
      return isActive;
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppToast.error(context, 'Lỗi kiểm tra trạng thái: $e');
      }
      return null;
    }
  }



  void _startDeploy(ServerModel server) {
    if (_deployingServerId != null) return;
    setState(() {
      _deployingServerId = server.id;
      _expandedServerIds.add(server.id);
      _deployLogs[server.id] = ['⚡ Bắt đầu tự động thiết lập & Deploy Agent lên máy chủ ${server.name} (${server.serverIp})...'];
    });

    final scrollCtrl = _deployScrollCtrls.putIfAbsent(server.id, () => ScrollController());
    _deploySubs[server.id]?.cancel();
    _deploySubs[server.id] = _api.streamDeploy(
      server: server,
      onStep: (step) {
        setState(() {
          _deployLogs[server.id]?.add(step);
        });
        if (scrollCtrl.hasClients) {
          scrollCtrl.animateTo(
            scrollCtrl.position.maxScrollExtent + 40,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      },
      onDone: () {
        setState(() {
          _deployingServerId = null;
          _deployLogs[server.id]?.add('✔ Quá trình thiết lập trên máy chủ ${server.name} hoàn tất!');
        });
        if (mounted) AppToast.success(context, 'Thiết lập thành công trên ${server.name}!');
      },
      onError: (err) {
        setState(() {
          _deployingServerId = null;
          _deployLogs[server.id]?.add('❌ Lỗi thiết lập: $err');
        });
        if (mounted) AppToast.error(context, 'Lỗi thiết lập trên ${server.name}: $err');
      },
    );
  }

  void _showAddServerDialog(BuildContext context, [ServerModel? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.serverIp ?? '');
    final portCtrl = TextEditingController(text: existing?.sshPort.toString() ?? '22');
    final apiPortCtrl = TextEditingController(text: existing?.apiPort.toString() ?? '8000');
    final userCtrl = TextEditingController(text: existing?.sshUser ?? 'root');
    final passCtrl = TextEditingController(text: existing?.sshPass ?? '');
    final remoteDirCtrl = TextEditingController(text: existing?.remoteWorkDir ?? '/opt/ai_agent');
    String selectedAgentMode = existing?.agentMode ?? 'systemd';
    String selectedCliBinary = existing?.cliBinary ?? 'agy';
    bool isServiceActive = existing != null && (existing.status == 'online' || existing.status == 'active');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDeployingThis = existing != null && _deployingServerId == existing.id;
          final deployLogs = existing != null ? _deployLogs[existing.id] : null;
          final scrollCtrl = existing != null ? _deployScrollCtrls[existing.id] : null;

          return TaduDialog(
            minWidth: 580,
            maxWidth: 720,
            title: Row(
              children: [
                const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
                const SizedBox(width: 8),
                Text(existing != null ? 'Chỉnh Sửa Thông Tin Máy Chủ' : 'Thêm Máy Chủ VPS Mới'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tên gợi nhớ (Ví dụ: Web Production, Staging VPS):', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Tên máy chủ',
                      prefixIcon: Icon(Icons.label_outline_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Địa Chỉ IP / Hostname:', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: ipCtrl,
                              decoration: const InputDecoration(
                                hintText: '103.x.x.x hoặc domain.com',
                                prefixIcon: Icon(Icons.router_rounded, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SSH Port:', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: portCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '22',
                                prefixIcon: Icon(Icons.tag_rounded, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SSH User:', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: userCtrl,
                              decoration: const InputDecoration(
                                hintText: 'root / ubuntu',
                                prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SSH Password:', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: passCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: 'Mật khẩu root VPS',
                                prefixIcon: Icon(Icons.key_rounded, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Thư Mục Làm Việc Từ Xa (Remote Work Directory):', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: remoteDirCtrl,
                    decoration: const InputDecoration(
                      hintText: '/opt/ai_agent hoặc /root',
                      prefixIcon: Icon(Icons.folder_open_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.borderDark, height: 1),
                  const SizedBox(height: 12),

                  // ── CHẾ ĐỘ HOẠT ĐỘNG CỦA AI AGENT TRÊN MÁY CHỦ ──
                  const Text(
                    'CHẾ ĐỘ HOẠT ĐỘNG CỦA AI AGENT TRÊN MÁY CHỦ',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bgDark,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      children: [
                        // Option 1: Systemd Service (Tự Động)
                        InkWell(
                          onTap: () => setDialogState(() => selectedAgentMode = 'systemd'),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Radio<String>(
                                      value: 'systemd',
                                      groupValue: selectedAgentMode,
                                      activeColor: AppColors.primaryLight,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (val) {
                                        if (val != null) setDialogState(() => selectedAgentMode = val);
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'Chế độ 1: Dịch vụ nền Systemd (ai-agent.service)',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: const BoxDecoration(
                                                  color: AppColors.primary,
                                                  borderRadius: BorderRadius.all(Radius.circular(3)),
                                                ),
                                                child: const Text('Khuyên Dùng', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'Chạy AI Agent dạng background service ổn định, tự khởi động lại khi reboot, có API port',
                                            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (selectedAgentMode == 'systemd') ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 36, right: 6),
                                    child: Row(
                                      children: [
                                        const Text('API Port:', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 80,
                                          height: 32,
                                          child: TextField(
                                            controller: apiPortCtrl,
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(fontSize: 12),
                                            decoration: const InputDecoration(
                                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('(Port lắng nghe của ai-agent.service)', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                ],
                                if (selectedAgentMode == 'systemd' && existing != null) ...[
                                  const SizedBox(height: 12),
                                  const Divider(color: AppColors.borderDark, height: 1),
                                  const SizedBox(height: 10),

                                  // 1. Quản lý Dịch vụ Systemd trực tiếp (Start / Restart / Stop)
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderDark),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.shield_rounded, size: 15, color: AppColors.primaryLight),
                                            SizedBox(width: 6),
                                            Text(
                                              'Điều Khiển Dịch Vụ Systemd (ai-agent.service)',
                                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Thao tác quản trị dịch vụ Systemd trực tiếp trên máy chủ qua SSH:',
                                          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            // Start (chỉ hiển thị khi service chưa bật)
                                            if (!isServiceActive)
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                                                  foregroundColor: AppColors.accent,
                                                  side: const BorderSide(color: AppColors.accent),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                ),
                                                icon: const Icon(Icons.play_arrow_rounded, size: 14),
                                                label: const Text('Bật (Start)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                onPressed: () async {
                                                  final ok = await _executeSystemdAction(existing, 'start', 'khởi động');
                                                  if (ok) {
                                                    setDialogState(() {
                                                      isServiceActive = true;
                                                    });
                                                  }
                                                },
                                              ),
                                            // Restart (chỉ hiển thị khi service đã bật)
                                            if (isServiceActive)
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                                                  foregroundColor: AppColors.warning,
                                                  side: const BorderSide(color: AppColors.warning),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                ),
                                                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                                                label: const Text('Khởi Động Lại (Restart)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                onPressed: () async {
                                                  final ok = await _executeSystemdAction(existing, 'restart', 'khởi động lại');
                                                  if (ok) {
                                                    setDialogState(() {
                                                      isServiceActive = true;
                                                    });
                                                  }
                                                },
                                              ),
                                            // Stop (chỉ hiển thị khi service đã bật)
                                            if (isServiceActive)
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.danger.withValues(alpha: 0.15),
                                                  foregroundColor: AppColors.danger,
                                                  side: const BorderSide(color: AppColors.danger),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                ),
                                                icon: const Icon(Icons.stop_rounded, size: 14),
                                                label: const Text('Dừng (Stop)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                onPressed: () async {
                                                  final ok = await _executeSystemdAction(existing, 'stop', 'dừng');
                                                  if (ok) {
                                                    setDialogState(() {
                                                      isServiceActive = false;
                                                    });
                                                  }
                                                },
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // 2. 1-Click Deploy & Tự Động Thiết Lập Trọn Gói
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderDark),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(Icons.cloud_upload_rounded, size: 15, color: AppColors.accentCyan),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        '1-Click Deploy & Tự Động Thiết Lập',
                                                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    'Tự động cài đặt nhị phân, cấu hình Systemd service trên VPS',
                                                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Nút Kiểm Tra Trạng Thái (Status) nằm bên trái nút Thiết lập ngay
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: AppColors.primaryLight),
                                                foregroundColor: AppColors.primaryLight,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              ),
                                              icon: const Icon(Icons.terminal_rounded, size: 14),
                                              label: const Text('Kiểm Tra Trạng Thái', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                              onPressed: () async {
                                                final active = await _showSystemdStatusModal(existing);
                                                if (active != null) {
                                                  setDialogState(() {
                                                    isServiceActive = active;
                                                  });
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            // Nút Thiết lập ngay
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.primary,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              ),
                                              icon: isDeployingThis
                                                  ? const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                    )
                                                  : const Icon(Icons.rocket_launch_rounded, size: 13),
                                              label: Text(
                                                isDeployingThis ? 'Đang thiết lập...' : 'Thiết lập ngay',
                                                style: const TextStyle(fontSize: 10.5),
                                              ),
                                              onPressed: isDeployingThis
                                                  ? null
                                                  : () {
                                                      _startDeploy(existing);
                                                      setDialogState(() {});
                                                    },
                                            ),
                                          ],
                                        ),
                                        if (deployLogs != null && deployLogs.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            height: 110,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.terminalBg,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppColors.borderDark),
                                            ),
                                            child: ListView.builder(
                                              controller: scrollCtrl,
                                              itemCount: deployLogs.length,
                                              itemBuilder: (context, idx) {
                                                return Text(
                                                  deployLogs[idx],
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 10,
                                                    color: AppColors.terminalGreen,
                                                    height: 1.35,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // Tùy chọn 2: Chế độ CLI Agent (agy, claude, gemini)
                        InkWell(
                          onTap: () => setDialogState(() => selectedAgentMode = 'cli'),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedAgentMode == 'cli'
                                  ? AppColors.accent.withValues(alpha: 0.15)
                                  : AppColors.inputBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: selectedAgentMode == 'cli' ? AppColors.accent : AppColors.borderDark,
                                width: selectedAgentMode == 'cli' ? 1.2 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Radio<String>(
                                      value: 'cli',
                                      groupValue: selectedAgentMode,
                                      activeColor: AppColors.accent,
                                      onChanged: (val) => setDialogState(() => selectedAgentMode = val ?? 'cli'),
                                    ),
                                    const SizedBox(width: 4),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Chế độ 2: Chạy bằng CLI Agent cài sẵn (agy, claude, gemini...)',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Máy chủ đã được cài sẵn CLI như Google Antigravity (agy), Claude Code hoặc Gemini CLI',
                                            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (selectedAgentMode == 'cli') ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 36, right: 6),
                                    child: Row(
                                      children: [
                                        const Text('Lệnh CLI thực thi:', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                        const SizedBox(width: 8),
                                        DropdownButton<String>(
                                          value: selectedCliBinary,
                                          dropdownColor: AppColors.cardBg,
                                          style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite, fontFamily: 'monospace'),
                                          underline: Container(height: 1, color: AppColors.accent),
                                          items: const [
                                            DropdownMenuItem(value: 'agy', child: Text('agy (Google Antigravity CLI)')),
                                            DropdownMenuItem(value: 'claude', child: Text('claude (Claude Code CLI)')),
                                            DropdownMenuItem(value: 'gemini', child: Text('gemini (Google Gemini CLI)')),
                                            DropdownMenuItem(value: 'ollama', child: Text('ollama (Local LLM CLI)')),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) setDialogState(() => selectedCliBinary = val);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.save_rounded, size: 16),
                label: Text(existing != null ? 'Cập Nhật' : 'Thêm Máy Chủ'),
                onPressed: () async {
                  if (ipCtrl.text.trim().isEmpty) {
                    AppToast.error(context, 'Vui lòng nhập địa chỉ IP hoặc Hostname!');
                    return;
                  }
                  final newServer = ServerModel(
                    id: existing?.id ?? 'srv_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim().isEmpty ? ipCtrl.text.trim() : nameCtrl.text.trim(),
                    serverIp: ipCtrl.text.trim(),
                    sshPort: int.tryParse(portCtrl.text.trim()) ?? 22,
                    apiPort: int.tryParse(apiPortCtrl.text.trim()) ?? 8000,
                    sshUser: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                    sshPass: passCtrl.text.trim(),
                    remoteWorkDir: remoteDirCtrl.text.trim().isEmpty ? '/opt/ai_agent' : remoteDirCtrl.text.trim(),
                    agentMode: selectedAgentMode,
                    cliBinary: selectedCliBinary,
                    isSelected: existing?.isSelected ?? false,
                  );
                  Navigator.pop(ctx);
                  await context.read<ServerProvider>().addOrUpdateServer(newServer);
                  if (mounted) {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                    AppToast.success(this.context, 'Đã lưu thông tin máy chủ "${newServer.name}" (${newServer.isCliMode ? 'Chế độ 2: CLI ${newServer.cliBinary}' : 'Chế độ 1: Systemd'})!');
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleExportServers(ServerProvider serverProvider) async {
    try {
      final jsonStr = await serverProvider.exportServers(includeFullConfig: true);

      String? outputPath;
      try {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Lưu file sao lưu cấu hình config.json',
          fileName: 'config.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
      } catch (_) {}

      if (outputPath == null) {
        if (!mounted) return;
        AppToast.info(context, 'Đã huỷ thao tác sao lưu.');
        return;
      }

      final file = File(outputPath);
      await file.writeAsString(jsonStr);

      if (!mounted) return;
      AppToast.success(context, 'Đã lưu file sao lưu cấu hình: $outputPath');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Lỗi khi xuất cấu hình: $e');
    }
  }

  Future<void> _handleImportServers(ServerProvider serverProvider) async {
    final jsonCtrl = TextEditingController();
    bool overwrite = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => TaduDialog(
          minWidth: 540,
          maxWidth: 680,
          title: const Row(
            children: [
              Icon(Icons.upload_file_rounded, color: AppColors.primaryLight, size: 22),
              SizedBox(width: 8),
              Text('Khôi Phục / Nhập Danh Sách Máy Chủ (Import)'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chọn file sao lưu (.json) từ máy tính hoặc dán trực tiếp nội dung JSON cấu hình máy chủ vào ô bên dưới:',
                style: TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  side: const BorderSide(color: AppColors.primaryLight),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 16, color: AppColors.primaryLight),
                label: const Text('Chọn File .JSON Từ Máy Tính', style: TextStyle(fontSize: 12, color: AppColors.primaryLight)),
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                      dialogTitle: 'Chọn file sao lưu cấu hình Server (.json)',
                    );
                    if (result != null && result.files.single.path != null) {
                      final file = File(result.files.single.path!);
                      final content = await file.readAsString();
                      setDlgState(() {
                        jsonCtrl.text = content;
                      });
                      if (ctx.mounted) {
                        AppToast.info(ctx, 'Đã nạp nội dung từ: ${result.files.single.name}');
                      }
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      AppToast.error(ctx, 'Không thể đọc file: $e');
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: jsonCtrl,
                maxLines: 7,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textWhite),
                decoration: const InputDecoration(
                  hintText: 'Dán mã JSON chứa danh sách máy chủ tại đây...\n{\n  "servers": [ ... ]\n}',
                  hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: overwrite,
                    activeColor: AppColors.warning,
                    onChanged: (val) => setDlgState(() => overwrite = val ?? false),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Ghi đè toàn bộ danh sách hiện tại (Nếu không chọn, hệ thống sẽ gộp và cập nhật thêm máy chủ)',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textBody),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Thực Hiện Import'),
              onPressed: () async {
                final text = jsonCtrl.text.trim();
                if (text.isEmpty) {
                  AppToast.warning(ctx, 'Vui lòng chọn file JSON hoặc dán dữ liệu vào ô nhập.');
                  return;
                }

                try {
                  final count = await serverProvider.importServers(text, overwrite: overwrite);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    AppToast.success(ctx, 'Đã nhập thành công $count máy chủ vào hệ thống!');
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    AppToast.error(ctx, 'Lỗi định dạng JSON: $e');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final isRemoteActive = serverProvider.selectedServer != null &&
        serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
        serverProvider.selectedServer!.serverIp != 'localhost';

    final servers = serverProvider.servers.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.serverIp.toLowerCase().contains(q) ||
          s.sshUser.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. Header Bar (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Quản Lý Máy Chủ & Kết Nối SSH',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${serverProvider.servers.length} máy chủ',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          isRemoteActive
                              ? 'Đang kết nối: ${serverProvider.selectedServer!.name} (${serverProvider.selectedServer!.serverIp})'
                              : 'Chọn một máy chủ VPS bên dưới để kết nối và quản trị',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Tải lại danh sách máy chủ',
                      onPressed: () => serverProvider.loadServers(),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Sao lưu & Khôi phục dữ liệu',
                      color: AppColors.surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                      onSelected: (value) {
                        if (value == 'export') {
                          _handleExportServers(serverProvider);
                        } else if (value == 'import') {
                          _handleImportServers(serverProvider);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'export',
                          height: 36,
                          child: Row(
                            children: [
                              Icon(Icons.file_download_outlined, size: 15, color: AppColors.accentCyan),
                              SizedBox(width: 8),
                              Text('Sao lưu (Export)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'import',
                          height: 36,
                          child: Row(
                            children: [
                              Icon(Icons.file_upload_outlined, size: 15, color: AppColors.accent),
                              SizedBox(width: 8),
                              Text('Khôi phục (Import)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          border: Border.all(color: AppColors.borderDark),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync_alt_rounded, size: 15, color: AppColors.textDim),
                            SizedBox(width: 6),
                            Text('Sao Lưu & Khôi Phục', style: TextStyle(fontSize: 12, color: AppColors.textBody, fontWeight: FontWeight.w500)),
                            SizedBox(width: 2),
                            Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppColors.textDim),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Thêm Máy Chủ Mới', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _showAddServerDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Search & Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchCtrl,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Tìm kiếm nhanh máy chủ theo tên, IP, username...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textDim),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.primaryLight, width: 1),
                  ),
                ),
              ),
            ),
          ),

          if (_searchQuery.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 14, color: AppColors.primaryLight),
                  const SizedBox(width: 6),
                  Text(
                    'Đang lọc theo: "$_searchQuery" (${servers.length} kết quả)',
                    style: const TextStyle(fontSize: 12, color: AppColors.primaryLight),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Text(
                      'Xóa bộ lọc (Hiện tất cả)',
                      style: TextStyle(fontSize: 12, color: AppColors.accentCyan, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Main Server List
          Expanded(
            child: serverProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : servers.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          margin: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.dns_outlined, size: 36, color: AppColors.textDim),
                              const SizedBox(height: 10),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Không tìm thấy máy chủ nào khớp với "$_searchQuery"'
                                    : 'Chưa có máy chủ VPS nào trong danh sách',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                icon: const Icon(Icons.add_rounded, size: 15),
                                label: const Text('Thêm Máy Chủ VPS Ngay', style: TextStyle(fontSize: 12)),
                                onPressed: () => _showAddServerDialog(context),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: servers.length,
                        itemBuilder: (context, index) {
                          final s = servers[index];
                          final isSelected = isRemoteActive &&
                              serverProvider.selectedServer != null &&
                              (s.id == serverProvider.selectedServer!.id || s.serverIp == serverProvider.selectedServer!.serverIp);
                          final test = _testStatus[s.id];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.cardBg : AppColors.cardBg.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.borderDark,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Server Icon & Active Indicator
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary.withValues(alpha: 0.15)
                                          : AppColors.inputBg,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderDark,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.dns_rounded,
                                      size: 24,
                                      color: isSelected ? AppColors.primaryLight : AppColors.textDim,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Server Information
                                  Expanded(
                                    child: InkWell(
                                      hoverColor: Colors.transparent,
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      mouseCursor: SystemMouseCursors.click,
                                      onTap: () {
                                        if (!isSelected) _switchToServer(serverProvider, s);
                                      },
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                s.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.textWhite),
                                              ),
                                              if (isSelected) ...[
                                                const SizedBox(width: 10),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.check_circle_rounded, size: 11, color: Colors.white),
                                                      SizedBox(width: 3),
                                                      Text(
                                                        'ĐANG HOẠT ĐỘNG',
                                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.inputBg,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppColors.borderDark),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.terminal_rounded, size: 12, color: AppColors.accentCyan),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${s.sshUser}@${s.serverIp}:${s.sshPort}',
                                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textWhite),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.inputBg,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppColors.borderDark),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.folder_special_outlined, size: 12, color: AppColors.warning),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      s.remoteWorkDir.isNotEmpty ? s.remoteWorkDir : '/opt/ai_agent',
                                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textMuted),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: s.isCliMode
                                                      ? AppColors.accent.withValues(alpha: 0.15)
                                                      : AppColors.primary.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: s.isCliMode
                                                        ? AppColors.accent.withValues(alpha: 0.4)
                                                        : AppColors.primaryLight.withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      s.isCliMode ? Icons.terminal_rounded : Icons.shield_rounded,
                                                      size: 11,
                                                      color: s.isCliMode ? AppColors.accent : AppColors.primaryLight,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      s.isCliMode ? 'Chế độ 2: CLI (${s.cliBinary})' : 'Chế độ 1: Systemd (Port ${s.apiPort})',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: s.isCliMode ? AppColors.accent : AppColors.primaryLight,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Action Buttons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Test Connection Button (Icon only)
                                      IconButton(
                                        icon: test == 'testing'
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                              )
                                            : Icon(
                                                test == 'success'
                                                    ? Icons.wifi_protected_setup_rounded
                                                    : test == 'failed'
                                                        ? Icons.error_outline_rounded
                                                        : Icons.wifi_protected_setup_rounded,
                                                size: 16,
                                                color: test == 'success'
                                                    ? AppColors.accent
                                                    : test == 'failed'
                                                        ? AppColors.danger
                                                        : AppColors.textDim,
                                              ),
                                        tooltip: test == 'testing'
                                            ? 'Đang thử kết nối...'
                                            : test == 'success'
                                                ? 'Kết nối thành công (Online) - Bấm để thử lại'
                                                : test == 'failed'
                                                    ? 'Lỗi kết nối - Bấm để thử lại'
                                                    : 'Thử kết nối máy chủ',
                                        onPressed: test == 'testing' ? null : () => _testServerConnection(s),
                                      ),
                                      const SizedBox(width: 8),

                                      // Edit Button
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textDim),
                                        tooltip: 'Chỉnh sửa thông tin máy chủ',
                                        onPressed: () => _showAddServerDialog(context, s),
                                      ),

                                      // Delete Button
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                                        tooltip: 'Xóa máy chủ khỏi danh sách',
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => TaduDialog(
                                              minWidth: 420,
                                              maxWidth: 500,
                                              title: const Row(
                                                children: [
                                                  Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 22),
                                                  SizedBox(width: 8),
                                                  Text('Xác Nhận Xóa Máy Chủ'),
                                                ],
                                              ),
                                              content: Text('Bạn có chắc muốn xóa máy chủ "${s.name}" (${s.serverIp})?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx),
                                                  child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                                  onPressed: () {
                                                    final srvId = s.id;
                                                    final srvName = s.name;
                                                    Navigator.pop(ctx);
                                                    serverProvider.deleteServer(srvId);
                                                    if (mounted) {
                                                      AppToast.success(context, 'Đã xóa máy chủ "$srvName" thành công!');
                                                    }
                                                  },
                                                  child: const Text('Xóa vĩnh viễn'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
