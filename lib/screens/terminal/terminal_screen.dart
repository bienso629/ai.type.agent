import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';
import '../../providers/terminal_provider.dart';

export '../../models/terminal_pane_model.dart';
export '../../providers/terminal_provider.dart';

class TerminalScreen extends StatefulWidget {
  final VoidCallback? onHidePanel;

  const TerminalScreen({super.key, this.onHidePanel});

  @override
  State<TerminalScreen> createState() => TerminalScreenState();
}

class TerminalScreenState extends State<TerminalScreen> with AutomaticKeepAliveClientMixin {
  final ScrollController _tabScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  // Bảng màu terminal đồng bộ màu nền ứng dụng (AppColors.bgDark)
  static final _terminalTheme = TerminalTheme(
    cursor: const Color(0xFFFFFFFF),
    selection: AppColors.primary.withValues(alpha: 0.40),
    foreground: const Color(0xFFFFFFFF),
    background: AppColors.bgDark, // Trùng với màu nền của ứng dụng
    black: const Color(0xFF2E3436),
    red: const Color(0xFFCC0000),
    green: const Color(0xFF4E9A06),
    yellow: const Color(0xFFC4A000),
    blue: const Color(0xFF3465A4),
    magenta: const Color(0xFF75507B),
    cyan: const Color(0xFF06989A),
    white: const Color(0xFFD3D7CF),
    brightBlack: const Color(0xFF555753),
    brightRed: const Color(0xFFEF2929),
    brightGreen: const Color(0xFF8AE234),
    brightYellow: const Color(0xFFFCE94F),
    brightBlue: const Color(0xFF729FCF),
    brightMagenta: const Color(0xFFAD7FA8),
    brightCyan: const Color(0xFF34E2E2),
    brightWhite: const Color(0xFFEEEEEC),
    searchHitBackground: const Color(0xFFFCE94F),
    searchHitBackgroundCurrent: const Color(0xFFE95420),
    searchHitForeground: Colors.black,
  );

