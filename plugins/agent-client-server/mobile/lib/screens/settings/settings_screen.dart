import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/server_model.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/server_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _modelCtrl = TextEditingController(text: 'glm-5.3');
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://openrouter.ai/api/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGlobalConfig();
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null) _modelCtrl.text = cfg['ai_model'].toString();
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
    } catch (_) {}
  }

  Future<void> _saveAISettings() async {
    try {
      final cfg = await _api.getConfig();
      cfg['ai_model'] = _modelCtrl.text.trim();
      cfg['proxy_base_url'] = _baseUrlCtrl.text.trim();
      cfg['proxy_api_key'] = _apiKeyCtrl.text.trim();
      final ok = await _api.saveConfig(cfg);
      if (mounted) {
        if (ok) {
          context.read<ServerProvider>().setGlobalAiModel(_modelCtrl.text.trim());
          AppToast.success(context, 'Đã lưu cấu hình AI thành công!');
        } else {
          AppToast.error(context, 'Lưu cấu hình AI thất bại!');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi: $e');
      }
    }
  }

  void _showAddEditServerDialog([ServerModel? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.serverIp ?? '');
    final portCtrl = TextEditingController(text: existing?.sshPort.toString() ?? '22');
    final userCtrl = TextEditingController(text: existing?.sshUser ?? 'root');
    final passCtrl = TextEditingController(text: existing?.sshPass ?? '');
    final modelCtrl = TextEditingController(text: existing?.aiModel ?? 'glm-5.3');
    final dirCtrl = TextEditingController(text: existing?.remoteWorkDir ?? '/opt/ai_agent');
    final apiPortCtrl = TextEditingController(text: existing?.apiPort.toString() ?? '8000');
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 540,
        maxWidth: 640,
        title: Row(
          children: [
            const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
            const SizedBox(width: 8),
            Text(existing != null ? 'Chỉnh Sửa Máy Chủ' : 'Thêm Máy Chủ Mới'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên Gợi Nhớ (Ví dụ: Web Production)',
                prefixIcon: Icon(Icons.label_outline_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(
                labelText: 'Địa Chỉ IP Máy Chủ',
                prefixIcon: Icon(Icons.public_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'SSH Port'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(labelText: 'SSH User (root)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật Khẩu SSH / Sudo',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(labelText: 'Model AI (glm-5.3)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: apiPortCtrl,
                    decoration: const InputDecoration(labelText: 'Cổng Agent (8000)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirCtrl,
              decoration: const InputDecoration(
                labelText: 'Thư Mục Làm Việc Từ Xa (/opt/ai_agent)',
                prefixIcon: Icon(Icons.folder_open_rounded, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = ipCtrl.text.trim();
              if (ip.isEmpty) {
                AppToast.error(context, 'Vui lòng nhập Địa chỉ IP máy chủ');
                return;
              }
              final newServer = ServerModel(
                id: existing?.id ?? 'srv_${DateTime.now().millisecondsSinceEpoch}',
                name: nameCtrl.text.trim().isEmpty ? ip : nameCtrl.text.trim(),
                serverIp: ip,
                sshPort: int.tryParse(portCtrl.text.trim()) ?? 22,
                sshUser: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                sshPass: passCtrl.text.trim(),
                aiModel: modelCtrl.text.trim().isEmpty ? 'glm-5.3' : modelCtrl.text.trim(),
                remoteWorkDir: dirCtrl.text.trim().isEmpty ? '/opt/ai_agent' : dirCtrl.text.trim(),
                apiPort: int.tryParse(apiPortCtrl.text.trim()) ?? 8000,
                isSelected: existing?.isSelected ?? false,
              );
              Navigator.pop(ctx);
              final ok = await context.read<ServerProvider>().addOrUpdateServer(newServer);
              if (mounted) {
                if (ok) {
                  AppToast.success(context, 'Đã lưu thông tin máy chủ!');
                } else {
                  AppToast.error(context, 'Lưu thông tin máy chủ thất bại');
                }
              }
            },
            child: const Text('Lưu Máy Chủ'),
          ),
        ],
      ),
    );
  }

  void _showDeleteServerConfirmDialog(ServerModel server) {
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
        content: Text(
          'Bạn có chắc chắn muốn xóa máy chủ "${server.name}" (${server.serverIp}:${server.sshPort}) khỏi danh sách kết nối không?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await context.read<ServerProvider>().deleteServer(server.id);
              if (mounted) {
                if (ok) {
                  AppToast.info(context, 'Đã xóa máy chủ "${server.name}"');
                } else {
                  AppToast.error(context, 'Không thể xóa máy chủ');
                }
              }
            },
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final gateway = context.watch<GatewayProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Topbar Header (Height 66px)
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
                    const Icon(Icons.tune_rounded, color: AppColors.primaryLight, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quản Lý Đa Máy Chủ & Cấu Hình AI',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Thêm, sửa, chuyển đổi máy chủ SSH Remote và cấu hình AI Model (${serverProvider.currentAiModel})',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Thêm Máy Chủ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _showAddEditServerDialog(),
                ),
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GROUP 1: MULTI-SERVER MANAGEMENT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lan_rounded, size: 16, color: AppColors.accentCyan),
                          const SizedBox(width: 8),
                          const Text(
                            '1. Danh Sách Máy Chủ Remote (Multi-Server)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${serverProvider.servers.length} máy chủ',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Servers Grid Cards
                  if (serverProvider.servers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: const Text('Chưa có máy chủ nào được thêm', style: TextStyle(color: AppColors.textMuted)),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 420,
                        mainAxisExtent: 140,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: serverProvider.servers.length,
                      itemBuilder: (context, idx) {
                        final s = serverProvider.servers[idx];
                        final isSelected = serverProvider.selectedServer != null &&
                            (s.id == serverProvider.selectedServer!.id || s.serverIp == serverProvider.selectedServer!.serverIp);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.cardBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.borderDark,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.dns_rounded, size: 18, color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
                                      const SizedBox(width: 8),
                                      Text(
                                        s.name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ĐANG KẾT NỐI',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                '${s.sshUser}@${s.serverIp}:${s.sshPort}',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textMuted),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (!isSelected)
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: () => serverProvider.selectServer(s),
                                      child: const Text('Chọn Server', style: TextStyle(fontSize: 11)),
                                    )
                                  else
                                    const Text('Mặc định', style: TextStyle(fontSize: 11, color: AppColors.accent)),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16),
                                        onPressed: () => _showAddEditServerDialog(s),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                                        tooltip: 'Xóa máy chủ',
                                        onPressed: () => _showDeleteServerConfirmDialog(s),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),

                  // GROUP 2: AI MODEL & PROXY CONFIGURATION
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.memory_rounded, size: 18, color: AppColors.primaryLight),
                                SizedBox(width: 8),
                                Text(
                                  '2. Cấu Hình AI Model & Proxy API (Toàn Cục)',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cardBg,
                                side: const BorderSide(color: AppColors.primary),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryLight),
                              label: const Text('Lưu Cấu Hình AI', style: TextStyle(color: AppColors.primaryLight)),
                              onPressed: _saveAISettings,
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('AI Model Name', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _modelCtrl,
                                    decoration: const InputDecoration(hintText: 'glm-5.3'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Proxy Base URL', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _baseUrlCtrl,
                                    obscureText: true,
                                    decoration: const InputDecoration(hintText: 'https://openrouter.ai/api/v1'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Proxy API Key', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _apiKeyCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(hintText: 'sk-or-v1-... (OpenRouter / Zhipu / OpenAI API Key)'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 3: SECURITY & STORAGE INFO
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield_rounded, size: 18, color: AppColors.accent),
                            SizedBox(width: 8),
                            Text(
                              '3. Bảo Mật & Thông Tin Hệ Thống',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoBox('Chuẩn Mã Hoá', 'AES-256 GCM + HMAC-SHA256 lưu trữ an toàn trong config.json'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Trạng Thái Gateway', gateway.isConnected ? 'Kết nối OK (${gateway.pingMs} ms)' : 'Chưa kết nối'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Giao Thức Terminal', 'WebSocket xterm-256color PTY Live Stream'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
