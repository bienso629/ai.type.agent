import 'dart:async';
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

  void _handleServiceAction(ServerModel server, String action) async {
    final actionLabel = action == 'start'
        ? 'khởi động'
        : action == 'restart'
            ? 'khởi động lại'
            : action == 'stop'
                ? 'tắt'
                : 'kiểm tra chi tiết';
    AppToast.info(context, 'Đang gửi lệnh $actionLabel dịch vụ trên ${server.name}...');

    final res = await _api.executeServiceAction('ai-agent', action, server: server);
    final output = res['output']?.toString() ?? res['message']?.toString() ?? 'Không có phản hồi từ máy chủ';
    final msg = res['message']?.toString() ?? output;

    if (action == 'status') {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => TaduDialog(
          minWidth: 640,
          maxWidth: 820,
          maxHeight: 520,
          title: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 22),
              const SizedBox(width: 8),
              Text('Chi Tiết Trạng Thái Service - ${server.name} (${server.serverIp})'),
            ],
          ),
          content: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.terminalBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.terminalGreen, height: 1.4),
              ),
            ),
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
    } else {
      if (mounted) {
        if (res['status'] == 'error') {
          AppToast.error(context, msg);
        } else {
          AppToast.success(context, msg);
        }
      }
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
    final userCtrl = TextEditingController(text: existing?.sshUser ?? 'root');
    final passCtrl = TextEditingController(text: existing?.sshPass ?? '');
    final remoteDirCtrl = TextEditingController(text: existing?.remoteWorkDir ?? '/opt/ai_agent');

    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 520,
        maxWidth: 640,
        title: Row(
          children: [
            const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
            const SizedBox(width: 8),
            Text(existing != null ? 'Chỉnh Sửa Máy Chủ' : 'Thêm Máy Chủ VPS Mới'),
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
                  const SizedBox(width: 12),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mật khẩu SSH (hoặc sudo pass):', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'Mật khẩu SSH',
                            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Thư mục làm việc trên Server (Remote Work Dir):', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
              const SizedBox(height: 6),
              TextField(
                controller: remoteDirCtrl,
                decoration: const InputDecoration(
                  hintText: '/opt/ai_agent hoặc /var/www',
                  prefixIcon: Icon(Icons.folder_special_outlined, size: 18),
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
                sshUser: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                sshPass: passCtrl.text.trim(),
                remoteWorkDir: remoteDirCtrl.text.trim().isEmpty ? '/opt/ai_agent' : remoteDirCtrl.text.trim(),
                isSelected: existing?.isSelected ?? false,
              );
              Navigator.pop(ctx);
              await context.read<ServerProvider>().addOrUpdateServer(newServer);
              if (mounted) {
                _searchCtrl.clear();
                setState(() => _searchQuery = '');
                AppToast.success(this.context, 'Đã lưu thông tin máy chủ "${newServer.name}"!');
              }
            },
          ),
        ],
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
                          final isDeployingThis = _deployingServerId == s.id;
                          final isExpanded = _expandedServerIds.contains(s.id) || isDeployingThis;
                          final deployLogs = _deployLogs[s.id];
                          final scrollCtrl = _deployScrollCtrls[s.id];

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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top Row: Icon, Server Info, Action Buttons
                                  Row(
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

                                      const SizedBox(width: 4),

                                      // Expand / Collapse Chevron Button
                                      IconButton(
                                        icon: Icon(
                                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                          size: 20,
                                          color: isExpanded ? AppColors.primaryLight : AppColors.textDim,
                                        ),
                                        tooltip: isExpanded ? 'Thu gọn thiết lập' : 'Mở rộng điều khiển Systemd & 1-Click Deploy',
                                        onPressed: () {
                                          setState(() {
                                            if (_expandedServerIds.contains(s.id)) {
                                              _expandedServerIds.remove(s.id);
                                            } else {
                                              _expandedServerIds.add(s.id);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              // Collapsible Content (Systemd Control & 1-Click Deploy)
                              if (isExpanded) ...[
                                // Divider
                                const SizedBox(height: 14),
                                const Divider(color: AppColors.borderDark, height: 1),
                                const SizedBox(height: 14),

                                // Block 1: Điều Khiển Dịch Vụ AI Agent (Systemd)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.borderDark),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.power_settings_new_rounded, size: 16, color: AppColors.primaryLight),
                                          SizedBox(width: 8),
                                          Text(
                                            'Điều Khiển Dịch Vụ AI Agent (Systemd)',
                                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 8,
                                        children: [
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF16A34A),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.play_arrow_rounded, size: 15),
                                            label: const Text('Khởi Động', style: TextStyle(fontSize: 11.5)),
                                            onPressed: () => _handleServiceAction(s, 'start'),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.warning,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.rotate_right_rounded, size: 15),
                                            label: const Text('Khởi Động Lại', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                            onPressed: () => _handleServiceAction(s, 'restart'),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.danger,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.stop_rounded, size: 15),
                                            label: const Text('Tắt', style: TextStyle(fontSize: 11.5)),
                                            onPressed: () => _handleServiceAction(s, 'stop'),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.cardBg,
                                              side: const BorderSide(color: AppColors.borderDark),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.info_outline_rounded, size: 15),
                                            label: const Text('Chi Tiết Status', style: TextStyle(fontSize: 11.5)),
                                            onPressed: () => _handleServiceAction(s, 'status'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Block 2: 1-Click Deploy & Tự Động Thiết Lập Trọn Gói
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.inputBg,
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
                                                    Icon(Icons.cloud_upload_rounded, size: 16, color: AppColors.accentCyan),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      '1-Click Deploy & Tự Động Thiết Lập Trọn Gói',
                                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  'Tự động cài đặt nhị phân, cấu hình Systemd service và kết nối Agent trên VPS',
                                                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            ),
                                            icon: isDeployingThis
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : const Icon(Icons.rocket_launch_rounded, size: 15),
                                            label: Text(
                                              isDeployingThis ? 'Đang thiết lập...' : 'Bắt đầu thiết lập',
                                              style: const TextStyle(fontSize: 11.5),
                                            ),
                                            onPressed: isDeployingThis ? null : () => _startDeploy(s),
                                          ),
                                        ],
                                      ),
                                      if (deployLogs != null && deployLogs.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          height: 140,
                                          padding: const EdgeInsets.all(10),
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
                                                  fontSize: 11,
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
