import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../providers/chat_provider.dart';
import '../../providers/server_provider.dart';
import 'chat/chat_screen.dart';
import 'chat/widgets/session_list_sidebar.dart';
import 'servers/servers_screen.dart';
import 'server_setup/server_setup_screen.dart';
import 'terminal/terminal_screen.dart';
import 'settings/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  String _activeTabKey = 'chat';
  bool _isSidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().loadServers();
      context.read<ChatProvider>().loadSessions();
    });
  }

  late final List<Widget> _screens = [
    ChatScreen(
      onNavigateToServers: () {
        setState(() {
          _activeTabKey = 'servers';
        });
      },
    ), // 0: chat
    const ServersScreen(), // 1: servers
    const ServerSetupScreen(), // 2: setup
    const TerminalScreen(), // 3: terminal
    const SettingsScreen(), // 4: settings
  ];

  int get _stackIndex {
    switch (_activeTabKey) {
      case 'chat':
        return 0;
      case 'servers':
        return 1;
      case 'setup':
        return 2;
      case 'terminal':
        return 3;
      case 'settings':
        return 4;
      default:
        return 0;
    }
  }

  List<Map<String, dynamic>> _getVisibleTabs(bool isLocal) {
    return [
      {
        'key': 'chat',
        'title': 'Trợ lý AI',
        'subtitle': 'Trợ lý lập trình & Quản trị Server/Local',
        'icon': Icons.chat_bubble_outline_rounded,
        'mobileIcon': Icons.chat_bubble_rounded,
        'shortLabel': 'Trợ lý AI',
      },
      {
        'key': 'servers',
        'title': 'Máy chủ & SSH',
        'subtitle': 'Quản lý Server & Kết nối SSH',
        'icon': Icons.dns_outlined,
        'mobileIcon': Icons.dns_rounded,
        'shortLabel': 'Máy chủ',
      },
      if (!isLocal)
        {
          'key': 'setup',
          'title': 'Thiết lập máy chủ',
          'subtitle': 'Deploy & Dịch vụ AI Agent',
          'icon': Icons.build_circle_outlined,
          'mobileIcon': Icons.build_circle_rounded,
          'shortLabel': 'Thiết lập',
        },
      {
        'key': 'terminal',
        'title': 'Terminal',
        'subtitle': 'Interactive Terminal Local & SSH',
        'icon': Icons.terminal_rounded,
        'mobileIcon': Icons.terminal_rounded,
        'shortLabel': 'Terminal',
      },
      {
        'key': 'settings',
        'title': 'Cấu hình',
        'subtitle': 'Cấu hình AI Model, API Key & Hệ thống',
        'icon': Icons.settings_outlined,
        'mobileIcon': Icons.settings_rounded,
        'shortLabel': 'Cấu hình',
      },
    ];
  }

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
  // DESKTOP LAYOUT (ANIMATED COLLAPSIBLE SIDEBAR: 250px <-> 68px)
  // =========================================================================
  Widget _buildDesktopLayout() {
    final serverProvider = context.watch<ServerProvider>();
    final isCollapsed = _isSidebarCollapsed;
    final sidebarWidth = isCollapsed ? 68.0 : 270.0;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Row(
        children: [
          // 1. LEFT SIDEBAR
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            width: sidebarWidth,
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(right: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: isCollapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                // 1.1 Brand Header (Height 66px)
                Container(
                  height: 66,
                  padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
                  ),
                  child: isCollapsed
                      ? Center(
                          child: IconButton(
                            icon: const Icon(Icons.menu_rounded, size: 22, color: AppColors.textWhite),
                            tooltip: 'Mở rộng menu (Sidebar)',
                            onPressed: () {
                              setState(() {
                                _isSidebarCollapsed = false;
                              });
                            },
                          ),
                        )
                      : Row(
                          children: [
                            Stack(
                              children: [
                                const AppLogo(size: 32),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppColors.accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.sidebarBg, width: 1.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Type',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textWhite,
                                      height: 1.2,
                                    ),
                                  ),
                                  Text(
                                    'LOCAL AI AGENT',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.menu_open_rounded, size: 18, color: AppColors.textMuted),
                              tooltip: 'Thu gọn menu (Sidebar)',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () {
                                setState(() {
                                  _isSidebarCollapsed = true;
                                });
                              },
                            ),
                          ],
                        ),
                ),

                // 1.2 Navigation & Content Area
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isLocal = serverProvider.selectedServer == null ||
                          serverProvider.selectedServer!.serverIp == '127.0.0.1' ||
                          serverProvider.selectedServer!.serverIp == 'localhost';
                      final visibleTabs = _getVisibleTabs(isLocal);

                      // If collapsed: Show standard vertical icon bar
                      if (isCollapsed) {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: visibleTabs.length,
                          itemBuilder: (context, idx) {
                            final item = visibleTabs[idx];
                            final isSelected = _activeTabKey == item['key'];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Tooltip(
                                message: '${item['title']}\n${item['subtitle']}',
                                preferBelow: false,
                                waitDuration: const Duration(milliseconds: 250),
                                child: Material(
                                  color: isSelected ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      setState(() {
                                        _activeTabKey = item['key'] as String;
                                      });
                                    },
                                    hoverColor: isSelected ? AppColors.primaryHover : AppColors.cardBg,
                                    child: Container(
                                      height: 42,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        item['icon'] as IconData,
                                        size: 18,
                                        color: isSelected ? Colors.white : AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }

                      // Expanded Left Sidebar: Unified single column session list
                      return SessionListSidebar(
                        isCollapsed: false,
                        onExpandRequested: () {
                          setState(() {
                            _isSidebarCollapsed = false;
                          });
                        },
                        onSessionSelected: () {
                          if (_activeTabKey != 'chat') {
                            setState(() {
                              _activeTabKey = 'chat';
                            });
                          }
                        },
                      );
                    },
                  ),
                ),

                // 1.4 Footer Navigation & Version
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 6 : 10, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
                  ),
                  child: isCollapsed
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.dns_outlined, size: 18, color: AppColors.textDim),
                              tooltip: 'Máy chủ & SSH',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => setState(() => _activeTabKey = 'servers'),
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined, size: 18, color: AppColors.textDim),
                              tooltip: 'Cấu hình',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => setState(() => _activeTabKey = 'settings'),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'chat' ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color: _activeTabKey == 'chat' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Hội thoại AI',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => setState(() => _activeTabKey = 'chat'),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'servers' ? Icons.dns_rounded : Icons.dns_outlined,
                                size: 16,
                                color: _activeTabKey == 'servers' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Máy chủ & SSH',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => setState(() => _activeTabKey = 'servers'),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'settings' ? Icons.settings_rounded : Icons.settings_outlined,
                                size: 16,
                                color: _activeTabKey == 'settings' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Cấu hình hệ thống',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => setState(() => _activeTabKey = 'settings'),
                            ),
                            const Spacer(),
                            const Text('v1.3.0', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppColors.textMuted)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),

          // 2. MAIN ACTIVE VIEW AREA
          Expanded(
            child: IndexedStack(
              index: _stackIndex,
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
    final serverProvider = context.watch<ServerProvider>();
    final isLocal = serverProvider.selectedServer == null ||
        serverProvider.selectedServer!.serverIp == '127.0.0.1' ||
        serverProvider.selectedServer!.serverIp == 'localhost';
    final visibleTabs = _getVisibleTabs(isLocal);
    final curIdx = visibleTabs.indexWhere((t) => t['key'] == _activeTabKey);
    final safeIdx = curIdx >= 0 ? curIdx : 0;

    return Scaffold(
      body: IndexedStack(
        index: _stackIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.8)),
        ),
        child: NavigationBar(
          selectedIndex: safeIdx,
          backgroundColor: AppColors.sidebarBg,
          indicatorColor: AppColors.primary.withValues(alpha: 0.25),
          onDestinationSelected: (idx) {
            setState(() {
              _activeTabKey = visibleTabs[idx]['key'] as String;
            });
          },
          destinations: visibleTabs.map((t) {
            return NavigationDestination(
              icon: Icon(t['icon'] as IconData),
              selectedIcon: Icon(t['mobileIcon'] as IconData, color: AppColors.primaryLight),
              label: t['shortLabel'] as String,
            );
          }).toList(),
        ),
      ),
    );
  }
}
