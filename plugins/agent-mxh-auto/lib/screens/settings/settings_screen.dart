import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/local_config_service.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/model_picker_dialog.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/server_model.dart';
import '../../providers/auth_provider.dart';
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
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://api.mitom.ai/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();
  String _aiEngineTab = 'cloud'; // 'cloud' | 'cli'

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
      final aiModel = cfg['ai_model']?.toString() ?? '';
      final activeEngine = cfg['active_agent_engine']?.toString() ?? '';
      bool isCli(String name) {
        final n = name.toLowerCase();
        return n.contains('cli') || n == 'agy' || n == 'claude' || n == 'gemini';
      }

      if (aiModel.isNotEmpty && !isCli(aiModel)) {
        _modelCtrl.text = aiModel;
      } else if (aiModel.contains('antigravity') || aiModel == 'agy') {
        _modelCtrl.text = 'glm-5.3';
      }
      if (activeEngine.isNotEmpty && isCli(activeEngine) && !activeEngine.contains('antigravity') && activeEngine != 'agy') {
        _aiEngineTab = 'cli';
      } else {
        _aiEngineTab = 'cloud';
      }
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
    } catch (_) {}
  }

  Future<void> _saveAISettings() async {
    final rawBaseUrl = _baseUrlCtrl.text.trim();
    if (rawBaseUrl.isNotEmpty && !LocalConfigService.isValidMitomProxyUrl(rawBaseUrl)) {
      AppToast.error(context, 'Chỉ chấp nhận Proxy Base URL thuộc domain *.mitom.ai (Ví dụ: https://api.mitom.ai/v1)');
      return;
    }

    try {
      final cfg = await _api.getConfig();
      cfg['ai_model'] = _modelCtrl.text.trim();
      cfg['proxy_base_url'] = rawBaseUrl;
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
    showDialog(
      context: context,
      builder: (ctx) {
        bool isTesting = false;
        bool isServiceActive = false;
        bool isOperatingService = false;
        bool isCheckingStatus = existing != null && existing.serverIp.isNotEmpty;
        bool hasCheckedService = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            // Tự động kiểm tra trạng thái service khi mở modal chỉnh sửa máy chủ
            if (isCheckingStatus && !hasCheckedService && existing != null && existing.serverIp.isNotEmpty) {
              Future.microtask(() async {
                try {
                  final active = await NativeSshService().getMultiIpSocks5Status(
                    host: existing.serverIp,
                    port: existing.sshPort,
                    user: existing.sshUser.isEmpty ? 'root' : existing.sshUser,
                    pass: existing.sshPass,
                  );
                  if (ctx.mounted) {
                    setModalState(() {
                      isServiceActive = active;
                      hasCheckedService = true;
                      isCheckingStatus = false;
                    });
                  }
                } catch (_) {
                  if (ctx.mounted) {
                    setModalState(() {
                      hasCheckedService = true;
                      isCheckingStatus = false;
                    });
                  }
                }
              });
            }

            return TaduDialog(
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
                  const SizedBox(height: 16),
                  // KHỐI QUẢN LÝ SERVICE MULTI-IP SOCKS5
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.sidebarBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.hub_rounded, size: 16, color: AppColors.primaryLight),
                            const SizedBox(width: 8),
                            const Text(
                              'Dịch Vụ Multi-IP SOCKS5 (Alias Routing)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            const Spacer(),
                            if (isCheckingStatus)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.primaryLight),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Đang kiểm tra...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (hasCheckedService)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isServiceActive
                                      ? AppColors.accent.withValues(alpha: 0.15)
                                      : AppColors.danger.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isServiceActive
                                        ? AppColors.accent.withValues(alpha: 0.4)
                                        : AppColors.danger.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  isServiceActive ? 'Đang chạy' : 'Đang tắt',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isServiceActive ? AppColors.accent : AppColors.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
                            const SizedBox(height: 6),
                            const Text(
                              'Kích hoạt service systemd "multi-ip-socks5.service" trên VPS để trình duyệt nhận đúng IP Alias khi mở.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Nút Bật / Tắt Service
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isServiceActive ? AppColors.danger : AppColors.primary,
                                    foregroundColor: isServiceActive ? Colors.white : const Color(0xFF070B14),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  icon: isOperatingService
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                        )
                                      : Icon(
                                          isServiceActive ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded,
                                          size: 15,
                                        ),
                                  label: Text(
                                    isOperatingService
                                        ? 'Đang xử lý...'
                                        : (isServiceActive ? 'Tắt Service (Disable)' : 'Bật Service (Enable)'),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: isOperatingService
                                      ? null
                                      : () async {
                                          final host = ipCtrl.text.trim();
                                          if (host.isEmpty) {
                                            AppToast.error(ctx, 'Vui lòng nhập IP máy chủ!');
                                            return;
                                          }
                                          setModalState(() {
                                            isOperatingService = true;
                                          });
                                          try {
                                            final ssh = NativeSshService();
                                            final targetEnable = !isServiceActive;
                                            final ok = await ssh.toggleMultiIpSocks5Service(
                                              host: host,
                                              port: int.tryParse(portCtrl.text.trim()) ?? 22,
                                              user: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                                              pass: passCtrl.text.trim(),
                                              enable: targetEnable,
                                            );
                                            if (ctx.mounted) {
                                              if (ok) {
                                                setModalState(() {
                                                  isServiceActive = targetEnable;
                                                  hasCheckedService = true;
                                                });
                                                AppToast.success(
                                                  ctx,
                                                  targetEnable
                                                      ? 'Đã bật multi-ip-socks5.service thành công!'
                                                      : 'Đã tắt multi-ip-socks5.service thành công!',
                                                );
                                              } else {
                                                AppToast.error(ctx, 'Thao tác service thất bại! Kiểm tra SSH.');
                                              }
                                            }
                                          } catch (e) {
                                            if (ctx.mounted) {
                                              AppToast.error(ctx, 'Lỗi: $e');
                                            }
                                          } finally {
                                            if (ctx.mounted) {
                                              setModalState(() {
                                                isOperatingService = false;
                                              });
                                            }
                                          }
                                        },
                                ),
                                const SizedBox(width: 8),
                                // Nút Kiểm tra trạng thái
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textWhite,
                                    side: const BorderSide(color: AppColors.borderDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
                                  label: const Text('Kiểm tra trạng thái', style: TextStyle(fontSize: 11.5)),
                                  onPressed: isOperatingService
                                      ? null
                                      : () async {
                                          final host = ipCtrl.text.trim();
                                          if (host.isEmpty) {
                                            AppToast.error(ctx, 'Vui lòng nhập IP máy chủ!');
                                            return;
                                          }
                                          setModalState(() {
                                            isOperatingService = true;
                                          });
                                          try {
                                            final ssh = NativeSshService();
                                            final active = await ssh.getMultiIpSocks5Status(
                                              host: host,
                                              port: int.tryParse(portCtrl.text.trim()) ?? 22,
                                              user: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                                              pass: passCtrl.text.trim(),
                                            );
                                            if (ctx.mounted) {
                                              setModalState(() {
                                                isServiceActive = active;
                                                hasCheckedService = true;
                                              });
                                              AppToast.info(
                                                ctx,
                                                active
                                                    ? 'Dịch vụ multi-ip-socks5 đang HOẠT ĐỘNG (Active)'
                                                    : 'Dịch vụ multi-ip-socks5 ĐANG TẮT (Inactive)',
                                              );
                                            }
                                          } catch (e) {
                                            if (ctx.mounted) {
                                              AppToast.error(ctx, 'Lỗi: $e');
                                            }
                                          } finally {
                                            if (ctx.mounted) {
                                              setModalState(() {
                                                isOperatingService = false;
                                              });
                                            }
                                          }
                                        },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              leadingActions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isTesting ? AppColors.primaryLight : AppColors.textWhite,
                    side: BorderSide(
                      color: isTesting ? AppColors.primary : AppColors.borderDark,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 16, color: AppColors.accent),
                  label: Text(
                    isTesting ? 'Đang test...' : 'Test kết nối',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: isTesting
                      ? null
                      : () async {
                          final host = ipCtrl.text.trim();
                          if (host.isEmpty) {
                            AppToast.error(ctx, 'Vui lòng nhập IP máy chủ để kiểm tra!');
                            return;
                          }
                          setModalState(() {
                            isTesting = true;
                          });

                          try {
                            final ssh = NativeSshService();
                            final ok = await ssh.testConnection(
                              host: host,
                              port: int.tryParse(portCtrl.text.trim()) ?? 22,
                              user: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                              pass: passCtrl.text.trim(),
                            );

                            if (ctx.mounted) {
                              if (ok) {
                                AppToast.success(ctx, 'Kết nối SSH thành công đến $host!');
                              } else {
                                AppToast.error(ctx, 'Kết nối thất bại! Kiểm tra IP, Port hoặc Mật khẩu.');
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              AppToast.error(ctx, 'Lỗi kết nối: $e');
                            }
                          } finally {
                            if (ctx.mounted) {
                              setModalState(() {
                                isTesting = false;
                              });
                            }
                          }
                        },
                ),
              ],
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
                      aiModel: existing?.aiModel ?? 'glm-5.3',
                      remoteWorkDir: existing?.remoteWorkDir ?? '/opt/ai_agent',
                      apiPort: existing?.apiPort ?? 8000,
                      isSelected: existing?.isSelected ?? false,
                    );
                    final srvProvider = context.read<ServerProvider>();
                    final rootCtx = context;
                    Navigator.pop(ctx);
                    final ok = await srvProvider.addOrUpdateServer(newServer);
                    if (rootCtx.mounted) {
                      if (ok) {
                        AppToast.success(rootCtx, 'Đã lưu thông tin máy chủ!');
                      } else {
                        AppToast.error(rootCtx, 'Lưu thông tin máy chủ thất bại');
                      }
                    }
                  },
                  child: const Text('Lưu Máy Chủ'),
                ),
              ],
            );
          },
        );
      },
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
    final auth = context.watch<AuthProvider>();

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
                        maxCrossAxisExtent: 460,
                        mainAxisExtent: 125,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: serverProvider.servers.length,
                      itemBuilder: (context, idx) {
                        final s = serverProvider.servers[idx];
                        final isSelected = serverProvider.selectedServer != null &&
                            (s.id == serverProvider.selectedServer!.id || s.serverIp == serverProvider.selectedServer!.serverIp);

                        return Container(
                          padding: const EdgeInsets.all(12),
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
                              // Hàng 1: Tên server & Badge Đang kết nối
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.dns_rounded, size: 18, color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            s.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 6),
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
                                ],
                              ),

                              // Hàng 2: SSH User & Main IP + Số lượng IP
                              Builder(
                                builder: (context) {
                                  final ips = serverProvider.getIpsForServer(s);
                                  final isLoading = serverProvider.isLoadingIps(s.id);
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${s.sshUser}@${s.serverIp}:${s.sshPort}',
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textMuted),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isLoading)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 4),
                                                child: SizedBox(
                                                  width: 8,
                                                  height: 8,
                                                  child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.primaryLight),
                                                ),
                                              ),
                                            Text(
                                              isLoading ? 'Đang quét...' : '${ips.length} IPs',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              // Hàng 3: Actions (Chọn server, Sửa, Xóa)
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
                        if (auth.isAdmin) ...[
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.sidebarBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      setState(() {
                                        _aiEngineTab = 'cloud';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _aiEngineTab == 'cloud'
                                            ? AppColors.primary.withValues(alpha: 0.25)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: _aiEngineTab == 'cloud'
                                              ? AppColors.primaryLight
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.cloud_queue_rounded,
                                            size: 15,
                                            color: _aiEngineTab == 'cloud'
                                                ? AppColors.primaryLight
                                                : AppColors.textDim,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Cloud API (OpenRouter / Mitom)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: _aiEngineTab == 'cloud'
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: _aiEngineTab == 'cloud'
                                                  ? AppColors.primaryLight
                                                  : AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      setState(() {
                                        _aiEngineTab = 'cli';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _aiEngineTab == 'cli'
                                            ? AppColors.accentCyan.withValues(alpha: 0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: _aiEngineTab == 'cli'
                                              ? AppColors.accentCyan
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.terminal_rounded,
                                            size: 15,
                                            color: _aiEngineTab == 'cli'
                                                ? AppColors.accentCyan
                                                : AppColors.textDim,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Local CLI Agent (Admin)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: _aiEngineTab == 'cli'
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: _aiEngineTab == 'cli'
                                                  ? AppColors.accentCyan
                                                  : AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // NỘI DUNG THEO TAB
                        if (_aiEngineTab == 'cloud') ...[
                          // KHỐI CLOUD API (Chỉ nằm trong tab Cloud API)
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('AI Model Name (Cloud)', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _modelCtrl,
                                      decoration: InputDecoration(
                                        hintText: 'glm-5.3 / gpt-4o / deepseek-chat',
                                        prefixIcon: const Icon(Icons.smart_toy_outlined, size: 18),
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.list_alt_rounded, size: 18, color: AppColors.primaryLight),
                                          tooltip: 'Mở bảng chọn Cloud Model',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => ModelPickerDialog(
                                                serverProvider: serverProvider,
                                                isAdmin: auth.isAdmin,
                                                initialTab: 0,
                                              ),
                                            ).then((_) {
                                              if (mounted) {
                                                setState(() {
                                                  _modelCtrl.text = serverProvider.cloudAiModel;
                                                });
                                              }
                                            });
                                          },
                                        ),
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
                                    const Text('Proxy Base URL', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _baseUrlCtrl,
                                      obscureText: true,
                                      decoration: const InputDecoration(hintText: 'https://api.mitom.ai/v1'),
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
                        ] else if (_aiEngineTab == 'cli' && auth.isAdmin) ...[
                          // KHỐI LOCAL CLI AGENT (Khi chọn tab này, khối Cloud API biến mất)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.sidebarBg,
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
                                        Icon(Icons.terminal_rounded, size: 16, color: AppColors.accentCyan),
                                        SizedBox(width: 8),
                                        Text(
                                          'Quản Lý & Chọn CLI Agent Đang Cài Trên Máy',
                                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                        ),
                                      ],
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.accentCyan,
                                        side: const BorderSide(color: AppColors.accentCyan),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      icon: const Icon(Icons.radar_rounded, size: 14),
                                      label: const Text('Quét lại CLI', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        serverProvider.scanCliAgents(forceRefresh: true);
                                        AppToast.info(context, 'Đang quét lại các CLI Agent...');
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Chế độ CLI Agent sẽ trực tiếp gọi công cụ nhị phân cài đặt trên hệ điều hành nội bộ (không sử dụng Proxy Base URL hay Proxy API Key).',
                                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    ActionChip(
                                      avatar: const Icon(Icons.code_rounded, size: 14, color: AppColors.accentCyan),
                                      label: Text(
                                        'claude-cli (${_modelCtrl.text == 'claude-cli' ? 'Đang chọn' : 'Chọn'})',
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                      backgroundColor: _modelCtrl.text == 'claude-cli' || _modelCtrl.text == 'claude'
                                          ? AppColors.accentCyan.withValues(alpha: 0.25)
                                          : AppColors.cardBg,
                                      side: BorderSide(
                                        color: _modelCtrl.text == 'claude-cli' || _modelCtrl.text == 'claude'
                                            ? AppColors.accentCyan
                                            : AppColors.borderDark,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _modelCtrl.text = 'claude-cli';
                                        });
                                        serverProvider.setActiveAgent('claude-cli');
                                        AppToast.success(context, 'Đã chọn Claude CLI Agent');
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Text('CLI Agent đang kích hoạt: ', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentCyan.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        _modelCtrl.text,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
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
