import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/primary_host_server_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_toast.dart';
import '../../providers/chat_provider.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/server_provider.dart';
import 'chat/chat_screen.dart';
import 'chat/widgets/session_list_sidebar.dart';
import 'servers/servers_screen.dart';
import 'server_setup/server_setup_screen.dart';
import 'terminal/terminal_screen.dart';
import 'settings/settings_screen.dart';
import 'aitype_admin/aitype_admin_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();
  String _activeTabKey = 'chat';
  bool _isSidebarCollapsed = false;
  StreamSubscription<PendingPairingRequest>? _pairingReqSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().loadServers();
      context.read<ChatProvider>().loadSessions();
    });
    _pairingReqSub = PrimaryHostServerService.instance.onPairingRequest.listen(_showIncomingPairingDialog);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<ChatProvider>().onAppResumed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pairingReqSub?.cancel();
    super.dispose();
  }

  void _showIncomingPairingDialog(PendingPairingRequest req) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.primaryLight, width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.phonelink_setup_rounded, color: AppColors.primaryLight, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Yêu cầu điều khiển từ App Phụ',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thiết bị "${req.clientDeviceName}" (${req.clientOs.toUpperCase()} • ${req.clientIp}) đang muốn kết nối để điều khiển máy tính này.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    const Text(
                      'MÃ ĐỐI CHIẾU TRÊN ĐIỆN THOẠI',
                      style: TextStyle(fontSize: 10, color: AppColors.textMuted, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      req.pin,
                      style: const TextStyle(
                        fontSize: 22,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: AppColors.accentCyan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                PrimaryHostServerService.instance.rejectPairingRequest(req.id);
                Navigator.of(dlgCtx).pop();
                if (mounted) {
                  AppToast.info(context, 'Đã từ chối kết nối từ ${req.clientDeviceName}.');
                }
              },
              child: const Text('Từ chối', style: TextStyle(color: AppColors.danger)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Chấp nhận kết nối'),
              onPressed: () {
                PrimaryHostServerService.instance.approvePairingRequest(req.id);
                Navigator.of(dlgCtx).pop();
                if (mounted) {
                  AppToast.success(context, 'Đã cho phép "${req.clientDeviceName}" điều khiển máy tính này!');
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _openMobileDrawer() {
    _mobileScaffoldKey.currentState?.openDrawer();
  }

  late final List<Widget> _screens = [
    ChatScreen(
      embedTerminalPanel: false,
      onOpenSessionsDrawer: _openMobileDrawer,
      onNavigateToServers: () {
        setState(() {
          _activeTabKey = 'servers';
        });
      },
    ), // 0: chat
    ServersScreen(onOpenDrawer: _openMobileDrawer), // 1: servers
    ServerSetupScreen(onOpenDrawer: _openMobileDrawer), // 2: setup
    TerminalScreen(onOpenDrawer: _openMobileDrawer), // 3: terminal
    SettingsScreen(onOpenDrawer: _openMobileDrawer), // 4: settings
    AiTypeAdminScreen(onOpenDrawer: _openMobileDrawer), // 5: admin
  ];

  late final List<Widget> _desktopScreens = [
    ChatScreen(
      embedTerminalPanel: true,
      onNavigateToServers: () {
        setState(() {
          _activeTabKey = 'servers';
        });
      },
    ), // 0: chat
    const ServersScreen(), // 1: servers
    const ServerSetupScreen(), // 2: setup
    const SizedBox.shrink(), // 3: terminal is embedded directly in ChatScreen on desktop
    const SettingsScreen(), // 4: settings
    const AiTypeAdminScreen(), // 5: admin
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
      case 'admin':
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
        'key': 'admin',
        'title': 'Quản trị AI.Type',
        'subtitle': 'Thanh toán SMS, License Keys & Thành viên type.vn',
        'icon': Icons.admin_panel_settings_outlined,
        'mobileIcon': Icons.admin_panel_settings_rounded,
        'shortLabel': 'Quản trị',
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

  static ButtonStyle _sidebarIconStyle(double size) => IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size(size, size),
        fixedSize: Size(size, size),
        maximumSize: Size(size, size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      );

  // =========================================================================
  // DESKTOP LAYOUT (ANIMATED COLLAPSIBLE SIDEBAR: 250px <-> 68px)
  // =========================================================================
  Widget _buildDesktopLayout() {
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
                              style: _sidebarIconStyle(28),
                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
                  child: SessionListSidebar(
                    isCollapsed: isCollapsed,
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
                              icon: Icon(
                                _activeTabKey == 'chat' ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: _activeTabKey == 'chat' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Hội thoại AI',
                              style: _sidebarIconStyle(32),
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              onPressed: () => setState(() => _activeTabKey = 'chat'),
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'servers' ? Icons.dns_rounded : Icons.dns_outlined,
                                size: 18,
                                color: _activeTabKey == 'servers' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Máy chủ & SSH',
                              style: _sidebarIconStyle(32),
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              onPressed: () => setState(() => _activeTabKey = 'servers'),
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'admin'
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.admin_panel_settings_outlined,
                                size: 18,
                                color: _activeTabKey == 'admin' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Quản trị AI.Type',
                              style: _sidebarIconStyle(32),
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              onPressed: () => setState(() => _activeTabKey = 'admin'),
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'settings' ? Icons.settings_rounded : Icons.settings_outlined,
                                size: 18,
                                color: _activeTabKey == 'settings' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Cấu hình',
                              style: _sidebarIconStyle(32),
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
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
                              style: _sidebarIconStyle(28),
                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
                              style: _sidebarIconStyle(28),
                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                              onPressed: () => setState(() => _activeTabKey = 'servers'),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'admin'
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.admin_panel_settings_outlined,
                                size: 16,
                                color: _activeTabKey == 'admin' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Quản trị AI.Type',
                              style: _sidebarIconStyle(28),
                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                              onPressed: () => setState(() => _activeTabKey = 'admin'),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                _activeTabKey == 'settings' ? Icons.settings_rounded : Icons.settings_outlined,
                                size: 16,
                                color: _activeTabKey == 'settings' ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: 'Cấu hình hệ thống',
                              style: _sidebarIconStyle(28),
                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                              onPressed: () => setState(() => _activeTabKey = 'settings'),
                            ),
                            const Spacer(),
                            Builder(
                              builder: (ctx) {
                                final gw = ctx.watch<GatewayProvider>();
                                if (gw.isSecondary) {
                                  return Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (gw.isConnected ? AppColors.accentCyan : AppColors.warning).withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      gw.isConnected ? 'App Phụ' : 'Phụ (Offline)',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: gw.isConnected ? AppColors.accentCyan : AppColors.warning,
                                      ),
                                    ),
                                  );
                                }
                                if (gw.isHostRunning) {
                                  final countSuffix = gw.onlineClientsCount > 0
                                      ? ' • ${gw.onlineClientsCount} máy'
                                      : '';
                                  return Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (gw.isInternetTunnelRunning ? AppColors.accentCyan : AppColors.accent)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${gw.isInternetTunnelRunning ? 'Internet' : 'Host :${gw.hostBoundPort}'}$countSuffix',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: gw.isInternetTunnelRunning ? AppColors.accentCyan : AppColors.accent,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            const Text('v1.5.10', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppColors.textMuted)),
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
              children: _desktopScreens,
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
    final gateway = context.watch<GatewayProvider>();
    final isLocal = serverProvider.selectedServer == null ||
        serverProvider.selectedServer!.serverIp == '127.0.0.1' ||
        serverProvider.selectedServer!.serverIp == 'localhost';
    final visibleTabs = _getVisibleTabs(isLocal);
    final navIconSize = visibleTabs.length > 5 ? 26.0 : 28.0;
    final navIconGap = visibleTabs.length > 5 ? 2.0 : 4.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.bgDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        key: _mobileScaffoldKey,
        backgroundColor: AppColors.bgDark,
        drawer: Drawer(
          width: 296,
          backgroundColor: AppColors.sidebarBg,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SessionListSidebar(
                    isCollapsed: false,
                    onSessionSelected: () {
                      Navigator.of(context).pop();
                      if (_activeTabKey != 'chat') {
                        setState(() => _activeTabKey = 'chat');
                      }
                    },
                  ),
                ),
                // Footer Navigation (Trợ lý AI, Máy chủ, Terminal, Quản trị, Cấu hình)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
                  ),
                  child: Row(
                    children: [
                      ...visibleTabs.map((t) {
                        final tabKey = t['key'] as String;
                        final isSelected = _activeTabKey == tabKey;
                        final iconData = isSelected
                            ? (t['mobileIcon'] as IconData)
                            : (t['icon'] as IconData);
                        return Padding(
                          padding: EdgeInsets.only(right: navIconGap),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: IconButton(
                              icon: Icon(
                                iconData,
                                size: 17,
                                color: isSelected ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              tooltip: t['shortLabel'] as String,
                              style: _sidebarIconStyle(navIconSize),
                              constraints: BoxConstraints.tightFor(
                                width: navIconSize,
                                height: navIconSize,
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                if (_activeTabKey != tabKey) {
                                  setState(() => _activeTabKey = tabKey);
                                }
                              },
                            ),
                          ),
                        );
                      }),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (gateway.isSecondary)
                                Flexible(
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (gateway.isConnected ? AppColors.accentCyan : AppColors.warning)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      gateway.isConnected ? 'App Phụ' : 'Phụ (Offline)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: gateway.isConnected ? AppColors.accentCyan : AppColors.warning,
                                      ),
                                    ),
                                  ),
                                )
                              else if (gateway.isHostRunning)
                                Flexible(
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (gateway.isInternetTunnelRunning ? AppColors.accentCyan : AppColors.accent)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      gateway.isInternetTunnelRunning ? 'Internet' : 'Host :${gateway.hostBoundPort}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: gateway.isInternetTunnelRunning ? AppColors.accentCyan : AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              const Text(
                                'v1.5.10',
                                style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          top: true,
          bottom: true,
          child: Column(
            children: [
              if (gateway.isSecondary)
                InkWell(
                  onTap: () => setState(() => _activeTabKey = 'settings'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: (gateway.isConnected ? AppColors.primary : AppColors.warning).withValues(alpha: 0.16),
                      border: Border(
                        bottom: BorderSide(
                          color: (gateway.isConnected ? AppColors.primaryLight : AppColors.warning).withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          gateway.isConnected ? Icons.phonelink_rounded : Icons.link_off_rounded,
                          size: 13,
                          color: gateway.isConnected ? AppColors.accentCyan : AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            gateway.isConnected
                                ? 'App Phụ (${gateway.isSecondaryOverInternet ? 'Internet' : 'LAN'}) đang điều khiển: ${gateway.remoteHostName} (${gateway.pingMs} ms)'
                                : 'App Phụ chưa kết nối App Chính • Chạm để cấu hình',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: gateway.isConnected ? AppColors.accentCyan : AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _stackIndex,
                  children: _screens,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
