import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/server_model.dart';
import '../../providers/chat_provider.dart';
import '../../providers/server_provider.dart';
import 'chat/chat_screen.dart';
import 'servers/servers_screen.dart';
import 'server_setup/server_setup_screen.dart';
import 'terminal/terminal_screen.dart';
import 'logs/logs_screen.dart';
import 'settings/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  String _activeTabKey = 'chat';
  bool _isSidebarCollapsed = false;

  Future<void> _switchToLocal(ServerProvider serverProvider) async {
    final localSrv = ServerModel(
      id: 'local',
      name: 'Local Machine',
      serverIp: '127.0.0.1',
    );
    await serverProvider.selectServer(localSrv);
    if (!mounted) return;
    AppToast.success(context, 'Đã chuyển sang chế độ Local Machine');
  }

  Future<void> _switchToServer(ServerProvider serverProvider, ServerModel srv) async {
    await serverProvider.selectServer(srv);
    if (!mounted) return;
    AppToast.success(context, 'Đã chuyển sang máy chủ: ${srv.name}');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().loadServers();
      context.read<ChatProvider>().loadSessions();
    });
  }

  final List<Widget> _screens = const [
    ChatScreen(), // 0: chat
    ServersScreen(), // 1: servers
    ServerSetupScreen(), // 2: setup
    TerminalScreen(), // 3: terminal
    LogsScreen(), // 4: logs
    SettingsScreen(), // 5: settings
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
      case 'logs':
        return 4;
      case 'settings':
        return 5;
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
        'key': 'logs',
        'title': 'Logs',
        'subtitle': 'Nhật ký thực thi câu lệnh và hoạt động',
        'icon': Icons.description_outlined,
        'mobileIcon': Icons.description_rounded,
        'shortLabel': 'Logs',
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
    final sidebarWidth = isCollapsed ? 68.0 : 250.0;

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
                            const AppLogo(size: 32),
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
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
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

                // 1.2 Active Target Environment Badge
                Padding(
                  padding: EdgeInsets.all(isCollapsed ? 8 : 12),
                  child: PopupMenuButton<ServerModel>(
                    tooltip: isCollapsed
                        ? ((serverProvider.selectedServer != null &&
                                serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                serverProvider.selectedServer!.serverIp != 'localhost')
                            ? 'Máy chủ: ${serverProvider.selectedServer!.name}'
                            : 'Môi trường: Local Machine')
                        : 'Chuyển đổi Máy chủ / Local',
                    offset: const Offset(0, 52),
                    color: AppColors.cardBg,
                    constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: const BorderSide(color: AppColors.borderDark),
                    ),
                    onSelected: (srv) {
                      if (srv.id == '__manage_servers__') {
                        setState(() {
                          _activeTabKey = 'servers';
                        });
                      } else if (srv.id == 'local' || srv.serverIp == '127.0.0.1' || srv.serverIp == 'localhost') {
                        _switchToLocal(serverProvider);
                      } else {
                        _switchToServer(serverProvider, srv);
                      }
                    },
                    itemBuilder: (ctx) {
                      final list = <PopupMenuEntry<ServerModel>>[];
                      final isLocalSelected = serverProvider.selectedServer == null ||
                          serverProvider.selectedServer!.serverIp == '127.0.0.1' ||
                          serverProvider.selectedServer!.serverIp == 'localhost';

                      // 1. Local Machine item
                      list.add(
                        PopupMenuItem<ServerModel>(
                          value: ServerModel(id: 'local', name: 'Local Machine', serverIp: '127.0.0.1'),
                          child: Row(
                            children: [
                              const Icon(Icons.laptop_chromebook_rounded, size: 16, color: AppColors.accent),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Local Machine', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                    Text('Thực thi trực tiếp trên máy', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              if (isLocalSelected) const Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
                            ],
                          ),
                        ),
                      );

                      // 2. VPS Servers list
                      if (serverProvider.servers.isNotEmpty) {
                        list.add(const PopupMenuDivider());
                        for (final s in serverProvider.servers) {
                          final isSel = !isLocalSelected &&
                              (s.id == serverProvider.selectedServer?.id || s.serverIp == serverProvider.selectedServer?.serverIp);
                          list.add(
                            PopupMenuItem<ServerModel>(
                              value: s,
                              child: Row(
                                children: [
                                  const Icon(Icons.dns_rounded, size: 16, color: AppColors.primaryLight),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                        Text('${s.sshUser}@${s.serverIp}:${s.sshPort}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  if (isSel) const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryLight),
                                ],
                              ),
                            ),
                          );
                        }
                      }

                      // 3. Manage Servers item
                      list.add(const PopupMenuDivider());
                      list.add(
                        PopupMenuItem<ServerModel>(
                          value: ServerModel(id: '__manage_servers__', name: 'Quản lý máy chủ', serverIp: ''),
                          child: const Row(
                            children: [
                              Icon(Icons.settings_suggest_outlined, size: 16, color: AppColors.textDim),
                              SizedBox(width: 10),
                              Text(
                                'Quản lý máy chủ & Thêm mới...',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
                              ),
                            ],
                          ),
                        ),
                      );

                      return list;
                    },
                    child: isCollapsed
                        ? Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: (serverProvider.selectedServer != null &&
                                      serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                      serverProvider.selectedServer!.serverIp != 'localhost')
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Icon(
                              (serverProvider.selectedServer != null &&
                                      serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                      serverProvider.selectedServer!.serverIp != 'localhost')
                                  ? Icons.dns_rounded
                                  : Icons.laptop_chromebook_rounded,
                              size: 18,
                              color: (serverProvider.selectedServer != null &&
                                      serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                      serverProvider.selectedServer!.serverIp != 'localhost')
                                  ? AppColors.primaryLight
                                  : AppColors.accent,
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: (serverProvider.selectedServer != null &&
                                            serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                            serverProvider.selectedServer!.serverIp != 'localhost')
                                        ? AppColors.primary.withValues(alpha: 0.2)
                                        : AppColors.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    (serverProvider.selectedServer != null &&
                                            serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                            serverProvider.selectedServer!.serverIp != 'localhost')
                                        ? Icons.dns_rounded
                                        : Icons.laptop_chromebook_rounded,
                                    size: 16,
                                    color: (serverProvider.selectedServer != null &&
                                            serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                            serverProvider.selectedServer!.serverIp != 'localhost')
                                        ? AppColors.primaryLight
                                        : AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (serverProvider.selectedServer != null &&
                                                serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                                serverProvider.selectedServer!.serverIp != 'localhost')
                                            ? serverProvider.selectedServer!.name
                                            : 'Local Machine',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                      ),
                                      Text(
                                        (serverProvider.selectedServer != null &&
                                                serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                                serverProvider.selectedServer!.serverIp != 'localhost')
                                            ? '${serverProvider.selectedServer!.serverIp} • ${serverProvider.currentAiModel}'
                                            : '${Platform.operatingSystem.toUpperCase()} • ${serverProvider.currentAiModel}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.unfold_more_rounded, size: 14, color: AppColors.textDim),
                              ],
                            ),
                          ),
                  ),
                ),

                // 1.3 Nav Buttons
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isLocal = serverProvider.selectedServer == null ||
                          serverProvider.selectedServer!.serverIp == '127.0.0.1' ||
                          serverProvider.selectedServer!.serverIp == 'localhost';
                      final visibleTabs = _getVisibleTabs(isLocal);

                      return ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 6 : 10),
                        itemCount: visibleTabs.length,
                        itemBuilder: (context, idx) {
                          final item = visibleTabs[idx];
                          final isSelected = _activeTabKey == item['key'];

                          if (isCollapsed) {
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
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
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
                      );
                    },
                  ),
                ),

                // 1.4 Footer
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
                  ),
                  child: isCollapsed
                      ? const Center(
                          child: Tooltip(
                            message: 'AI Type Desktop v1.3.0',
                            child: Icon(Icons.shield_rounded, size: 16, color: AppColors.accent),
                          ),
                        )
                      : const Row(
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
