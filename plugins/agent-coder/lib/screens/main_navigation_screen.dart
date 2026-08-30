import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
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
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            (serverProvider.selectedServer != null &&
                                                    serverProvider.selectedServer!.serverIp != '127.0.0.1' &&
                                                    serverProvider.selectedServer!.serverIp != 'localhost')
                                                ? '${serverProvider.selectedServer!.serverIp} • '
                                                : '${Platform.operatingSystem.toUpperCase()} • ',
                                            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                          ),
                                          Flexible(
                                            child: _buildModelSelectorDropdown(context, serverProvider),
                                          ),
                                        ],
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

  Widget _buildModelSelectorDropdown(BuildContext context, ServerProvider serverProvider) {
    final currentModel = serverProvider.currentAiModel;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => _ModelPickerDialog(serverProvider: serverProvider),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  currentModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down_rounded, size: 13, color: AppColors.primaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelPickerDialog extends StatefulWidget {
  final ServerProvider serverProvider;
  const _ModelPickerDialog({required this.serverProvider});

  static void showCustomModelDialog(BuildContext context, ServerProvider serverProvider) {
    final ctrl = TextEditingController(text: serverProvider.currentAiModel);
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 380,
        maxWidth: 440,
        title: const Row(
          children: [
            Icon(Icons.tune_rounded, size: 20, color: AppColors.primaryLight),
            SizedBox(width: 8),
            Text('Nhập AI Model / CLI Agent'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập tên Model API hoặc lệnh CLI đã cài trên máy:',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.textWhite),
              decoration: const InputDecoration(
                hintText: 'Ví dụ: antigravity-cli, claude-cli, ollama:llama3...',
                hintStyle: TextStyle(fontSize: 11.5, color: AppColors.textDim),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                serverProvider.setActiveAgent(val);
                Navigator.pop(ctx);
                AppToast.success(context, 'Đã cập nhật AI Model: $val');
              }
            },
            child: const Text('Lưu chọn'),
          ),
        ],
      ),
    );
  }

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = widget.serverProvider;
    final currentModel = serverProvider.currentAiModel;

    // Filter CLI agents
    final q = _searchQuery.toLowerCase();
    final filteredCliAgents = serverProvider.installedCliAgents.where((a) {
      if (q.isEmpty) return true;
      return a.id.toLowerCase().contains(q) || a.label.toLowerCase().contains(q);
    }).toList();

    // Filter Cloud models
    final allCloudModels = serverProvider.remoteModels.isNotEmpty
        ? serverProvider.remoteModels
        : ['glm-5.3', 'gpt-4o', 'deepseek-chat', 'claude-3-7-sonnet'];

    final filteredCloudModels = allCloudModels.where((m) {
      if (q.isEmpty) return true;
      return m.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: AppColors.cardBg,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark, width: 1),
      ),
      child: Container(
        width: 560,
        height: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, size: 20, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chọn AI Agent & Model',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Chuyển đổi giữa Local CLI Agents và Cloud API Models',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.radar_rounded, size: 18, color: AppColors.accent),
                  tooltip: 'Quét lại Local CLI Agents',
                  onPressed: () {
                    serverProvider.scanCliAgents(forceRefresh: true);
                    AppToast.info(context, 'Đang quét lại các CLI Agent trên máy local...');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.primaryLight),
                  tooltip: 'Tải lại danh sách từ API Base URL',
                  onPressed: () {
                    serverProvider.fetchModels(forceRefresh: true);
                    AppToast.info(context, 'Đang tải lại danh sách model từ API...');
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 2. Instant Search Input
            SizedBox(
              height: 38,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Tìm kiếm nhanh model (VD: claude, gemini, glm, deepseek, qwen, agy...)...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textDim),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.primaryLight, width: 1),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 3. Scrollable List of Models & Agents
            Expanded(
              child: ListView(
                children: [
                  // --- LOCAL CLI AGENTS ---
                  if (filteredCliAgents.isNotEmpty || serverProvider.isScanningCliAgents) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal_rounded, size: 13, color: AppColors.primaryLight),
                          const SizedBox(width: 6),
                          const Text(
                            'LOCAL CLI AGENTS (CÀI TRÊN MÁY LOCAL)',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 0.5),
                          ),
                          const Spacer(),
                          Text(
                            '${filteredCliAgents.length} agents',
                            style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                    if (serverProvider.isScanningCliAgents)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                          ),
                        ),
                      )
                    else
                      ...filteredCliAgents.map((agent) {
                        final isSel = currentModel == agent.id;
                        final icon = agent.id.contains('antigravity')
                            ? Icons.terminal_rounded
                            : (agent.id.contains('claude') ? Icons.code_rounded : Icons.memory_rounded);
                        final verStr = agent.version != null ? ' • v${agent.version}' : '';

                        return _buildModelCard(
                          title: agent.id,
                          subtitle: '${agent.label}$verStr',
                          icon: icon,
                          isSelected: isSel,
                          onTap: () {
                            serverProvider.setActiveAgent(agent.id);
                            Navigator.pop(context);
                            AppToast.success(context, 'Đã chuyển sang Local CLI Agent: ${agent.id}');
                          },
                        );
                      }),
                    const SizedBox(height: 12),
                  ],

                  // --- CLOUD LLM MODELS ---
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_queue_rounded, size: 13, color: AppColors.accentCyan),
                        const SizedBox(width: 6),
                        const Text(
                          'CLOUD LLM MODELS (API BASE URL)',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentCyan, letterSpacing: 0.5),
                        ),
                        const Spacer(),
                        Text(
                          '${filteredCloudModels.length} models',
                          style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ),

                  if (serverProvider.isLoadingModels)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                        ),
                      ),
                    )
                  else if (filteredCloudModels.isNotEmpty)
                    ...filteredCloudModels.map((m) {
                      final isSel = currentModel == m;
                      IconData icon = Icons.memory_rounded;
                      if (m.contains('glm')) {
                        icon = Icons.auto_awesome_rounded;
                      } else if (m.contains('gpt')) {
                        icon = Icons.psychology_rounded;
                      } else if (m.contains('claude')) {
                        icon = Icons.star_rounded;
                      } else if (m.contains('gemini')) {
                        icon = Icons.auto_awesome_rounded;
                      } else if (m.contains('deepseek')) {
                        icon = Icons.code_rounded;
                      } else if (m.contains('qwen')) {
                        icon = Icons.hub_rounded;
                      }

                      return _buildModelCard(
                        title: m,
                        subtitle: 'Cloud API Model',
                        icon: icon,
                        isSelected: isSel,
                        onTap: () {
                          serverProvider.setActiveAgent(m);
                          Navigator.pop(context);
                          AppToast.success(context, 'Đã chọn Cloud Model: $m');
                        },
                      );
                    })
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off_rounded, size: 28, color: AppColors.textDim),
                          const SizedBox(height: 8),
                          Text(
                            'Không tìm thấy model nào khớp với "$_searchQuery"',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primaryLight),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 14, color: AppColors.primaryLight),
                              label: Text('Chọn "$_searchQuery" làm model', style: const TextStyle(fontSize: 11.5, color: AppColors.primaryLight)),
                              onPressed: () {
                                serverProvider.setActiveAgent(_searchQuery);
                                Navigator.pop(context);
                                AppToast.success(context, 'Đã thiết lập model: $_searchQuery');
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: AppColors.borderDark, height: 1),
            const SizedBox(height: 10),

            // 4. Footer Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.textDim),
                  label: const Text('Nhập model tùy biến khác...', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                  onPressed: () {
                    Navigator.pop(context);
                    _ModelPickerDialog.showCustomModelDialog(context, serverProvider);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
          width: isSelected ? 1.2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          hoverColor: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? AppColors.accent : AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? AppColors.accent : AppColors.textWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.accent, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 12, color: AppColors.accent),
                        SizedBox(width: 4),
                        Text(
                          'ĐANG CHỌN',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textDim),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
