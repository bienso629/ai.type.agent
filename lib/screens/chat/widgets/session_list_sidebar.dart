import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/tadu_dialog.dart';
import '../../../models/chat_session.dart';
import '../../../models/server_model.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/server_provider.dart';

class SessionListSidebar extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onExpandRequested;
  final VoidCallback? onSessionSelected;

  const SessionListSidebar({
    super.key,
    this.isCollapsed = false,
    this.onExpandRequested,
    this.onSessionSelected,
  });

  @override
  State<SessionListSidebar> createState() => _SessionListSidebarState();
}

class _SessionListSidebarState extends State<SessionListSidebar> {
  final ApiService _apiService = ApiService();
  final TextEditingController _sessionSearchCtrl = TextEditingController();
  final FocusNode _sessionSearchFocusNode = FocusNode();
  bool _isSessionSearchOpen = false;
  String _sessionSearchQuery = '';

  final Map<String, List<String>> _sessionRecentQuestions = {};
  final Set<String> _loadingSessionQuestions = {};

  @override
  void dispose() {
    _sessionSearchCtrl.dispose();
    _sessionSearchFocusNode.dispose();
    super.dispose();
  }

  void _loadRecentQuestionsForSession(String sessionId, {bool forceReload = false}) async {
    if (!forceReload && _sessionRecentQuestions.containsKey(sessionId)) {
      return;
    }
    if (_loadingSessionQuestions.contains(sessionId)) return;
    _loadingSessionQuestions.add(sessionId);

    try {
      final questions = await _apiService.getRecentUserQuestions(sessionId, limit: 6);
      if (mounted) {
        setState(() {
          _sessionRecentQuestions[sessionId] = questions;
          _loadingSessionQuestions.remove(sessionId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingSessionQuestions.remove(sessionId);
        });
      }
    }
  }

  String _formatSessionTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  void _showClearAllSessionsDialog(ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 420,
        maxWidth: 500,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Xác Nhận Xóa Tất Cả'),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa toàn bộ danh sách hội thoại và lịch sử chat không?',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await chat.deleteAllSessions();
              if (mounted) {
                AppToast.success(context, 'Đã xóa toàn bộ các cuộc hội thoại!');
              }
            },
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );
  }

  void _showEditSessionDialog(ChatProvider chat, ChatSessionModel sess) {
    final serverProvider = context.read<ServerProvider>();
    final titleCtrl = TextEditingController(text: sess.title);
    String selectedServer = (sess.targetServer != null && sess.targetServer!.isNotEmpty)
        ? sess.targetServer!
        : 'Local Machine';

    final serverOptions = <Map<String, dynamic>>[
      {
        'value': 'Local Machine',
        'label': 'Local Machine (Máy tính cục bộ)',
        'isLocal': true,
      },
    ];

    for (final s in serverProvider.servers) {
      if (s.serverIp != '127.0.0.1' && s.serverIp != 'localhost') {
        serverOptions.add({
          'value': s.name,
          'label': '${s.name} (${s.serverIp})',
          'isLocal': false,
        });
      }
    }

    if (!serverOptions.any((opt) => opt['value'] == selectedServer)) {
      selectedServer = 'Local Machine';
    }

    void doSubmit(BuildContext ctx) async {
      final newTitle = titleCtrl.text.trim();
      Navigator.pop(ctx);
      final finalTitle = newTitle.isNotEmpty ? newTitle : sess.title;
      await chat.updateSession(
        sess,
        newTitle: finalTitle,
        newTargetServer: selectedServer,
      );
      if (mounted) {
        AppToast.success(context, 'Đã cập nhật hộp hội thoại!');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => TaduDialog(
          minWidth: 460,
          maxWidth: 540,
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: AppColors.primaryLight, size: 22),
              SizedBox(width: 8),
              Text('Chỉnh Sửa Hộp Hội Thoại'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tiêu đề cuộc trò chuyện:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                onSubmitted: (_) => doSubmit(ctx),
                decoration: const InputDecoration(
                  labelText: 'Tiêu đề cuộc hội thoại',
                  prefixIcon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Máy chủ thực thi (Gắn kết phiên làm việc):', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: selectedServer,
                dropdownColor: AppColors.cardBg,
                decoration: const InputDecoration(
                  labelText: 'Chọn Máy Chủ',
                  prefixIcon: Icon(Icons.dns_rounded, size: 16),
                ),
                items: serverOptions.map((opt) {
                  final isLoc = opt['isLocal'] as bool;
                  return DropdownMenuItem<String>(
                    value: opt['value'] as String,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLoc ? Icons.laptop_chromebook_rounded : Icons.dns_rounded,
                          size: 15,
                          color: isLoc ? AppColors.accent : const Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          opt['label'] as String,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isLoc ? AppColors.accent : AppColors.textWhite,
                            fontWeight: isLoc ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      selectedServer = val;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => doSubmit(ctx),
              child: const Text('Lưu thay đổi'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(ChatProvider chat, dynamic sess) {
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 420,
        maxWidth: 500,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Xác Nhận Xóa Hội Thoại'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa vĩnh viễn cuộc hội thoại "${sess.title}" và toàn bộ tin nhắn liên quan không?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await chat.deleteSession(sess.id);
              if (mounted) {
                AppToast.success(context, 'Đã xóa cuộc hội thoại thành công!');
              }
            },
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final serverProvider = context.watch<ServerProvider>();

    if (widget.isCollapsed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_comment_rounded, size: 18, color: AppColors.primaryLight),
              tooltip: 'Tạo hội thoại mới',
              onPressed: () {
                chat.createNewSession(
                  targetServer: serverProvider.selectedServer?.name ?? 'Local Machine',
                );
              },
            ),
            const SizedBox(height: 6),
            IconButton(
              icon: const Icon(Icons.history_rounded, size: 18, color: AppColors.textDim),
              tooltip: 'Mở rộng để xem danh sách hội thoại (${chat.sessions.length})',
              onPressed: widget.onExpandRequested,
            ),
          ],
        ),
      );
    }

    final query = _sessionSearchQuery.trim().toLowerCase();
    final displaySessions = query.isEmpty
        ? chat.sessions
        : chat.sessions.where((s) {
            final titleMatch = s.title.toLowerCase().contains(query);
            final serverMatch = (s.targetServer ?? '').toLowerCase().contains(query);
            final dirMatch = (s.workingDirScope ?? '').toLowerCase().contains(query);
            return titleMatch || serverMatch || dirMatch;
          }).toList();

    return Column(
      children: [
        // 1. Header with inline expandable Search Box & Add Session Button
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 0.8)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: _isSessionSearchOpen
                ? Row(
                    key: const ValueKey('search_open'),
                    children: [
                      Expanded(
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.borderDark.withValues(alpha: 0.7)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_rounded, size: 13, color: AppColors.textMuted),
                              const SizedBox(width: 5),
                              Expanded(
                                child: TextField(
                                  focusNode: _sessionSearchFocusNode,
                                  controller: _sessionSearchCtrl,
                                  onChanged: (val) => setState(() => _sessionSearchQuery = val),
                                  textAlignVertical: TextAlignVertical.center,
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite),
                                  decoration: const InputDecoration(
                                    hintText: 'Tìm kiếm hội thoại...',
                                    hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                                  ),
                                ),
                              ),
                              InkWell(
                                hoverColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                onTap: () {
                                  setState(() {
                                    _sessionSearchCtrl.clear();
                                    _sessionSearchQuery = '';
                                    _isSessionSearchOpen = false;
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.close_rounded, size: 13, color: AppColors.textDim),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.primaryLight),
                        tooltip: 'Tạo hội thoại mới',
                        onPressed: () => chat.createNewSession(
                          targetServer: serverProvider.selectedServer?.name ?? 'Local Machine',
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('search_closed'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.layers_rounded, size: 15, color: AppColors.primaryLight),
                          SizedBox(width: 8),
                          Text(
                            'Hộp Hội Thoại',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            icon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textDim),
                            tooltip: 'Tìm kiếm hội thoại',
                            onPressed: () {
                              setState(() {
                                _isSessionSearchOpen = true;
                                Future.delayed(const Duration(milliseconds: 60), () {
                                  if (mounted) _sessionSearchFocusNode.requestFocus();
                                });
                              });
                            },
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.primaryLight),
                            tooltip: 'Tạo hội thoại mới',
                            onPressed: () {
                              widget.onSessionSelected?.call();
                              chat.createNewSession(
                                targetServer: serverProvider.selectedServer?.name ?? 'Local Machine',
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),

        // 2. Session List
        Expanded(
          child: chat.sessions.isEmpty
              ? const Center(
                  child: Text('Chưa có hội thoại nào', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                )
              : displaySessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 26, color: AppColors.textDim),
                            const SizedBox(height: 6),
                            Text(
                              'Không tìm thấy hội thoại nào khớp với "$_sessionSearchQuery"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final yesterday = today.subtract(const Duration(days: 1));

                        final todaySessions = <ChatSessionModel>[];
                        final yesterdaySessions = <ChatSessionModel>[];
                        final olderSessions = <ChatSessionModel>[];

                        for (final sess in displaySessions) {
                          final sessDate = DateTime(sess.updatedAt.year, sess.updatedAt.month, sess.updatedAt.day);
                          if (sessDate.isAtSameMomentAs(today) || sessDate.isAfter(today)) {
                            todaySessions.add(sess);
                          } else if (sessDate.isAtSameMomentAs(yesterday)) {
                            yesterdaySessions.add(sess);
                          } else {
                            olderSessions.add(sess);
                          }
                        }

                        Widget buildSessionTile(ChatSessionModel sess) {
                          final isSelected = sess.id == chat.currentSession?.id;
                          final recentQuestions = _sessionRecentQuestions[sess.id] ?? [];
                          final isLoadingQuestions = _loadingSessionQuestions.contains(sess.id);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : (sess.isPinned ? AppColors.warning.withValues(alpha: 0.04) : Colors.transparent),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.5)
                                    : (sess.isPinned ? AppColors.warning.withValues(alpha: 0.25) : AppColors.borderDark.withValues(alpha: 0.3)),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: _SwipeableSessionItem(
                                    key: ValueKey('swipe_${sess.id}'),
                                    onEdit: () => _showEditSessionDialog(chat, sess),
                                    onDelete: () => _showDeleteDialog(chat, sess),
                                    backgroundColor: isSelected
                                        ? const Color(0xFF132733)
                                        : (sess.isPinned ? const Color(0xFF1B1A1E) : AppColors.sidebarBg),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        hoverColor: Colors.transparent,
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        onTap: () {
                                          widget.onSessionSelected?.call();
                                          if (chat.currentSession?.id == sess.id) return;
                                          chat.selectSession(sess);
                                          _loadRecentQuestionsForSession(sess.id);
                                          if (sess.targetServer != null && sess.targetServer!.isNotEmpty) {
                                            if (sess.targetServer == 'Local Machine' || sess.targetServer == 'Local' || sess.targetServer == '127.0.0.1') {
                                              if (serverProvider.selectedServer?.id != 'local') {
                                                serverProvider.selectServer(ServerModel(id: 'local', name: 'Local Machine', serverIp: '127.0.0.1'));
                                              }
                                            } else {
                                              final matches = serverProvider.servers.where((s) => s.name == sess.targetServer || s.id == sess.targetServer || s.serverIp == sess.targetServer);
                                              if (matches.isNotEmpty && serverProvider.selectedServer?.id != matches.first.id) {
                                                serverProvider.selectServer(matches.first);
                                              }
                                            }
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                          child: Row(
                                            children: [
                                              // Pin Button
                                              IconButton(
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                                hoverColor: Colors.transparent,
                                                splashColor: Colors.transparent,
                                                highlightColor: Colors.transparent,
                                                icon: Transform.rotate(
                                                  angle: sess.isPinned ? -0.5 : 0,
                                                  child: Icon(
                                                    sess.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                                    size: 12.5,
                                                    color: sess.isPinned ? AppColors.warning : AppColors.textDim,
                                                  ),
                                                ),
                                                tooltip: sess.isPinned ? 'Bỏ ghim hội thoại' : 'Ghim hội thoại lên đầu',
                                                onPressed: () async {
                                                  final success = await chat.pinSession(sess);
                                                  if (!success && context.mounted) {
                                                    AppToast.warning(context, 'Chỉ được ghim tối đa 3 hộp hội thoại lên đầu');
                                                  }
                                                },
                                              ),
                                              const SizedBox(width: 4),
                                              // Session Details
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            sess.title,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                              color: isSelected ? AppColors.primaryLight : AppColors.textBody,
                                                            ),
                                                          ),
                                                        ),
                                                        if (chat.isSessionGenerating(sess.id)) ...[
                                                          const SizedBox(width: 4),
                                                          const SizedBox(
                                                            width: 9,
                                                            height: 9,
                                                            child: CircularProgressIndicator(
                                                              strokeWidth: 1.5,
                                                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        if (sess.isPinned)
                                                          Container(
                                                            height: 16,
                                                            margin: const EdgeInsets.only(right: 6),
                                                            padding: const EdgeInsets.symmetric(horizontal: 5),
                                                            alignment: Alignment.center,
                                                            decoration: BoxDecoration(
                                                              color: AppColors.warning.withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(4),
                                                              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                                            ),
                                                            child: const Text(
                                                              'Ghim',
                                                              style: TextStyle(fontSize: 8.5, height: 1.1, fontWeight: FontWeight.bold, color: AppColors.warning),
                                                            ),
                                                          ),
                                                        // Target Server Badge
                                                        Builder(
                                                          builder: (context) {
                                                            final serverName = (sess.targetServer != null && sess.targetServer!.isNotEmpty)
                                                                ? sess.targetServer!
                                                                : 'Local Machine';
                                                            final isLocal = serverName == 'Local Machine' ||
                                                                serverName == 'Local' ||
                                                                serverName == 'localhost' ||
                                                                serverName == '127.0.0.1';
                                                            final badgeColor = isLocal ? AppColors.accent : const Color(0xFF38BDF8);

                                                            return Container(
                                                              height: 16,
                                                              margin: const EdgeInsets.only(right: 6),
                                                              padding: const EdgeInsets.symmetric(horizontal: 5),
                                                              alignment: Alignment.center,
                                                              decoration: BoxDecoration(
                                                                color: badgeColor.withValues(alpha: 0.12),
                                                                borderRadius: BorderRadius.circular(4),
                                                                border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                                                              ),
                                                              child: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                                children: [
                                                                  Icon(
                                                                    isLocal ? Icons.laptop_chromebook_rounded : Icons.dns_rounded,
                                                                    size: 9.5,
                                                                    color: badgeColor,
                                                                  ),
                                                                  const SizedBox(width: 3),
                                                                  ConstrainedBox(
                                                                    constraints: const BoxConstraints(maxWidth: 80),
                                                                    child: Text(
                                                                      serverName,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: TextStyle(
                                                                        fontSize: 8.5,
                                                                        height: 1.1,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: badgeColor,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                        // Q&A Count Badge
                                                        Container(
                                                          height: 16,
                                                          margin: const EdgeInsets.only(right: 6),
                                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                                          alignment: Alignment.center,
                                                          decoration: BoxDecoration(
                                                            color: AppColors.primary.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.35)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            crossAxisAlignment: CrossAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                '${sess.questionCount}',
                                                                style: const TextStyle(fontSize: 9, height: 1.1, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                                              ),
                                                              const Padding(
                                                                padding: EdgeInsets.symmetric(horizontal: 3),
                                                                child: Text(
                                                                  '/',
                                                                  style: TextStyle(fontSize: 8.5, height: 1.1, color: AppColors.textDim),
                                                                ),
                                                              ),
                                                              Text(
                                                                '${sess.answerCount}',
                                                                style: const TextStyle(fontSize: 9, height: 1.1, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Text(
                                                          _formatSessionTime(sess.updatedAt),
                                                          style: const TextStyle(fontSize: 9.5, color: AppColors.textDim),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Expanded Section: Recent Questions List
                                if (isSelected) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(left: 10, right: 8, top: 4, bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.bgDark.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderDark.withValues(alpha: 0.6)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.history_rounded, size: 12, color: AppColors.accentCyan),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'Câu hỏi gần đây (${sess.questionCount} câu)',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.accentCyan,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (isLoadingQuestions)
                                              const SizedBox(
                                                width: 9,
                                                height: 9,
                                                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accentCyan),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (isLoadingQuestions && recentQuestions.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 4),
                                            child: Text('Đang tải câu hỏi...', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                                          )
                                        else if (recentQuestions.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 4),
                                            child: Text('Chưa có câu hỏi nào trong hộp này.', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                                          )
                                        else
                                          ...recentQuestions.map((q) {
                                            return _RecentQuestionItem(
                                              question: q,
                                              session: sess,
                                              onTap: () {
                                                widget.onSessionSelected?.call();
                                                if (sess.id != chat.currentSession?.id) {
                                                  chat.selectSession(sess);
                                                }
                                              },
                                              onCopy: () {
                                                Clipboard.setData(ClipboardData(text: q));
                                                AppToast.success(context, 'Đã sao chép câu hỏi vào bộ nhớ tạm!');
                                              },
                                              onReAsk: () async {
                                                widget.onSessionSelected?.call();
                                                if (sess.id != chat.currentSession?.id) {
                                                  await chat.selectSession(sess);
                                                }
                                                if (sess.targetServer != null && sess.targetServer!.isNotEmpty) {
                                                  if (sess.targetServer == 'Local Machine' || sess.targetServer == 'Local' || sess.targetServer == '127.0.0.1') {
                                                    serverProvider.selectServer(ServerModel(id: 'local', name: 'Local Machine', serverIp: '127.0.0.1'));
                                                  } else {
                                                    final matches = serverProvider.servers.where((s) => s.name == sess.targetServer || s.id == sess.targetServer || s.serverIp == sess.targetServer);
                                                    if (matches.isNotEmpty) {
                                                      serverProvider.selectServer(matches.first);
                                                    }
                                                  }
                                                }
                                                chat.sendMessage(
                                                  q,
                                                  model: serverProvider.currentAiModel,
                                                  workingDir: chat.currentSessionScope,
                                                  targetServer: serverProvider.selectedServer?.name ?? 'Local Machine',
                                                );
                                              },
                                            );
                                          }),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }

                        Widget buildGroupSection(String title, List<ChatSessionModel> groupList) {
                          if (groupList.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 6, right: 6, top: 8, bottom: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      title.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textDim,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: AppColors.borderDark.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${groupList.length}',
                                      style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              ...groupList.map(buildSessionTile),
                            ],
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          children: [
                            buildGroupSection('Hôm nay', todaySessions),
                            buildGroupSection('Hôm qua', yesterdaySessions),
                            buildGroupSection('Lâu hơn', olderSessions),
                          ],
                        );
                      },
                    ),
        ),

        // 3. Footer with count and Clear All Button
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.8)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                query.isNotEmpty ? '${displaySessions.length}/${chat.sessions.length} hội thoại' : '${chat.sessions.length} hội thoại',
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
              if (chat.sessions.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showClearAllSessionsDialog(chat),
                  child: const Text('Xoá tất cả', style: TextStyle(fontSize: 11, color: AppColors.danger)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentQuestionItem extends StatefulWidget {
  final String question;
  final ChatSessionModel session;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onReAsk;

  const _RecentQuestionItem({
    required this.question,
    required this.session,
    required this.onTap,
    required this.onCopy,
    required this.onReAsk,
  });

  @override
  State<_RecentQuestionItem> createState() => _RecentQuestionItemState();
}

class _RecentQuestionItemState extends State<_RecentQuestionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final textColor = _isHovered ? AppColors.accentCyan : AppColors.textBody;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Chọn phiên hội thoại',
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    widget.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor,
                      height: 1.35,
                      fontWeight: _isHovered ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Copy Button
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                icon: Icon(
                  Icons.copy_rounded,
                  size: 11.5,
                  color: _isHovered ? AppColors.textWhite : AppColors.textDim,
                ),
                tooltip: 'Sao chép câu hỏi',
                onPressed: widget.onCopy,
              ),
              const SizedBox(width: 2),
              // Re-ask Button
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                icon: const Icon(
                  Icons.replay_rounded,
                  size: 12,
                  color: AppColors.primaryLight,
                ),
                tooltip: 'Hỏi lại câu này ngay',
                onPressed: widget.onReAsk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeableSessionItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Color? backgroundColor;

  const _SwipeableSessionItem({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.backgroundColor,
  });

  @override
  State<_SwipeableSessionItem> createState() => _SwipeableSessionItemState();
}

class _SwipeableSessionItemState extends State<_SwipeableSessionItem> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  double _dragExtent = 0.0;
  static const double _maxActionWidth = 68.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _dragExtent = _animCtrl.value * -_maxActionWidth;
        });
      });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _open() {
    _animCtrl.animateTo(1.0, curve: Curves.easeOutCubic);
  }

  void _close() {
    _animCtrl.animateTo(0.0, curve: Curves.easeOutCubic);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent = (_dragExtent + details.primaryDelta!).clamp(-_maxActionWidth, 0.0);
      _animCtrl.value = -_dragExtent / _maxActionWidth;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity! < -200 || _dragExtent < -(_maxActionWidth / 2)) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? AppColors.sidebarBg;

    return MouseRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Background Action Buttons
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit Button
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.edit_outlined, size: 13, color: AppColors.primaryLight),
                        tooltip: 'Chỉnh sửa hội thoại',
                        onPressed: () {
                          _close();
                          widget.onEdit();
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Delete Button
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.delete_outline_rounded, size: 13, color: AppColors.danger),
                        tooltip: 'Xóa hội thoại',
                        onPressed: () {
                          _close();
                          widget.onDelete();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Foreground Content
            Transform.translate(
              offset: Offset(_dragExtent, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
