import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/server_provider.dart';
import 'chat/chat_screen.dart';
import 'docs/docs_screen.dart';
import 'settings/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().loadServers();
      context.read<ChatProvider>().reloadForUser();
    });
  }

  final List<Widget> _screens = const [
    ChatScreen(),
    DocsScreen(),
    SettingsScreen(),
  ];

  final List<Map<String, dynamic>> _tabs = [
    {
      'title': 'Trợ lý AI',
      'subtitle': 'Trò chuyện và hỗ trợ kỹ thuật thông minh',
      'icon': Icons.chat_bubble_outline_rounded,
    },
    {
      'title': 'Tài liệu',
      'subtitle': 'Hướng dẫn sử dụng và tài liệu kỹ thuật',
      'icon': Icons.menu_book_rounded,
    },
    {
      'title': 'Cài đặt',
      'subtitle': 'Cấu hình AI Model, Proxy API và tài khoản',
      'icon': Icons.settings_outlined,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        if (isDesktop) {
          return _buildDesktopLayout();
        } else {
          return _buildMobileLayout();
        }
      },
    );
  }

  // =========================================================================
  // DESKTOP LAYOUT (EXACT 1:1 REPLICATION OF templates/index.html)
  // =========================================================================
  Widget _buildDesktopLayout() {
    final metricsProvider = context.watch<MetricsProvider>();
    final auth = context.watch<AuthProvider>();
    final m = metricsProvider.metrics;
    final isAgentActive = m.serviceStatus == 'active';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Row(
        children: [
          // 1. LEFT SIDEBAR (Width 250px, #0d121f)
          Container(
            width: 250,
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(right: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1.1 Brand Header (Height 66px)
                Container(
                  height: 66,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/logo.jpg',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                            ),
                            child: const Icon(Icons.cloud_sync_rounded, color: AppColors.primaryLight, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Agent',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textWhite,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              'AI AGENT CHATBOT',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isAgentActive ? AppColors.accent : AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 1.3 Nav Buttons (Exact 5 items from templates/index.html)
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: _tabs.length,
                    itemBuilder: (context, idx) {
                      final item = _tabs[idx];
                      final isSelected = _currentIndex == idx;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              setState(() {
                                _currentIndex = idx;
                              });
                            },
                            hoverColor: isSelected ? AppColors.primaryHover : AppColors.cardBg,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    size: 16,
                                    color: isSelected ? Colors.white : AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item['title'] as String,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        color: isSelected ? Colors.white : AppColors.textBody,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 1.4 Inactive Agent Alert Banner (if agent not active)
                if (!isAgentActive)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Agent chưa được bật',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warning),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          height: 28,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: Colors.black,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () {
                              setState(() {
                                _currentIndex = 2; // Switch to Cài đặt
                              });
                            },
                            child: const Text('Cài đặt hệ thống', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 1.45 User Account Info & Logout in sidebar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          (auth.userEmail?.isNotEmpty == true)
                              ? auth.userEmail![0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              auth.userEmail ?? 'admin@tadu.vn',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                            ),
                            const Text(
                              '50k token AI',
                              style: TextStyle(fontSize: 9.5, color: AppColors.accent, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        icon: const Icon(Icons.logout_rounded, size: 15, color: AppColors.textDim),
                        tooltip: 'Đăng xuất',
                        onPressed: () => _confirmLogout(context, auth),
                      ),
                    ],
                  ),
                ),

                // 1.5 Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_rounded, size: 14, color: AppColors.accent),
                          SizedBox(width: 6),
                          Text('AI Agent Desktop', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                        ],
                      ),
                      Text('v1.3.0', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppColors.textDim)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. MAIN ACTIVE VIEW AREA
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // MOBILE LAYOUT
  // =========================================================================
  Widget _buildMobileLayout() {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.8)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: AppColors.sidebarBg,
          indicatorColor: AppColors.primary.withValues(alpha: 0.25),
          onDestinationSelected: (idx) {
            setState(() {
              _currentIndex = idx;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded, color: AppColors.primaryLight),
              label: 'Trợ lý AI',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_rounded),
              selectedIcon: Icon(Icons.menu_book_rounded, color: AppColors.primaryLight),
              label: 'Tài liệu',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded, color: AppColors.primaryLight),
              label: 'Cài đặt',
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 420,
        maxWidth: 480,
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Xác Nhận Đăng Xuất'),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản AI Agent Chatbot?',
          style: TextStyle(fontSize: 13, color: AppColors.textBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
              AppToast.info(context, 'Đã đăng xuất tài khoản.');
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}
