import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/server_model.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/server_provider.dart';

class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  @override
  Widget build(BuildContext context) {
    final metricsProvider = context.watch<MetricsProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final m = metricsProvider.metrics;
    final s = serverProvider.selectedServer;

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
                const Row(
                  children: [
                    Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 24),
                    SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quản Lý Máy Chủ & Dịch Vụ Systemd',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Triển khai code lên VPS/Server và giám sát tài nguyên thời gian thực',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (serverProvider.servers.isNotEmpty) ...[
                      PopupMenuButton<ServerModel>(
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
                          AppToast.success(this.context, 'Đang quản trị máy chủ: ${srv.name}');
                        },
                        itemBuilder: (ctx) => serverProvider.servers.map((srv) {
                          final isSel = srv.id == serverProvider.selectedServer?.id || srv.serverIp == serverProvider.selectedServer?.serverIp;
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
                                      Text(srv.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      Text('${srv.sshUser}@${srv.serverIp}:${srv.sshPort}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                                if (isSel) const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryLight),
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(
                                  serverProvider.selectedServer?.name ?? 'Chọn Server',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppColors.primaryLight),
                            ],
                          ),
                        ),
                      ),
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
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Four Server Status Cards Grid
                  Row(
                    children: [
                      Expanded(
                        child: () {
                          final st = m.serviceStatus.toLowerCase().trim();
                          String label = 'Chưa bật';
                          Color color = AppColors.warning;
                          if (st == 'active') {
                            label = 'Đang chạy';
                            color = AppColors.accent;
                          } else if (st == 'failed') {
                            label = 'Bị lỗi (Failed)';
                            color = AppColors.danger;
                          } else if (st == 'activating') {
                            label = 'Đang bật...';
                            color = AppColors.warning;
                          } else if (st == 'deactivating') {
                            label = 'Đang tắt...';
                            color = AppColors.textDim;
                          }
                          return _buildStatusCard(
                            title: 'Trạng thái Service',
                            icon: Icons.shield_rounded,
                            iconColor: color,
                            value: label,
                            valueColor: color,
                            subtitle: 'ai-agent.service',
                            hasDot: true,
                          );
                        }(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          title: 'Địa chỉ Máy Chủ',
                          icon: Icons.public_rounded,
                          iconColor: AppColors.accentCyan,
                          value: s?.serverIp ?? '127.0.0.1',
                          valueColor: AppColors.textWhite,
                          subtitle: 'Cổng API: ${s?.apiPort ?? 8000}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          title: 'Mô hình AI',
                          icon: Icons.memory_rounded,
                          iconColor: AppColors.primaryLight,
                          value: serverProvider.currentAiModel,
                          valueColor: AppColors.textWhite,
                          subtitle: 'Function Calling',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          title: 'Thời gian chạy (Uptime)',
                          icon: Icons.schedule_rounded,
                          iconColor: AppColors.accent,
                          value: m.uptime,
                          valueColor: AppColors.textWhite,
                          subtitle: m.os,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. Server Resource Metrics (CPU, RAM, DISK, NETWORK)
                  const Text(
                    'Tài Nguyên Máy Chủ Đám Mây',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // CPU Card
                      Expanded(
                        child: _buildMetricProgressCard(
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
                          footerRight: '✔ Siêu nhẹ',
                        ),
                      ),
                      const SizedBox(width: 12),

                      // RAM Card
                      Expanded(
                        child: _buildMetricProgressCard(
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Disk Card
                      Expanded(
                        child: _buildMetricProgressCard(
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
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Network Card
                      Expanded(
                        child: _buildMetricProgressCard(
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
                        ),
                      ),
                    ],
                  ),
                ],
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                  Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                ],
              ),
              Icon(icon, size: 16, color: iconColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
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
  }) {
    final clamped = percent.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
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
              Row(
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(labelLeft, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
              Text(labelRight, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textWhite)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped,
              backgroundColor: AppColors.inputBg,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(footerLeft, style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
              Text(footerRight, style: const TextStyle(fontSize: 10, color: AppColors.accent)),
            ],
          ),
        ],
      ),
    );
  }
}
