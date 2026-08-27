import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../providers/chat_provider.dart';
import '../../providers/server_provider.dart';
import 'chat/chat_screen.dart';
import 'terminal/terminal_screen.dart';
import 'logs/logs_screen.dart';
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
      context.read<ChatProvider>().loadSessions();
    });
  }

  final List<Widget> _screens = const [
    ChatScreen(),
    TerminalScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  final List<Map<String, dynamic>> _tabs = [
    {
      'title': 'Trợ lý AI',
      'subtitle': 'Trợ lý AI lập trình và tự động hoá Local',
      'icon': Icons.chat_bubble_outline_rounded,
    },
    {
      'title': 'Terminal',
      'subtitle': 'Interactive Terminal trên máy tính cục bộ',
      'icon': Icons.terminal_rounded,
    },
    {
      'title': 'Logs',
      'subtitle': 'Nhật ký thực thi câu lệnh và hoạt động',
      'icon': Icons.description_outlined,
    },
    {
      'title': 'Cấu hình',
      'subtitle': 'Cấu hình AI Model, API Key và Hệ thống Local',
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
  // DESKTOP LAYOUT (EXACT 250px SIDEBAR)
  // =========================================================================
  Widget _buildDesktopLayout() {
    final serverProvider = context.watch<ServerProvider>();

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
                      const AppLogo(size: 36),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Type',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textWhite,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              'LOCAL AI AGENT',
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
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),

                // 1.2 Local Machine Badge
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.laptop_chromebook_rounded, size: 16, color: AppColors.accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Local Machine',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                              ),
                              Text(
                                '${Platform.operatingSystem.toUpperCase()} • ${serverProvider.currentAiModel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 1.3 Nav Buttons
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
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['title'] as String,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            color: isSelected ? Colors.white : AppColors.textDim,
                                          ),
                                        ),
                                        Text(
                                          item['subtitle'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            color: isSelected ? Colors.white70 : AppColors.textMuted,
                                          ),
                                        ),
                                      ],
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

                // 1.4 Footer
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
                          Text('AI Type Desktop', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
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
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal_rounded, color: AppColors.primaryLight),
              label: 'Terminal',
            ),
            NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description_rounded, color: AppColors.primaryLight),
              label: 'Logs',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded, color: AppColors.primaryLight),
              label: 'Cấu hình',
            ),
          ],
        ),
      ),
    );
  }
}
