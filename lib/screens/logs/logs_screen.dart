import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/server_model.dart';
import '../../providers/logs_provider.dart';
import '../../providers/server_provider.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logsProvider = context.watch<LogsProvider>();
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
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        logsProvider.isLocal ? Icons.description_rounded : Icons.dns_rounded,
                        color: logsProvider.isLocal ? AppColors.accent : AppColors.primaryLight,
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
                                Text(
                                  logsProvider.isLocal
                                      ? 'Nhật Ký Local Machine'
                                      : 'Nhật Ký Máy Chủ: ${logsProvider.selectedServer?.name ?? 'Server'}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (logsProvider.isLocal ? AppColors.accent : AppColors.primaryLight).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: logsProvider.isLocal ? AppColors.accent : AppColors.primaryLight),
                                  ),
                                  child: Text(
                                    logsProvider.isLocal ? 'LOCAL' : '${logsProvider.selectedServer?.serverIp}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: logsProvider.isLocal ? AppColors.accent : AppColors.primaryLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              logsProvider.isLocal
                                  ? 'Nhật ký thực thi hệ thống trên máy tính cục bộ'
                                  : 'Nhật ký máy chủ từ xa kết nối qua SSH trực tiếp',
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
                    // Environment Selector Dropdown
                    PopupMenuButton<ServerModel?>(
                      tooltip: 'Chọn nguồn xem Logs',
                      offset: const Offset(0, 42),
                      color: AppColors.cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                      onSelected: (srv) {
                        logsProvider.setServer(srv);
                      },
                      itemBuilder: (ctx) {
                        final items = <PopupMenuEntry<ServerModel?>>[];
                        // 1. Local
                        items.add(
                          PopupMenuItem<ServerModel?>(
                            value: null,
                            child: Row(
                              children: [
                                const Icon(Icons.laptop_chromebook_rounded, size: 15, color: AppColors.accent),
                                const SizedBox(width: 8),
                                const Text('Local Machine (Cục bộ)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                if (logsProvider.isLocal) ...[
                                  const Spacer(),
                                  const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                                ],
                              ],
                            ),
                          ),
                        );
                        // 2. Servers
                        if (serverProvider.servers.isNotEmpty) {
                          items.add(const PopupMenuDivider());
                          for (final s in serverProvider.servers) {
                            final isSel = !logsProvider.isLocal && logsProvider.selectedServer?.id == s.id;
                            items.add(
                              PopupMenuItem<ServerModel?>(
                                value: s,
                                child: Row(
                                  children: [
                                    const Icon(Icons.dns_rounded, size: 15, color: AppColors.primaryLight),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                          Text(s.serverIp, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                    if (isSel) const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryLight),
                                  ],
                                ),
                              ),
                            );
                          }
                        }
                        return items;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              logsProvider.isLocal ? Icons.laptop_chromebook_rounded : Icons.dns_rounded,
                              size: 13,
                              color: logsProvider.isLocal ? AppColors.accent : AppColors.primaryLight,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              logsProvider.isLocal ? 'Local Machine' : (logsProvider.selectedServer?.name ?? 'Server'),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down_rounded, size: 14, color: AppColors.textDim),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Refresh Interval Dropdown
                    PopupMenuButton<int>(
                      tooltip: 'Chu kỳ tự động làm mới',
                      offset: const Offset(0, 42),
                      color: AppColors.cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                      onSelected: (sec) => logsProvider.setRefreshInterval(sec),
                      itemBuilder: (ctx) => [
                        PopupMenuItem<int>(
                          value: 0,
                          child: Row(
                            children: [
                              const Text('Tắt (Làm mới thủ công)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              if (logsProvider.refreshInterval == 0) ...[
                                const Spacer(),
                                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuItem<int>(
                          value: 3,
                          child: Row(
                            children: [
                              const Text('Tự động mỗi 3 giây', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              if (logsProvider.refreshInterval == 3) ...[
                                const Spacer(),
                                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuItem<int>(
                          value: 5,
                          child: Row(
                            children: [
                              const Text('Tự động mỗi 5 giây', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              if (logsProvider.refreshInterval == 5) ...[
                                const Spacer(),
                                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuItem<int>(
                          value: 10,
                          child: Row(
                            children: [
                              const Text('Tự động mỗi 10 giây', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              if (logsProvider.refreshInterval == 10) ...[
                                const Spacer(),
                                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuItem<int>(
                          value: 30,
                          child: Row(
                            children: [
                              const Text('Tự động mỗi 30 giây', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              if (logsProvider.refreshInterval == 30) ...[
                                const Spacer(),
                                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: logsProvider.isAutoRefresh ? AppColors.accent : AppColors.borderDark),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 13,
                              color: logsProvider.isAutoRefresh ? AppColors.accent : AppColors.textDim,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              logsProvider.refreshInterval == 0 ? 'Thủ công' : '${logsProvider.refreshInterval}s',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: logsProvider.isAutoRefresh ? FontWeight.bold : FontWeight.normal,
                                color: logsProvider.isAutoRefresh ? AppColors.accent : AppColors.textBody,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_drop_down_rounded, size: 14, color: AppColors.textDim),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Manual Refresh Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBg,
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: logsProvider.isLoading
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textWhite),
                      label: const Text('Làm mới', style: TextStyle(fontSize: 11.5, color: AppColors.textWhite)),
                      onPressed: logsProvider.isLoading ? null : () => logsProvider.fetchLogs(),
                    ),
                    const SizedBox(width: 6),

                    // Copy Button
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textDim),
                      tooltip: 'Sao chép toàn bộ nhật ký',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: logsProvider.logs));
                        AppToast.success(context, 'Đã sao chép nhật ký vào Clipboard');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Filter Bar (Categories when viewing Server Logs)
          if (!logsProvider.isLocal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.sidebarBg,
                border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
              ),
              child: Row(
                children: [
                  const Text('Loại Log: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('🤖 AI Agent Service', 'agent', logsProvider),
                          _buildFilterChip('📄 Syslog (/var/log)', 'syslog', logsProvider),
                          _buildFilterChip('🔒 SSH / Auth', 'auth', logsProvider),
                          _buildFilterChip('🌐 Nginx / Web', 'nginx', logsProvider),
                          _buildFilterChip('🚀 Dmesg / Kernel', 'dmesg', logsProvider),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Main Logs Display View
          Expanded(
            child: Container(
              width: double.infinity,
              color: AppColors.terminalBg,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SelectableText(
                  logsProvider.logs,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AppColors.textBody,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String type, LogsProvider provider) {
    final isSelected = provider.logType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isSelected ? AppColors.primary : AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => provider.setLogType(type),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isSelected ? AppColors.primary : AppColors.borderDark),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
