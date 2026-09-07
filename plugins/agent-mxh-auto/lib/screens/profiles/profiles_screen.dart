import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/socks5_proxy_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _openingIps = {};
  final Socks5ProxyService _socks5Service = Socks5ProxyService();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success(context, 'Đã sao chép $label: $text');
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final servers = serverProvider.servers;
    final selectedServer = serverProvider.selectedServer;

    // Tổng hợp tất cả IP Contact Cards từ server hiện tại hoặc tất cả servers
    final query = _searchCtrl.text.trim().toLowerCase();

    // Gom danh sách IP contact card
    final List<_ContactIpItem> allIpCards = [];

    for (final s in servers) {
      final ips = serverProvider.getIpsForServer(s);
      final isSelected = selectedServer != null && (selectedServer.id == s.id || selectedServer.serverIp == s.serverIp);

      for (int i = 0; i < ips.length; i++) {
        final ip = ips[i];
        final isMain = ip == s.serverIp;

        if (query.isNotEmpty) {
          final matchIp = ip.toLowerCase().contains(query);
          final matchServer = s.name.toLowerCase().contains(query);
          final matchUser = s.sshUser.toLowerCase().contains(query);
          if (!matchIp && !matchServer && !matchUser) {
            continue;
          }
        }

        allIpCards.add(
          _ContactIpItem(
            ip: ip,
            isMain: isMain,
            server: s,
            isCurrentServer: isSelected,
          ),
        );
      }
    }

    final isScanning = serverProvider.isLoading ||
        (selectedServer != null && serverProvider.isLoadingIps(selectedServer.id));

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. TOP TOOLBAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.contact_mail_rounded, color: AppColors.primaryLight, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Profiles / IP Contact Cards',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${allIpCards.length} Đầu IP khả dụng',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedServer != null
                            ? 'Danh sách các IP trỏ vào VPS máy chủ [${selectedServer.name}] (${selectedServer.serverIp})'
                            : 'Danh sách các đầu IP đang trỏ vào hệ thống máy chủ SSH',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),

                // Search Box
                SizedBox(
                  width: 240,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'Tìm theo IP, máy chủ...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textDim),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Button Quét lại IP
                ElevatedButton.icon(
                  onPressed: isScanning
                      ? null
                      : () {
                          if (selectedServer != null) {
                            serverProvider.fetchIpsForServer(selectedServer, force: true);
                            AppToast.info(context, 'Đang quét lại danh sách IP cho máy chủ...');
                          } else {
                            serverProvider.loadServers();
                          }
                        },
                  icon: isScanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070B14)),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    isScanning ? 'Đang quét...' : 'Quét lại IP',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF070B14),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. CONTACT CARDS GRID VIEW
          Expanded(
            child: allIpCards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.contact_mail_outlined, size: 54, color: AppColors.textDim.withValues(alpha: 0.5)),
                        const SizedBox(height: 14),
                        const Text(
                          'Chưa tìm thấy IP nào trỏ vào máy chủ',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hãy kiểm tra lại cấu hình kết nối SSH hoặc nhấn "Quét lại IP"',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Tính toán số cột responsive, giới hạn tối đa là 5 cột
                      int crossAxisCount = 3;
                      if (constraints.maxWidth < 650) {
                        crossAxisCount = 1;
                      } else if (constraints.maxWidth < 950) {
                        crossAxisCount = 2;
                      } else if (constraints.maxWidth < 1300) {
                        crossAxisCount = 3;
                      } else if (constraints.maxWidth < 1650) {
                        crossAxisCount = 4;
                      } else {
                        crossAxisCount = 5;
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 185,
                        ),
                        itemCount: allIpCards.length,
                        itemBuilder: (context, idx) {
                          final item = allIpCards[idx];
                          return _buildContactCard(item);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Khung danh thiếp Contact Card cho từng IP
  Widget _buildContactCard(_ContactIpItem item) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isCurrentServer
              ? AppColors.primary.withValues(alpha: 0.6)
              : AppColors.borderDark,
          width: item.isCurrentServer ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card (Tên máy chủ + Trạng thái)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: item.isCurrentServer
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.sidebarBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: const Border(bottom: BorderSide(color: AppColors.borderDark, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 16,
                  color: item.isCurrentServer ? AppColors.primaryLight : AppColors.textDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: item.isCurrentServer ? AppColors.primaryLight : AppColors.textWhite,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.isMain
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: item.isMain
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.borderDark,
                    ),
                  ),
                  child: Text(
                    item.isMain ? 'IP GỐC' : 'ALIAS IP',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: item.isMain ? AppColors.accent : AppColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body Card (IP Avatar + Contact Specs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar IP Badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: item.isMain ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderDark,
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.fingerprint_rounded,
                        color: item.isMain ? AppColors.accent : AppColors.primaryLight,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Thông số IP
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => _copyToClipboard(item.ip, 'IP'),
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.ip,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: AppColors.textWhite,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.copy_rounded, size: 13, color: AppColors.textDim),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Đang kết nối định tuyến',
                              style: TextStyle(fontSize: 10.5, color: AppColors.accent),
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

          // Footer Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
              border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isOpening = _openingIps.contains(item.ip);
                      return ElevatedButton.icon(
                        onPressed: isOpening
                            ? null
                            : () async {
                                setState(() {
                                  _openingIps.add(item.ip);
                                });
                                AppToast.info(context, 'Đang thiết lập SOCKS5 và mở trình duyệt cho ${item.ip}...');
                                try {
                                  await _socks5Service.launchBrowserWithSocks5(
                                    server: item.server,
                                    ip: item.ip,
                                  );
                                  if (context.mounted) {
                                    AppToast.success(context, 'Đã mở trình duyệt kết nối SOCKS5 qua ${item.ip}!');
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    AppToast.error(context, 'Lỗi mở trình duyệt: $e');
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _openingIps.remove(item.ip);
                                    });
                                  }
                                }
                              },
                        icon: isOpening
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                              )
                            : const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: Text(
                          isOpening ? 'Đang mở trình duyệt...' : 'Mở trình duyệt',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: const Color(0xFF070B14),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactIpItem {
  final String ip;
  final bool isMain;
  final ServerModel server;
  final bool isCurrentServer;

  _ContactIpItem({
    required this.ip,
    required this.isMain,
    required this.server,
    required this.isCurrentServer,
  });
}
