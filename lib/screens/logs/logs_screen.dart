import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/logs_provider.dart';

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
                    Icon(Icons.description_rounded, color: AppColors.warning, size: 24),
                    SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nhật Ký Hệ Thống Cục Bộ (System Logs)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Nhật ký thực thi realtime trên máy tính cục bộ',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Row(
                      children: [
                        Switch(
                          value: logsProvider.autoRefresh,
                          thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.white;
                            }
                            return const Color(0xFF94A3B8);
                          }),
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                          onChanged: (val) => logsProvider.setAutoRefresh(val),
                        ),
                        const SizedBox(width: 8),
                        const Text('Tự động làm mới (3s)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBg,
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: logsProvider.isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Làm mới', style: TextStyle(fontSize: 12)),
                      onPressed: () => logsProvider.fetchLogs(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Logs Display View (100% Full Width & Height, No Outer Borders)
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
}
