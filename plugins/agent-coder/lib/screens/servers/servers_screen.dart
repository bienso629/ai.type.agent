import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, String> _testStatus = {}; // serverId -> 'testing' | 'success' | 'failed'
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  Future<void> _switchToLocal(ServerProvider serverProvider) async {
    final localSrv = ServerModel(id: 'local', name: 'Local Machine', serverIp: '127.0.0.1');
    await serverProvider.selectServer(localSrv);
    if (!mounted) return;
    AppToast.success(context, 'Đã chuyển về chế độ Local Machine');
  }

  Future<void> _switchToServer(ServerProvider serverProvider, ServerModel server) async {
    await serverProvider.selectServer(server);
    if (!mounted) return;
    AppToast.success(context, 'Đã kích hoạt máy chủ "${server.name}" (${server.serverIp})');
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

  void _duplicateServer(ServerModel server) async {
    final dup = server.copyWith(
      id: 'srv_${DateTime.now().millisecondsSinceEpoch}',
      name: '${server.name} (Bản sao)',
      isSelected: false,
    );
    await context.read<ServerProvider>().addOrUpdateServer(dup);
    if (mounted) {
      _searchCtrl.clear();
      setState(() => _searchQuery = '');
      AppToast.success(context, 'Đã nhân bản máy chủ "${server.name}"!');
    }
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
                              : 'Đang ở chế độ Local Machine (thực thi trên máy cục bộ)',
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
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm nhanh máy chủ theo tên, IP, username...',
                        hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
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

          // 4. Main Server List
          Expanded(
            child: serverProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _searchQuery.isEmpty ? (servers.isEmpty ? 2 : servers.length + 1) : (servers.isEmpty ? 1 : servers.length),
                    itemBuilder: (context, index) {
                      // 1. Local Machine Card (when at top of search)
                      if (_searchQuery.isEmpty && index == 0) {
                        final isLocalActive = !isRemoteActive;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isLocalActive ? AppColors.cardBg : AppColors.cardBg.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isLocalActive ? AppColors.accent : AppColors.borderDark,
                              width: isLocalActive ? 1.5 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Tooltip(
                                  message: isLocalActive ? 'Đang kích hoạt' : 'Bật để chuyển sang chạy Local',
                                  child: Switch(
                                    value: isLocalActive,
                                    activeThumbColor: AppColors.accent,
                                    activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
                                    onChanged: (bool val) {
                                      if (val) _switchToLocal(serverProvider);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isLocalActive
                                        ? AppColors.accent.withValues(alpha: 0.15)
                                        : AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isLocalActive ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderDark,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.laptop_chromebook_rounded,
                                    size: 24,
                                    color: isLocalActive ? AppColors.accent : AppColors.textDim,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      if (!isLocalActive) _switchToLocal(serverProvider);
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Máy Cục Bộ (Local Machine)',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.textWhite),
                                            ),
                                            if (isLocalActive) ...[
                                              const SizedBox(width: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.accent,
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
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.terminal_rounded, size: 12, color: AppColors.accentCyan),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'localhost (127.0.0.1)',
                                                    style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppColors.textMuted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            const Text(
                                              'Thực thi câu lệnh trực tiếp trên máy của bạn',
                                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Empty state when servers is empty
                      if (servers.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: Column(
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
                        );
                      }

                      final s = _searchQuery.isEmpty ? servers[index - 1] : servers[index];
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
                                  // Switch Button to Toggle this Server Active Status
                                  Tooltip(
                                    message: isSelected ? 'Bấm để tắt (chuyển về Local)' : 'Bấm để kích hoạt máy chủ này',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Switch(
                                          value: isSelected,
                                          activeThumbColor: AppColors.primaryLight,
                                          activeTrackColor: AppColors.primary,
                                          onChanged: (bool val) {
                                            if (val) {
                                              _switchToServer(serverProvider, s);
                                            } else {
                                              _switchToLocal(serverProvider);
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  ),

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
                                      // Test Connection Button
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(
                                            color: test == 'success'
                                                ? AppColors.accent
                                                : test == 'failed'
                                                    ? AppColors.danger
                                                    : AppColors.borderDark,
                                          ),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        ),
                                        icon: test == 'testing'
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                              )
                                            : Icon(
                                                test == 'success'
                                                    ? Icons.check_circle_rounded
                                                    : test == 'failed'
                                                        ? Icons.error_outline_rounded
                                                        : Icons.wifi_protected_setup_rounded,
                                                size: 14,
                                                color: test == 'success'
                                                    ? AppColors.accent
                                                    : test == 'failed'
                                                        ? AppColors.danger
                                                        : AppColors.textMuted,
                                              ),
                                        label: Text(
                                          test == 'testing'
                                              ? 'Đang thử...'
                                              : test == 'success'
                                                  ? 'Online'
                                                  : test == 'failed'
                                                      ? 'Lỗi kết nối'
                                                      : 'Thử kết nối',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: test == 'success'
                                                ? AppColors.accent
                                                : test == 'failed'
                                                    ? AppColors.danger
                                                    : AppColors.textBody,
                                          ),
                                        ),
                                        onPressed: test == 'testing' ? null : () => _testServerConnection(s),
                                      ),
                                      const SizedBox(width: 8),

                                      // Duplicate Button
                                      IconButton(
                                        icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textDim),
                                        tooltip: 'Nhân bản cấu hình máy chủ này',
                                        onPressed: () => _duplicateServer(s),
                                      ),

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
