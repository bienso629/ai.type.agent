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
  final Set<String> _closingIps = {};
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
                          mainAxisExtent: 190,
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
    final socks5 = context.watch<Socks5ProxyService>();
    final isBrowserRunning = socks5.isBrowserRunningForIp(item.ip);
    final isAlias = !item.isMain;

    // Phối màu đặc sắc theo yêu cầu:
    // Nếu là ALIAS IP và ĐANG MỞ TRÌNH DUYỆT -> Màu Xanh Ngọc Cyber (Emerald/Cyan), viền sáng, huy hiệu Đang duyệt web
    // Nếu là IP GỐC và ĐANG MỞ TRÌNH DUYỆT -> Màu Vàng Hổ Phách Amber
    // Nếu chưa mở trình duyệt -> Màu Slate tối mặc định
    final Color cardBorderColor;
    final Color cardBgColor;
    final Color badgeBgColor;
    final Color badgeTextColor;
    final String statusText;
    final Color statusDotColor;

    if (isBrowserRunning) {
      if (isAlias) {
        cardBorderColor = AppColors.accent; // Xanh ngọc nổi bật cho Alias đang mở
        cardBgColor = const Color(0xFF091E1A);
        badgeBgColor = AppColors.accent.withValues(alpha: 0.2);
        badgeTextColor = AppColors.accent;
        statusText = 'Trình duyệt đang mở (Active)';
        statusDotColor = AppColors.accent;
      } else {
        cardBorderColor = AppColors.primaryLight;
        cardBgColor = const Color(0xFF1C1908);
        badgeBgColor = AppColors.primary.withValues(alpha: 0.2);
        badgeTextColor = AppColors.primaryLight;
        statusText = 'Trình duyệt đang mở (Active)';
        statusDotColor = AppColors.primaryLight;
      }
    } else {
      cardBorderColor = item.isCurrentServer ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderDark;
      cardBgColor = AppColors.cardBg;
      badgeBgColor = item.isMain ? AppColors.accent.withValues(alpha: 0.12) : AppColors.sidebarBg;
      badgeTextColor = item.isMain ? AppColors.accent : AppColors.textDim;
      statusText = isAlias ? 'Sẵn sàng kết nối Alias' : 'Sẵn sàng kết nối';
      statusDotColor = item.isMain ? AppColors.accent : AppColors.textDim;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cardBorderColor,
          width: isBrowserRunning ? 1.8 : (item.isCurrentServer ? 1.3 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isBrowserRunning
                ? (isAlias ? AppColors.accent.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.2))
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: isBrowserRunning ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card (Tên máy chủ + Trạng thái Loại IP)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isBrowserRunning
                  ? (isAlias ? const Color(0xFF0B2923) : const Color(0xFF26200A))
                  : (item.isCurrentServer ? AppColors.primary.withValues(alpha: 0.12) : AppColors.sidebarBg),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: isBrowserRunning ? cardBorderColor.withValues(alpha: 0.4) : AppColors.borderDark, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 16,
                  color: isBrowserRunning
                      ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                      : (item.isCurrentServer ? AppColors.primaryLight : AppColors.textDim),
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
                      color: isBrowserRunning
                          ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                          : (item.isCurrentServer ? AppColors.primaryLight : AppColors.textWhite),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isBrowserRunning ? cardBorderColor.withValues(alpha: 0.5) : AppColors.borderDark,
                    ),
                  ),
                  child: Text(
                    item.isMain ? 'IP GỐC' : 'ALIAS IP',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: badgeTextColor,
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
                      color: isBrowserRunning
                          ? (isAlias ? AppColors.accent.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15))
                          : AppColors.inputBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isBrowserRunning
                            ? cardBorderColor
                            : (item.isMain ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderDark),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        isBrowserRunning ? Icons.language_rounded : Icons.fingerprint_rounded,
                        color: isBrowserRunning
                            ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                            : (item.isMain ? AppColors.accent : AppColors.primaryLight),
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
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: isBrowserRunning
                                      ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                                      : AppColors.textWhite,
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
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: statusDotColor,
                                shape: BoxShape.circle,
                                boxShadow: isBrowserRunning
                                    ? [
                                        BoxShadow(
                                          color: statusDotColor.withValues(alpha: 0.8),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isBrowserRunning ? FontWeight.w600 : FontWeight.normal,
                                  color: statusDotColor,
                                ),
                              ),
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
            decoration: BoxDecoration(
              color: isBrowserRunning
                  ? (isAlias ? const Color(0xFF09211C) : const Color(0xFF211D09))
                  : AppColors.sidebarBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
              border: Border(top: BorderSide(color: isBrowserRunning ? cardBorderColor.withValues(alpha: 0.3) : AppColors.borderDark, width: 0.8)),
            ),
            child: () {
              final isOpening = _openingIps.contains(item.ip);
              final isClosing = _closingIps.contains(item.ip);
              final isBusy = isOpening || isClosing;

              if (isBrowserRunning) {
                // Đang mở trình duyệt -> Duy nhất 1 nút "Đóng trình duyệt" (màu đỏ)
                return ElevatedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          setState(() {
                            _closingIps.add(item.ip);
                          });
                          try {
                            await _socks5Service.stopSession(item.ip);
                            if (mounted) {
                              AppToast.info(context, 'Đã đóng trình duyệt cho ${item.ip}');
                            }
                          } catch (e) {
                            if (mounted) {
                              AppToast.error(context, 'Lỗi khi đóng trình duyệt: $e');
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _closingIps.remove(item.ip);
                              });
                            }
                          }
                        },
                  icon: isClosing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                        )
                      : const Icon(Icons.close_rounded, size: 16),
                  label: Text(
                    isClosing ? 'Đang đóng trình duyệt...' : 'Đóng trình duyệt',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              }

              // Chưa mở trình duyệt -> Duy nhất 1 nút "Mở trình duyệt"
              return ElevatedButton.icon(
                onPressed: isBusy
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
                          if (mounted) {
                            AppToast.success(context, 'Đã mở trình duyệt qua ${item.ip}');
                          }
                        } catch (e) {
                          if (mounted) {
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
            }(),
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