  /// Mở tab terminal mới và tự động chạy một lệnh ngay sau khi shell sẵn sàng.
  void openPaneWithCommand(String command, String? workingDirectory) {
    if (!mounted) return;
    context.read<TerminalProvider>().openPaneWithCommand(command, workingDirectory);
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  void _addWindow({bool isSsh = false, ServerModel? srv}) {
    context.read<TerminalProvider>().addWindow(
      isSsh: isSsh,
      srv: srv,
    );
  }

  void _removeWindow(int index) {
    context.read<TerminalProvider>().removeWindow(index);
  }

  void _confirmCloseWindow(int index) {
    final panes = context.read<TerminalProvider>().panes;
    if (index < 0 || index >= panes.length) return;
    if (panes.length <= 1) {
      AppToast.warning(context, 'Không thể đóng tab terminal duy nhất');
      return;
    }
    final pane = panes[index];
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 400,
        maxWidth: 480,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Xác Nhận Đóng Tab'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn đóng tab terminal "${pane.title}" không? Tất cả các tiến trình đang chạy trong tab này sẽ kết thúc.',
          style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textBody),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textDim,
              side: const BorderSide(color: AppColors.borderDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.textWhite,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _removeWindow(index);
              if (mounted) {
                AppToast.success(context, 'Đã đóng tab terminal');
              }
            },
            child: const Text('Đóng Terminal'),
          ),
        ],
      ),
    );
  }

  void _splitActiveWindow(TerminalSplitDirection direction, int windowIndex, TerminalPaneItem targetPane) {
    context.read<TerminalProvider>().splitActiveWindow(direction, windowIndex, targetPane);
  }

  void _closeChildPane(int windowIndex) {
    context.read<TerminalProvider>().closeChildPane(windowIndex);
  }

  void _confirmCloseChildPane(int windowIndex) {
    final panes = context.read<TerminalProvider>().panes;
    if (windowIndex < 0 || windowIndex >= panes.length) return;
    final windowPane = panes[windowIndex];
    if (windowPane.childPane == null) return;
    final childTitle = windowPane.childPane!.title;

    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 400,
        maxWidth: 480,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Xác Nhận Đóng Khung Phụ'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn đóng khung terminal phụ "$childTitle" không? Tiến trình đang chạy trong khung này sẽ bị dừng.',
          style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textBody),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textDim,
              side: const BorderSide(color: AppColors.borderDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.textWhite,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _closeChildPane(windowIndex);
              if (mounted) {
                AppToast.success(context, 'Đã đóng khung terminal phụ');
              }
            },
            child: const Text('Đóng Khung Phụ'),
          ),
        ],
      ),
    );
  }

  void _showRenameTabDialog(int index) {
    final panes = context.read<TerminalProvider>().panes;
    if (index < 0 || index >= panes.length) return;
    final windowPane = panes[index];
    final titleCtrl = TextEditingController(text: windowPane.title);

    void doSubmit(BuildContext ctx) {
      final newTitle = titleCtrl.text.trim();
      Navigator.pop(ctx);
      if (newTitle.isNotEmpty && newTitle != windowPane.title) {
        context.read<TerminalProvider>().renamePane(index, newTitle);
        if (mounted) {
          AppToast.success(context, 'Đã đổi tên Tab ${index + 1} thành "$newTitle"!');
        }
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 400,
        maxWidth: 480,
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppColors.accentCyan, size: 20),
            const SizedBox(width: 8),
            Text('Đổi Tên Tab ${index + 1}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập tên gợi nhớ mới cho tab terminal:',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
              onSubmitted: (_) => doSubmit(ctx),
              decoration: InputDecoration(
                hintText: 'Ví dụ: Backend Server, Docker Logs, Local Dev...',
                prefixIcon: const Icon(Icons.terminal_rounded, size: 16, color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.bgDark,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  borderSide: const BorderSide(color: AppColors.accentCyan, width: 1.2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textDim,
              side: const BorderSide(color: AppColors.borderDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            onPressed: () => doSubmit(ctx),
            icon: const Icon(Icons.check_rounded, size: 14),
            label: const Text('Lưu Tên Tab'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textWhite,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset position,
    int windowIndex,
    TerminalPaneItem pane,
    ServerProvider serverProvider, {
    bool isChild = false,
  }) async {
    final terminalProvider = context.read<TerminalProvider>();
    final panes = terminalProvider.panes;
    if (windowIndex < 0 || windowIndex >= panes.length) return;
    final windowPane = panes[windowIndex];

    terminalProvider.setActivePaneIndex(windowIndex);
    if (isChild) {
      terminalProvider.setActiveSubPaneId(pane.id);
    }
    pane.focusNode.requestFocus();

    final isCurrentlySplit = windowPane.splitDirection != TerminalSplitDirection.none && windowPane.childPane != null;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      elevation: 10,
      items: [
        // 1. SPLIT CHO CHÍNH CỬA SỔ HIỆN TẠI (WINDOW SPECIFIC)
        const PopupMenuItem<String>(
          enabled: false,
          height: 26,
          child: Text('CHIA KHUNG CỬA SỔ NÀY (SPLIT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
        ),
        PopupMenuItem<String>(
          value: 'split_none',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.crop_square_rounded, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Khung đơn (Không chia)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (!isCurrentlySplit) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split_horizontal',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.view_column_outlined, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Chia đôi: Trái / Phải', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (isCurrentlySplit && windowPane.splitDirection == TerminalSplitDirection.horizontal) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split_vertical',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.view_agenda_outlined, size: 15, color: AppColors.textBody),
              const SizedBox(width: 8),
              const Text('Chia đôi: Trên / Dưới', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
              if (isCurrentlySplit && windowPane.splitDirection == TerminalSplitDirection.vertical) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(height: 10),

        // 2. THAO TÁC TERMINAL
        PopupMenuItem<String>(
          value: 'set_directory',
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 15, color: AppColors.accentCyan),
              const SizedBox(width: 8),
              Text(
                pane.workingDirectory != null && pane.workingDirectory!.isNotEmpty
                    ? 'Đổi thư mục: .../${pane.workingDirectory!.split(Platform.isWindows ? r'\' : '/').where((p) => p.isNotEmpty).last}'
                    : 'Chọn thư mục làm việc (cd)',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'restart_pane',
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.refresh_rounded, size: 15, color: AppColors.textDim),
              SizedBox(width: 8),
              Text('Khởi động lại Terminal này', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clear_pane',
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.cleaning_services_rounded, size: 15, color: AppColors.textDim),
              SizedBox(width: 8),
              Text('Xoá sạch màn hình (Clear)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
            ],
          ),
        ),

        // 3. ĐÓNG PANEL / WINDOW
        if (isChild) ...[
          const PopupMenuDivider(height: 10),
          const PopupMenuItem<String>(
            value: 'close_subpane',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.close_fullscreen_rounded, size: 15, color: AppColors.warning),
                SizedBox(width: 8),
                Text('Đóng khung phụ (Huỷ Split)', style: TextStyle(fontSize: 12, color: AppColors.warning)),
              ],
            ),
          ),
        ] else if (panes.length > 1) ...[
          const PopupMenuDivider(height: 10),
          const PopupMenuItem<String>(
            value: 'close_window',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.close_rounded, size: 15, color: AppColors.danger),
                SizedBox(width: 8),
                Text('Đóng Tab cửa sổ này', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ],
    );

    if (result == null) return;

    if (result == 'set_directory') {
      _pickDirectoryForPane(pane);
    } else if (result == 'split_none') {
      _splitActiveWindow(TerminalSplitDirection.none, windowIndex, pane);
    } else if (result == 'split_horizontal') {
      _splitActiveWindow(TerminalSplitDirection.horizontal, windowIndex, pane);
    } else if (result == 'split_vertical') {
      _splitActiveWindow(TerminalSplitDirection.vertical, windowIndex, pane);
    } else if (result == 'restart_pane') {
      terminalProvider.connectPane(pane);
    } else if (result == 'clear_pane') {
      pane.terminal.eraseDisplay();
      pane.terminal.setCursor(0, 0);
    } else if (result == 'close_subpane') {
      _confirmCloseChildPane(windowIndex);
    } else if (result == 'close_window') {
      _confirmCloseWindow(windowIndex);
    }
  }

  Future<void> _pickDirectoryForPane(TerminalPaneItem pane) async {
    try {
      final initial = (pane.workingDirectory != null && Directory(pane.workingDirectory!).existsSync())
          ? pane.workingDirectory
          : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Chọn thư mục làm việc cho Terminal',
        initialDirectory: initial,
      );
      if (selected != null && selected.isNotEmpty && mounted) {
        await context.read<TerminalProvider>().setDirectoryForPane(pane, selected);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final terminalProvider = context.watch<TerminalProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final panes = terminalProvider.panes;
    final activePaneIndex = terminalProvider.activePaneIndex;
    final activePane = terminalProvider.activePane;
    final showVirtualKeyboard = terminalProvider.showVirtualKeyboard;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Window Tabs Bar & Actions (Tối giản, phẳng, không chiếm diện tích)
          Container(
            height: 38,
            padding: const EdgeInsets.only(left: 10, right: 10),
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const MaterialScrollBehavior().copyWith(
                      dragDevices: {
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.touch,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: ListView.builder(
                      controller: _tabScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: panes.length,
                      itemBuilder: (ctx, index) {
                        final window = panes[index];
                        final isWinActive = activePaneIndex == index;
                        final isSplit = window.splitDirection != TerminalSplitDirection.none && window.childPane != null;

                        return Container(
                          margin: const EdgeInsets.only(right: 4, top: 4, bottom: 0),
                          height: 34,
                          child: Material(
                            color: isWinActive ? AppColors.bgDark : AppColors.sidebarBg.withValues(alpha: 0.6),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                            child: InkWell(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                topRight: Radius.circular(6),
                              ),
                              onTap: () {
                                terminalProvider.setActivePaneIndex(index);
                                window.focusNode.requestFocus();
                              },
                              onDoubleTap: () => _showRenameTabDialog(index),
                              child: Container(
                                height: 34,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: window.isConnected ? AppColors.accent : (window.isConnecting ? AppColors.warning : AppColors.danger),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      window.isRemoteSsh ? Icons.dns_rounded : Icons.laptop_chromebook_rounded,
                                      size: 13,
                                      color: window.isRemoteSsh ? AppColors.primaryLight : AppColors.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Click đúp để đổi tên tab',
                                      child: Text(
                                        'Tab ${index + 1}: ${window.title}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: isWinActive ? FontWeight.bold : FontWeight.normal,
                                          color: isWinActive ? AppColors.textWhite : AppColors.textDim,
                                        ),
                                      ),
                                    ),
                                    if (isSplit) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentCyan.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          window.splitDirection == TerminalSplitDirection.horizontal ? 'SPLIT H' : 'SPLIT V',
                                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                                        ),
                                      ),
                                    ],
                                    if (panes.length > 1) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => _confirmCloseWindow(index),
                                        borderRadius: BorderRadius.circular(10),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2),
                                          child: Icon(Icons.close_rounded, size: 12, color: AppColors.textDim),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Nút tạo Tab Cửa Sổ Mới (Đồng bộ height 34px, sát bottom = 0)
                if (panes.length < 6)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 0),
                    height: 34,
                    child: PopupMenuButton<String>(
                      tooltip: 'Mở thêm Tab Cửa Sổ Terminal mới',
                      offset: const Offset(0, 34),
                      color: AppColors.cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                      onSelected: (val) {
                        if (val == 'new_local') {
                          _addWindow(isSsh: false);
                        } else if (val.startsWith('new_ssh_')) {
                          final srvId = val.replaceFirst('new_ssh_', '');
                          final srv = serverProvider.servers.firstWhere((s) => s.id == srvId, orElse: () => serverProvider.servers.first);
                          _addWindow(isSsh: true, srv: srv);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem<String>(
                          value: 'new_local',
                          child: Row(
                            children: [
                              Icon(Icons.laptop_chromebook_rounded, size: 14, color: AppColors.accent),
                              SizedBox(width: 8),
                              Text('Thêm Tab Local Machine', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                            ],
                          ),
                        ),
                        for (final s in serverProvider.servers)
                          PopupMenuItem<String>(
                            value: 'new_ssh_${s.id}',
                            child: Row(
                              children: [
                                const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
                                const SizedBox(width: 8),
                                Text('Thêm Tab SSH: ${s.name}', style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        height: 34,
                        width: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                          border: const Border(
                            top: BorderSide(color: Color(0x660D9488), width: 0.8),
                            left: BorderSide(color: Color(0x660D9488), width: 0.8),
                            right: BorderSide(color: Color(0x660D9488), width: 0.8),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.add_rounded, size: 16, color: AppColors.primaryLight),
                      ),
                    ),
                  ),
                if (widget.onHidePanel != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 0),
                    height: 34,
                    width: 34,
                    decoration: BoxDecoration(
                      color: AppColors.sidebarBg.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                      ),
                      border: const Border(
                        top: BorderSide(color: AppColors.borderDark, width: 0.8),
                        left: BorderSide(color: AppColors.borderDark, width: 0.8),
                        right: BorderSide(color: AppColors.borderDark, width: 0.8),
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Ẩn Terminal',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 16, color: AppColors.textDim),
                      hoverColor: AppColors.primary.withValues(alpha: 0.15),
                      onPressed: widget.onHidePanel,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. Virtual Key Bar (Optional)
          if (showVirtualKeyboard)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.cardBg,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildKeyBtn('ESC', '\x1b'),
                    _buildKeyBtn('TAB', '\t'),
                    _buildKeyBtn('CTRL+C', '\x03', isHighlight: true),
                    _buildKeyBtn('CTRL+D', '\x04'),
                    _buildKeyBtn('CTRL+Z', '\x1a'),
                    _buildKeyBtn('CTRL+L', '\x0c'),
                    _buildKeyBtn('▲', '\x1b[A'),
                    _buildKeyBtn('▼', '\x1b[B'),
                    _buildKeyBtn('◀', '\x1b[D'),
                    _buildKeyBtn('▶', '\x1b[C'),
                    _buildKeyBtn('HOME', '\x1b[H'),
                    _buildKeyBtn('END', '\x1b[F'),
                    _buildKeyBtn('PAGE UP', '\x1b[5~'),
                    _buildKeyBtn('PAGE DOWN', '\x1b[6~'),
                  ],
                ),
              ),
            ),

          // 4. MAIN TERMINAL SPLIT WORKSPACE
          Expanded(
            child: Container(
              color: AppColors.bgDark,
              padding: EdgeInsets.zero,
              child: _buildSplitWorkspace(terminalProvider, serverProvider),
            ),
          ),

          // 5. TERMINAL FOOTER BAR (Chứa 3 nút tiện ích: Phím ảo, Khởi động lại, Xóa màn hình)
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                // Thông tin nhanh shell hoặc trạng thái
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: (activePane?.isConnected ?? false) ? AppColors.accent : (activePane?.isConnecting == true ? AppColors.warning : AppColors.danger),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (activePane?.isRemoteSsh == true)
                          ? 'SSH: ${activePane?.server?.name ?? 'Server'}'
                          : 'Local Shell (${Platform.operatingSystem})',
                      style: const TextStyle(fontSize: 11, color: AppColors.textDim, fontFamily: 'monospace'),
                    ),
                  ],
                ),

                const Spacer(),

                // 1. Phím ảo
                IconButton(
                  icon: Icon(
                    showVirtualKeyboard ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
                    color: showVirtualKeyboard ? AppColors.accentCyan : AppColors.textDim,
                    size: 16,
                  ),
                  tooltip: showVirtualKeyboard ? 'Ẩn phím ảo' : 'Hiện phím ảo',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => terminalProvider.toggleVirtualKeyboard(),
                ),

                const SizedBox(width: 4),

                // 2. Khởi động lại
                IconButton(
                  icon: (activePane?.isConnecting == true)
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                        )
                      : Icon(
                          (activePane?.isConnected ?? false) ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                          color: (activePane?.isConnected ?? false) ? AppColors.accent : AppColors.warning,
                          size: 16,
                        ),
                  tooltip: 'Khởi động lại Terminal đang chọn',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: activePane != null ? () => terminalProvider.connectPane(activePane) : null,
                ),

                const SizedBox(width: 4),

                // 3. Xoá màn hình
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppColors.textDim),
                  tooltip: 'Xoá màn hình',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    activePane?.terminal.eraseDisplay();
                    activePane?.terminal.setCursor(0, 0);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitWorkspace(TerminalProvider terminalProvider, ServerProvider serverProvider) {
    final panes = terminalProvider.panes;
    if (panes.isEmpty) {
      return const Center(child: Text('Không có Terminal nào', style: TextStyle(color: AppColors.textMuted)));
    }

    final activeIndex = (terminalProvider.activePaneIndex >= 0 && terminalProvider.activePaneIndex < panes.length)
        ? terminalProvider.activePaneIndex
        : 0;
    final activeWindow = panes[activeIndex];

    // Nếu active window không split
    if (activeWindow.splitDirection == TerminalSplitDirection.none || activeWindow.childPane == null) {
      return _buildPaneCard(
        terminalProvider,
        activeWindow,
        activeIndex,
        serverProvider,
        isChild: false,
        isOnlyOne: true,
      );
    }

    // Nếu active window được split
    final mainCard = _buildPaneCard(terminalProvider, activeWindow, activeIndex, serverProvider, isChild: false);
    final childCard = _buildPaneCard(terminalProvider, activeWindow.childPane!, activeIndex, serverProvider, isChild: true);

    if (activeWindow.splitDirection == TerminalSplitDirection.horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: mainCard),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.borderDark),
          Expanded(child: childCard),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: mainCard),
        const Divider(height: 1, thickness: 1, color: AppColors.borderDark),
        Expanded(child: childCard),
      ],
    );
  }

  Widget _buildPaneCard(
    TerminalProvider terminalProvider,
    TerminalPaneItem pane,
    int windowIndex,
    ServerProvider serverProvider, {
    bool isChild = false,
    bool isOnlyOne = false,
  }) {
    final activeSubPaneId = terminalProvider.activeSubPaneId;
    final isThisPaneActive = isChild ? (activeSubPaneId == pane.id) : (activeSubPaneId == null);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (terminalProvider.activePaneIndex != windowIndex || (isChild ? activeSubPaneId != pane.id : activeSubPaneId != null)) {
          terminalProvider.setActivePaneIndex(windowIndex);
          if (isChild) {
            terminalProvider.setActiveSubPaneId(pane.id);
          }
        }
        if (!pane.focusNode.hasFocus) {
          pane.focusNode.requestFocus();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (terminalProvider.activePaneIndex != windowIndex || (isChild ? activeSubPaneId != pane.id : activeSubPaneId != null)) {
            terminalProvider.setActivePaneIndex(windowIndex);
            if (isChild) {
              terminalProvider.setActiveSubPaneId(pane.id);
            }
          }
          pane.focusNode.requestFocus();
        },
        onSecondaryTapDown: (details) => _showContextMenu(
          context,
          details.globalPosition,
          windowIndex,
          pane,
          serverProvider,
          isChild: isChild,
        ),
        child: Container(
          color: AppColors.bgDark,
          child: Column(
            children: [
              // Sub-Header for each pane
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  color: AppColors.cardBg,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.borderDark,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: pane.isConnected ? AppColors.accent : (pane.isConnecting ? AppColors.warning : AppColors.danger),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Pane Mode Switcher Dropdown
                        PopupMenuButton<String>(
                          tooltip: 'Đổi môi trường cho Panel này',
                          offset: const Offset(0, 30),
                          color: AppColors.cardBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                            side: const BorderSide(color: AppColors.borderDark),
                          ),
                          onSelected: (val) {
                            terminalProvider.setActivePaneIndex(windowIndex);
                            if (isChild) {
                              terminalProvider.setActiveSubPaneId(pane.id);
                            }
                            if (val == 'local') {
                              pane.isRemoteSsh = false;
                              pane.server = null;
                              pane.title = 'Local Machine';
                            } else {
                              final srv = serverProvider.servers.firstWhere((s) => s.id == val, orElse: () => serverProvider.servers.first);
                              pane.isRemoteSsh = true;
                              pane.server = srv;
                              pane.title = srv.name;
                            }
                            terminalProvider.connectPane(pane);
                            terminalProvider.saveTerminalSessions();
                          },
                          itemBuilder: (ctx) {
                            final items = <PopupMenuEntry<String>>[];
                            items.add(
                              PopupMenuItem<String>(
                                value: 'local',
                                child: Row(
                                  children: [
                                    const Icon(Icons.laptop_chromebook_rounded, size: 14, color: AppColors.accent),
                                    const SizedBox(width: 8),
                                    const Text('Local Machine', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                    if (!pane.isRemoteSsh) ...[
                                      const Spacer(),
                                      const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
                                    ],
                                  ],
                                ),
                              ),
                            );
                            if (serverProvider.servers.isNotEmpty) {
                              items.add(const PopupMenuDivider());
                              for (final s in serverProvider.servers) {
                                final isSel = pane.isRemoteSsh && pane.server?.id == s.id;
                                items.add(
                                  PopupMenuItem<String>(
                                    value: s.id,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.dns_rounded, size: 14, color: AppColors.primaryLight),
                                        const SizedBox(width: 8),
                                        Text('SSH: ${s.name}', style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                        if (isSel) ...[
                                          const Spacer(),
                                          const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryLight),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }
                            }
                            return items;
                          },
                          child: Container(
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: pane.isRemoteSsh ? AppColors.primary.withValues(alpha: 0.2) : AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  pane.isRemoteSsh ? Icons.dns_rounded : Icons.laptop_chromebook_rounded,
                                  size: 12,
                                  color: pane.isRemoteSsh ? AppColors.primaryLight : AppColors.accent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  pane.isRemoteSsh ? 'SSH: ${pane.server?.name ?? 'Server'}' : 'Local Machine',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: pane.isRemoteSsh ? AppColors.primaryLight : AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.arrow_drop_down_rounded, size: 13, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        ),
                        if (pane.workingDirectory != null && pane.workingDirectory!.trim().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _pickDirectoryForPane(pane),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              height: 24,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: AppColors.sidebarBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.borderDark, width: 0.8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(Icons.folder_open_rounded, size: 11, color: AppColors.accentCyan),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      pane.workingDirectory!.split(Platform.isWindows ? r'\' : '/').where((p) => p.isNotEmpty).isEmpty
                                          ? pane.workingDirectory!
                                          : pane.workingDirectory!.split(Platform.isWindows ? r'\' : '/').where((p) => p.isNotEmpty).last,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: AppColors.textDim,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    Row(
                      children: [
                        if (isThisPaneActive)
                          Container(
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.accent.withValues(alpha: 0.6), width: 0.8),
                            ),
                            alignment: Alignment.center,
                            child: const Text('ĐANG CHỌN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accent)),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, size: 14, color: AppColors.textDim),
                          tooltip: 'Menu tuỳ chọn (Chuột phải)',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () {
                            final RenderBox box = context.findRenderObject() as RenderBox;
                            final pos = box.localToGlobal(Offset.zero);
                            _showContextMenu(
                              context,
                              Offset(pos.dx + box.size.width - 200, pos.dy + 100),
                              windowIndex,
                              pane,
                              serverProvider,
                              isChild: isChild,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
                          tooltip: 'Khởi động lại terminal này',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () => terminalProvider.connectPane(pane),
                        ),
                        if (isChild)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                            tooltip: 'Đóng khung phụ này (Huỷ split)',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => _confirmCloseChildPane(windowIndex),
                          )
                        else if (!isOnlyOne && terminalProvider.panes.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                            tooltip: 'Đóng Tab cửa sổ này',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => _confirmCloseWindow(windowIndex),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Terminal View (Chuẩn cấu hình hiển thị và con trỏ Ubuntu Terminal)
              Expanded(
                child: Scrollbar(
                  controller: pane.scrollController,
                  thumbVisibility: true,
                  trackVisibility: false,
                  interactive: true,
                  child: TerminalView(
                    pane.terminal,
                    controller: pane.controller,
                    scrollController: pane.scrollController,
                    focusNode: pane.focusNode,
                    theme: _terminalTheme,
                    cursorType: TerminalCursorType.block,
                    alwaysShowCursor: isThisPaneActive,
                    hardwareKeyboardOnly: Platform.isWindows || Platform.isLinux || Platform.isMacOS,
                    onTapUp: (_, _) {
                      if (terminalProvider.activePaneIndex != windowIndex || (isChild ? activeSubPaneId != pane.id : activeSubPaneId != null)) {
                        terminalProvider.setActivePaneIndex(windowIndex);
                        if (isChild) {
                          terminalProvider.setActiveSubPaneId(pane.id);
                        }
                      }
                      pane.focusNode.requestFocus();
                    },
                    padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6, right: 6),
                    textStyle: const TerminalStyle(
                      fontSize: 13.5,
                      fontFamily: 'Ubuntu Mono',
                      fontFamilyFallback: ['UbuntuMono', 'DejaVu Sans Mono', 'Liberation Mono', 'Consolas', 'Courier New', 'monospace'],
                      height: 1.2,
                    ),
                    autofocus: isThisPaneActive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyBtn(String label, String code, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isHighlight ? AppColors.danger.withValues(alpha: 0.2) : AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            HapticFeedback.lightImpact();
            context.read<TerminalProvider>().sendKeyToActive(code);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isHighlight ? AppColors.danger : AppColors.borderDark,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: isHighlight ? AppColors.danger : AppColors.textWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
