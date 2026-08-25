import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/chat_message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/server_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isRightSidebarOpen = true;
  String? _workingDirScope;

  String? _lastSessionId;
  String _lastTrackedContent = '';
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      if (chat.currentSession != null) {
        chat.selectSession(chat.currentSession!).then((_) {
          _safeScrollToBottom(instant: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 60) {
      final chat = context.read<ChatProvider>();
      if (chat.hasMoreMessages && !chat.isLoadingMore && !chat.isLoading) {
        final oldMaxScroll = _scrollController.position.maxScrollExtent;
        final oldPixels = _scrollController.position.pixels;
        chat.loadMoreMessages().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final newMaxScroll = _scrollController.position.maxScrollExtent;
              final diff = newMaxScroll - oldMaxScroll;
              if (diff > 0) {
                _scrollController.jumpTo(oldPixels + diff);
              }
            }
          });
        });
      }
    }
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_scrollController.hasClients) return;
    try {
      final target = _scrollController.position.maxScrollExtent + 200;
      if (instant) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
  }

  void _safeScrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollToBottom(instant: instant);
        Future.delayed(const Duration(milliseconds: 60), () {
          if (_scrollController.hasClients) {
            _scrollToBottom(instant: instant);
          }
        });
      }
    });
  }

  void _handleSend(ChatProvider chat, ServerProvider serverProvider) {
    final text = _textController.text.trim();
    if (text.isEmpty || chat.isGenerating) return;
    _textController.clear();
    chat.sendMessage(text, model: serverProvider.currentAiModel);
    _safeScrollToBottom();
  }

  void _triggerScopePicker() async {
    final textCtrl = TextEditingController(text: _workingDirScope ?? '/var/www');
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 480,
        maxWidth: 560,
        title: const Row(
          children: [
            Icon(Icons.folder_open_rounded, color: AppColors.warning, size: 20),
            SizedBox(width: 8),
            Text('Phạm Vi Thư Mục Làm Việc'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Giới hạn thao tác của AI Agent trong thư mục này trên máy chủ Linux:',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              decoration: const InputDecoration(
                hintText: '/var/www/my_project',
                prefixIcon: Icon(Icons.folder_rounded, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _workingDirScope = null;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Xóa giới hạn', style: TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _workingDirScope = textCtrl.text.trim().isEmpty ? null : textCtrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final serverProvider = context.watch<ServerProvider>();

    if (_lastSessionId != chat.currentSession?.id) {
      _lastSessionId = chat.currentSession?.id;
      _lastTrackedContent = '';
      _lastMessageCount = chat.messages.length;
      _safeScrollToBottom(instant: true);
    } else if (chat.isGenerating) {
      _safeScrollToBottom();
    } else if (chat.messages.length != _lastMessageCount ||
        (chat.messages.isNotEmpty && _lastTrackedContent != chat.messages.last.content)) {
      _lastMessageCount = chat.messages.length;
      _lastTrackedContent = chat.messages.isNotEmpty ? chat.messages.last.content : '';
      _safeScrollToBottom();
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. Topbar Header (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/logo.jpg',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.smart_toy_rounded, color: AppColors.primaryLight, size: 24),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.bgDark, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              chat.currentSession?.title ?? 'Tadu Cloud AI Assistant',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                serverProvider.currentAiModel,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Có quyền thực thi lệnh bash an toàn trên máy chủ Linux',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.view_sidebar_rounded,
                        color: _isRightSidebarOpen ? AppColors.primaryLight : AppColors.textDim,
                        size: 20,
                      ),
                      tooltip: 'Đóng/Mở danh sách hộp hội thoại',
                      onPressed: () {
                        setState(() {
                          _isRightSidebarOpen = !_isRightSidebarOpen;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Hội thoại mới', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => chat.createNewSession(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Chat Center & Right Sidebar Split View
          Expanded(
            child: Row(
              children: [
                // 2.1 Chat Center Feed
                Expanded(
                  child: Column(
                    children: [
                      // Message Stream
                      Expanded(
                        child: chat.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                itemCount: chat.hasMoreMessages
                                    ? chat.messages.length + 1
                                    : (chat.messages.isEmpty ? 1 : chat.messages.length + 1),
                                itemBuilder: (context, idx) {
                                  if (idx == 0) {
                                    if (chat.hasMoreMessages) {
                                      return _buildLoadMoreBanner(chat);
                                    }
                                    return _buildGreetingBubble(chat, serverProvider);
                                  }
                                  final msg = chat.messages[idx - 1];
                                  return _buildMessageItem(msg, chat);
                                },
                              ),
                      ),

                      // Status Progress Indicator Bar
                      if (chat.isGenerating)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: AppColors.sidebarBg,
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  chat.currentStatus.isNotEmpty ? chat.currentStatus : 'AI đang xử lý yêu cầu...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.primaryLight),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Input Bar
                      _buildInputBar(chat, serverProvider),
                    ],
                  ),
                ),

                // 2.2 Right Sidebar: Sessions List
                if (_isRightSidebarOpen) _buildRightSessionsSidebar(chat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreBanner(ChatProvider chat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      alignment: Alignment.center,
      child: chat.isLoadingMore
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sidebarBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Đang tải thêm 3 tin nhắn trước đó...',
                    style: TextStyle(fontSize: 11.5, color: AppColors.primaryLight),
                  ),
                ],
              ),
            )
          : InkWell(
              onTap: () => chat.loadMoreMessages(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 13, color: AppColors.textMuted),
                    SizedBox(width: 6),
                    Text(
                      'Cuộn lên hoặc bấm để tải thêm 3 tin nhắn cũ',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGreetingBubble(ChatProvider chat, ServerProvider serverProvider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: AppColors.primaryLight, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '👋 Xin chào! Tôi là Tadu Cloud AI Agent (${serverProvider.currentAiModel})',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tôi có thể giải đáp thắc mắc, phân tích hệ thống và tự động chạy lệnh Terminal khi bạn yêu cầu!',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const Divider(height: 20),
          const Text(
            'GỢI Ý CÂU LỆNH MẪU:',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textDim, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPromptChip(
                icon: Icons.pie_chart_rounded,
                iconColor: AppColors.accentCyan,
                label: 'Kiểm tra RAM & Ổ đĩa',
                prompt: 'Kiểm tra dung lượng ổ đĩa và RAM hiện tại',
                chat: chat,
              ),
              _buildPromptChip(
                icon: Icons.bolt_rounded,
                iconColor: AppColors.warning,
                label: 'Top tiến trình CPU',
                prompt: 'Xem danh sách tiến trình đang chạy và chiếm nhiều CPU nhất',
                chat: chat,
              ),
              _buildPromptChip(
                icon: Icons.lan_rounded,
                iconColor: AppColors.primaryLight,
                label: 'Cổng đang mở',
                prompt: 'Kiểm tra các cổng mạng đang mở (listening ports)',
                chat: chat,
              ),
              _buildPromptChip(
                icon: Icons.sync_rounded,
                iconColor: AppColors.accent,
                label: 'Trạng thái Services',
                prompt: 'Kiểm tra trạng thái service nginx và uvicorn',
                chat: chat,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromptChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String prompt,
    required ChatProvider chat,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.borderDark),
        backgroundColor: AppColors.inputBg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(icon, size: 14, color: iconColor),
      label: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textBody)),
      onPressed: () {
        chat.sendMessage(prompt);
        _safeScrollToBottom();
      },
    );
  }

  Widget _buildMessageItem(ChatMessageModel msg, ChatProvider chat) {
    final isUser = msg.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/logo.jpg',
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, size: 16, color: AppColors.primaryLight),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isUser
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.borderDark,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.content.isNotEmpty)
                        MarkdownBody(
                          data: msg.content,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 13.5, color: AppColors.textWhite, height: 1.55),
                            pPadding: const EdgeInsets.only(bottom: 6),
                            strong: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            em: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textBody),
                            h1: const TextStyle(fontSize: 15.0, fontWeight: FontWeight.bold, color: AppColors.textWhite, height: 1.35),
                            h1Padding: const EdgeInsets.only(top: 10, bottom: 5),
                            h2: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: AppColors.textWhite, height: 1.35),
                            h2Padding: const EdgeInsets.only(top: 9, bottom: 4),
                            h3: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.primaryLight, height: 1.3),
                            h3Padding: const EdgeInsets.only(top: 7, bottom: 4),
                            h4: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600, color: AppColors.textWhite, height: 1.3),
                            h4Padding: const EdgeInsets.only(top: 6, bottom: 3),
                            h5: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textWhite, height: 1.3),
                            h5Padding: const EdgeInsets.only(top: 4, bottom: 2),
                            h6: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.3),
                            h6Padding: const EdgeInsets.only(top: 4, bottom: 2),
                            blockSpacing: 8.0,
                            listBullet: const TextStyle(fontSize: 13.5, color: AppColors.primaryLight),
                            listBulletPadding: const EdgeInsets.only(right: 6, top: 1),
                            listIndent: 20.0,
                            code: const TextStyle(
                              fontFamily: 'monospace',
                              backgroundColor: AppColors.codeBg,
                              color: AppColors.terminalGreen,
                              fontSize: 12,
                            ),
                            codeblockPadding: const EdgeInsets.all(10),
                            codeblockDecoration: BoxDecoration(
                              color: AppColors.codeBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            blockquote: const TextStyle(fontSize: 13, color: AppColors.textBody, fontStyle: FontStyle.italic),
                            blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            blockquoteDecoration: BoxDecoration(
                              color: AppColors.inputBg,
                              borderRadius: BorderRadius.circular(4),
                              border: const Border(
                                left: BorderSide(color: AppColors.primaryLight, width: 3),
                              ),
                            ),
                            horizontalRuleDecoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
                            ),
                            tableBorder: TableBorder.all(
                              color: AppColors.borderDark,
                              width: 1.0,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            tableHead: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textWhite,
                            ),
                            tableBody: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textBody,
                            ),
                            tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            tableCellsDecoration: const BoxDecoration(
                              color: AppColors.inputBg,
                            ),
                          ),
                        ),

                      if (msg.content.isEmpty && msg.isStreaming)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                            ),
                            SizedBox(width: 8),
                            Text('Đang xử lý...', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),

                      if (msg.toolExecutions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...msg.toolExecutions.map((tool) => _buildToolCard(tool)),
                      ],
                    ],
                  ),
                ),

                // Message Action Bar (Timestamp, Copy, Retry)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 11, color: AppColors.textDim),
                      const SizedBox(width: 3),
                      Text(
                        _formatSessionTime(msg.createdAt),
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textDim, fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(3),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: msg.content));
                          AppToast.success(context, 'Đã sao chép nội dung vào bộ nhớ tạm!');
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.copy_rounded, size: 11, color: AppColors.textDim),
                              SizedBox(width: 3),
                              Text('Sao chép', style: TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                            ],
                          ),
                        ),
                      ),
                      if (!isUser) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(3),
                          onTap: () async {
                            final server = context.read<ServerProvider>().selectedServer;
                            final srvInfo = server != null ? '${server.sshUser}@${server.serverIp}' : null;
                            AppToast.info(context, 'Đang tạo và lưu tài liệu PDF chuẩn A4...');
                            try {
                              final path = await PdfExportService.exportMessageToPdf(msg, serverInfo: srvInfo);
                              if (mounted) {
                                AppToast.success(context, 'Đã lưu PDF tại Downloads: ${path?.split('/').last ?? ''}');
                              }
                            } catch (e) {
                              if (mounted) {
                                AppToast.error(context, 'Lỗi xuất PDF: $e');
                              }
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf_outlined, size: 11, color: AppColors.primaryLight),
                                SizedBox(width: 3),
                                Text('Tải PDF A4', style: TextStyle(fontSize: 10.5, color: AppColors.primaryLight, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (isUser) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(3),
                          onTap: () {
                            chat.sendMessage(msg.content);
                            _safeScrollToBottom();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.rotate_right_rounded, size: 12, color: AppColors.primaryLight),
                                SizedBox(width: 3),
                                Text('Hỏi lại', style: TextStyle(fontSize: 10.5, color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            Builder(
              builder: (ctx) {
                final auth = ctx.watch<AuthProvider>();
                final letter = (auth.userEmail?.isNotEmpty == true)
                    ? auth.userEmail![0].toUpperCase()
                    : 'U';
                return Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    letter,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryLight,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolCard(ToolExecutionItem tool) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.terminalBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tool.command,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          if (tool.output.isNotEmpty) ...[
            const Divider(color: AppColors.borderDark, height: 10),
            Text(
              tool.output.trim(),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatProvider chat, ServerProvider serverProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.bgDark,
        border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_workingDirScope != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 14, color: AppColors.accentCyan),
                    const SizedBox(width: 6),
                    const Text('Phạm vi Agent: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    Text(
                      _workingDirScope!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _workingDirScope = null;
                        });
                      },
                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _textController,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(chat, serverProvider),
              decoration: const InputDecoration(
                hintText: "Nhập yêu cầu, gõ '/' để chọn thư mục giới hạn...",
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.account_tree_rounded, size: 14, color: AppColors.warning),
                      label: const Text('Scope /', style: TextStyle(fontSize: 11, color: AppColors.textBody)),
                      onPressed: _triggerScopePicker,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.attach_file_rounded, size: 14, color: AppColors.accentCyan),
                      label: const Text('Attach', style: TextStyle(fontSize: 11, color: AppColors.textBody)),
                      onPressed: () {
                        AppToast.info(context, 'Chức năng đính kèm tệp đã sẵn sàng');
                      },
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 14),
                  label: const Text('Gửi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: chat.isGenerating ? null : () => _handleSend(chat, serverProvider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSessionTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  Widget _buildRightSessionsSidebar(ChatProvider chat) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(left: BorderSide(color: AppColors.borderDark, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.layers_rounded, size: 16, color: AppColors.primaryLight),
                    SizedBox(width: 8),
                    Text('Hộp Hội Thoại', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.primaryLight),
                  tooltip: 'Tạo hội thoại mới',
                  onPressed: () => chat.createNewSession(),
                ),
              ],
            ),
          ),
          Expanded(
            child: chat.sessions.isEmpty
                ? const Center(
                    child: Text('Chưa có hội thoại nào', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: chat.sessions.length,
                    itemBuilder: (context, idx) {
                      final sess = chat.sessions[idx];
                      final isSelected = sess.id == chat.currentSession?.id;

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
                                : (sess.isPinned ? AppColors.warning.withValues(alpha: 0.25) : Colors.transparent),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => chat.selectSession(sess).then((_) {
                              _scrollToBottom(instant: true);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Row(
                                children: [
                                  // Left Pin Button
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                    icon: Transform.rotate(
                                      angle: sess.isPinned ? -0.5 : 0,
                                      child: Icon(
                                        sess.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                        size: 13,
                                        color: sess.isPinned ? AppColors.warning : AppColors.textDim,
                                      ),
                                    ),
                                    tooltip: sess.isPinned ? 'Bỏ ghim hội thoại' : 'Ghim hội thoại lên đầu',
                                    onPressed: () => chat.pinSession(sess),
                                  ),
                                  const SizedBox(width: 4),
                                  // Session Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          sess.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? AppColors.primaryLight : AppColors.textBody,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (sess.isPinned)
                                              Container(
                                                margin: const EdgeInsets.only(right: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warning.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(2),
                                                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                                ),
                                                child: const Text(
                                                  'Ghim',
                                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.warning),
                                                ),
                                              ),
                                            Text(
                                              _formatSessionTime(sess.updatedAt),
                                              style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Rename Button
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                    icon: const Icon(Icons.edit_outlined, size: 13, color: AppColors.textDim),
                                    tooltip: 'Đổi tên hội thoại',
                                    onPressed: () => _showRenameDialog(chat, sess),
                                  ),
                                  // Delete Button
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 13, color: AppColors.textDim),
                                    tooltip: 'Xóa hộp hội thoại này',
                                    onPressed: () => _showDeleteDialog(chat, sess),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${chat.sessions.length} hội thoại', style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                TextButton(
                  onPressed: () => chat.clearHistory(),
                  child: const Text('Xoá chat', style: TextStyle(fontSize: 11, color: AppColors.danger)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(ChatProvider chat, dynamic sess) {
    final titleCtrl = TextEditingController(text: sess.title);
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 460,
        maxWidth: 540,
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppColors.primaryLight, size: 22),
            SizedBox(width: 8),
            Text('Đổi Tên Hộp Hội Thoại'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập tiêu đề mới cho cuộc trò chuyện:', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề cuộc hội thoại',
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = titleCtrl.text.trim();
              if (newTitle.isNotEmpty) {
                chat.renameSession(sess, newTitle);
                AppToast.success(context, 'Đã đổi tên hộp hội thoại!');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Lưu thay đổi'),
          ),
        ],
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
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 22),
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
            onPressed: () {
              chat.deleteSession(sess.id);
              AppToast.info(context, 'Đã xóa hộp hội thoại!');
              Navigator.pop(ctx);
            },
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
  }
}
