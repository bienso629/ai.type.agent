import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/server_model.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/server_provider.dart';

class ServerSetupScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;

  const ServerSetupScreen({super.key, this.onOpenDrawer});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  Widget _buildDrawerButton() {
    return IconButton(
      tooltip: 'Mở menu điều hướng',
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(34, 34),
        fixedSize: const Size(34, 34),
        maximumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      onPressed: widget.onOpenDrawer,
      icon: const Icon(Icons.menu_rounded, size: 20, color: AppColors.textWhite),
    );
  }

  Widget _buildServerSelector(
    ServerProvider serverProvider,
    MetricsProvider metricsProvider, {
    required bool fullWidth,
  }) {
    final selected = serverProvider.selectedServer;
    final labelText = selected == null
        ? 'Chọn Server'
        : (fullWidth && selected.serverIp.isNotEmpty
            ? '${selected.name} (${selected.serverIp})'
            : selected.name);

    return PopupMenuButton<ServerModel>(
      tooltip: 'Chọn máy chủ VPS',
      offset: const Offset(0, 40),
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      onSelected: (srv) async {
        await serverProvider.selectServer(srv);
        metricsProvider.fetchMetrics();
        if (!mounted) return;
        AppToast.success(context, 'Đang quản trị máy chủ: ${srv.name}');
      },
      itemBuilder: (ctx) => serverProvider.servers.map((srv) {
        final isSel = srv.id == selected?.id || srv.serverIp == selected?.serverIp;
        return PopupMenuItem<ServerModel>(
          value: srv,
          child: Row(
            children: [
              const Icon(Icons.dns_rounded, size: 16, color: AppColors.primaryLight),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      srv.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                    Text(
                      '${srv.sshUser}@${srv.serverIp}:${srv.sshPort}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (isSel) const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryLight),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 34,
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
            const SizedBox(width: 6),
            if (fullWidth)
              Expanded(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLight,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppColors.primaryLight),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ServerProvider serverProvider,
    MetricsProvider metricsProvider,
    bool isCompactMobile,
  ) {
    if (isCompactMobile) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: AppColors.bgDark,
          border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (widget.onOpenDrawer != null) ...[
                  _buildDrawerButton(),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Thiết lập & Giám sát',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textWhite,
                      backgroundColor: AppColors.cardBg,
                      side: const BorderSide(color: AppColors.borderDark),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Cập nhật', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => metricsProvider.fetchMetrics(),
                  ),
                ),
              ],
            ),
            if (serverProvider.servers.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildServerSelector(serverProvider, metricsProvider, fullWidth: true),
            ],
          ],
        ),
      );
    }

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
                if (widget.onOpenDrawer != null) ...[
                  _buildDrawerButton(),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thiết Lập & Giám Sát Tài Nguyên Máy Chủ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                      ),
                      Text(
                        'Triển khai code lên VPS/Server và giám sát tài nguyên thời gian thực',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              if (serverProvider.servers.isNotEmpty) ...[
                _buildServerSelector(serverProvider, metricsProvider, fullWidth: false),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cardBg,
                  side: const BorderSide(color: AppColors.borderDark),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Cập nhật', style: TextStyle(fontSize: 12)),
                onPressed: () => metricsProvider.fetchMetrics(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metricsProvider = context.watch<MetricsProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final m = metricsProvider.metrics;
    final s = serverProvider.selectedServer;
    final isCompactMobile = MediaQuery.sizeOf(context).width < 700;

    final st = m.serviceStatus.toLowerCase().trim();
    String serviceLabel = 'Chưa bật';
    Color serviceColor = AppColors.warning;
    if (st == 'active') {
      serviceLabel = 'Đang chạy';
      serviceColor = AppColors.accent;
    } else if (st == 'failed') {
      serviceLabel = 'Bị lỗi (Failed)';
      serviceColor = AppColors.danger;
    } else if (st == 'activating') {
      serviceLabel = 'Đang bật...';
      serviceColor = AppColors.warning;
    } else if (st == 'deactivating') {
      serviceLabel = 'Đang tắt...';
      serviceColor = AppColors.textDim;
    }

    final statusCard = _buildStatusCard(
      title: 'Trạng thái Service',
      icon: Icons.shield_rounded,
      iconColor: serviceColor,
      value: serviceLabel,
      valueColor: serviceColor,
      subtitle: 'ai-agent.service',
      hasDot: true,
      compact: isCompactMobile,
    );
    final hostCard = _buildStatusCard(
      title: 'Địa chỉ Máy Chủ',
      icon: Icons.dns_rounded,
      iconColor: AppColors.accentCyan,
      value: s?.serverIp ?? '127.0.0.1',
      valueColor: AppColors.textWhite,
      subtitle: 'Cổng API: ${s?.apiPort ?? 8000}',
      compact: isCompactMobile,
    );
    final modelCard = _buildStatusCard(
      title: 'Mô hình AI',
      icon: Icons.memory_rounded,
      iconColor: AppColors.primaryLight,
      value: serverProvider.currentAiModel,
      valueColor: AppColors.textWhite,
      subtitle: 'Function Calling',
      compact: isCompactMobile,
    );
    final uptimeCard = _buildStatusCard(
      title: isCompactMobile ? 'Thời gian chạy' : 'Thời gian chạy (Uptime)',
      icon: Icons.schedule_rounded,
      iconColor: AppColors.accent,
      value: m.uptime,
      valueColor: AppColors.textWhite,
      subtitle: m.os,
      compact: isCompactMobile,
    );

    final cpuCard = _buildMetricProgressCard(
      title: 'Vi xử lý (CPU Usage)',
      icon: Icons.memory_rounded,
      iconColor: AppColors.warning,
      badgeText: '${m.cpuPercent.toStringAsFixed(1)}%',
      badgeColor: AppColors.warning,
      labelLeft: 'Tải hệ thống (1m, 5m, 15m)',
      labelRight: 'Load: ${m.loadAvg}',
      percent: m.cpuPercent / 100,
      progressColor: AppColors.warning,
      footerLeft: 'Chế độ: On-Demand',
      footerRight: 'Siêu nhẹ',
      compact: isCompactMobile,
    );
    final ramCard = _buildMetricProgressCard(
      title: 'Bộ nhớ RAM (Memory)',
      icon: Icons.storage_rounded,
      iconColor: AppColors.accent,
      badgeText: '${m.ramPercent.toStringAsFixed(1)}%',
      badgeColor: AppColors.accent,
      labelLeft: 'Đã dùng / Tổng RAM',
      labelRight: '${m.ramUsed} / ${m.ramTotal}',
      percent: m.ramPercent / 100,
      progressColor: AppColors.accent,
      footerLeft: 'Khả dụng: ${m.ramAvail}',
      footerRight: 'Bộ nhớ đệm: OK',
      compact: isCompactMobile,
    );
    final diskCard = _buildMetricProgressCard(
      title: 'Ổ đĩa hệ thống (Disk)',
      icon: Icons.disc_full_rounded,
      iconColor: AppColors.primaryLight,
      badgeText: '${m.diskPercent}%',
      badgeColor: AppColors.primaryLight,
      labelLeft: 'Đã dùng / Tổng dung lượng',
      labelRight: '${m.diskUsed} / ${m.diskTotal}',
      percent: m.diskPercent / 100,
      progressColor: AppColors.primaryLight,
      footerLeft: 'Còn trống: ${m.diskAvail}',
      footerRight: 'SSD NVMe',
      compact: isCompactMobile,
    );
    final networkCard = _buildMetricProgressCard(
      title: 'Băng thông mạng (Network I/O)',
      icon: Icons.speed_rounded,
      iconColor: AppColors.accentCyan,
      badgeText: m.netRxSpeed,
      badgeColor: AppColors.accentCyan,
      labelLeft: 'Tải về (Rx) / Tải lên (Tx)',
      labelRight: '${m.netRxSpeed} | ${m.netTxSpeed}',
      percent: (m.netPercent / 100).clamp(0.0, 1.0),
      progressColor: AppColors.accentCyan,
      footerLeft: 'Tổng: ${m.netRxTotal}',
      footerRight: 'Cổng 1Gbps',
      compact: isCompactMobile,
    );

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          _buildHeader(context, serverProvider, metricsProvider, isCompactMobile),

          // Scrollable Content
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryLight,
              backgroundColor: AppColors.cardBg,
              onRefresh: () => metricsProvider.fetchMetrics(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isCompactMobile ? 12 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Server Status Cards (2x2 on mobile, 4-column on desktop)
                    if (isCompactMobile) ...[
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: statusCard),
                            const SizedBox(width: 10),
                            Expanded(child: hostCard),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: modelCard),
                            const SizedBox(width: 10),
                            Expanded(child: uptimeCard),
                          ],
                        ),
                      ),
                    ] else
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: statusCard),
                            const SizedBox(width: 12),
                            Expanded(child: hostCard),
                            const SizedBox(width: 12),
                            Expanded(child: modelCard),
                            const SizedBox(width: 12),
                            Expanded(child: uptimeCard),
                          ],
                        ),
                      ),
                    SizedBox(height: isCompactMobile ? 14 : 16),

                    // 2. Server Resource Metrics (1-column stack on mobile, 2x2 grid on desktop)
                    const Text(
                      'Tài Nguyên Máy Chủ Đám Mây',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                    SizedBox(height: isCompactMobile ? 10 : 12),
                    if (isCompactMobile) ...[
                      cpuCard,
                      const SizedBox(height: 10),
                      ramCard,
                      const SizedBox(height: 10),
                      diskCard,
                      const SizedBox(height: 10),
                      networkCard,
                    ] else ...[
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cpuCard),
                            const SizedBox(width: 12),
                            Expanded(child: ramCard),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: diskCard),
                            const SizedBox(width: 12),
                            Expanded(child: networkCard),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    required Color valueColor,
    required String subtitle,
    bool hasDot = false,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (hasDot) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: compact ? 15 : 16, color: iconColor),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 14.5 : 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricProgressCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required Color badgeColor,
    required String labelLeft,
    required String labelRight,
    required double percent,
    required Color progressColor,
    required String footerLeft,
    required String footerRight,
    bool compact = false,
  }) {
    final clamped = percent.clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  labelLeft,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  labelRight,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textWhite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped,
              backgroundColor: AppColors.inputBg,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: compact ? 7 : 8,
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  footerLeft,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                footerRight,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
