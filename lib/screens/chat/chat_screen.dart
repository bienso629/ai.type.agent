import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/api_service.dart';
import '../../core/services/clipboard_service.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/attachment_hover_preview.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../core/widgets/chat_avatar.dart';
import 'widgets/model_picker_dialog.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/server_model.dart';
import '../../providers/chat_provider.dart';
import '../../providers/server_provider.dart';
import '../terminal/terminal_screen.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? onNavigateToServers;

  const ChatScreen({super.key, this.onNavigateToServers});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _apiService = ApiService();
  ApiService get _api => _apiService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final List<AttachmentItem> _attachedFiles = [];

  // Prompt history navigation state
  int _promptHistoryIndex = -1;
  String _draftPrompt = '';

  // Inline slash autocomplete state
  List<String> _inlineDirSuggestions = [];
  bool _isInlineDirLoading = false;
  String _currentSlashWord = '';
  int _inlineActiveIndex = 0;
  Timer? _dirDebounceTimer;

  String? _lastSessionId;
  bool _isLoadingOlder = false;
  bool _wasGenerating = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageKey;
  Timer? _highlightTimer;
  Timer? _stickyScrollThrottleTimer;
  ChatMessageModel? _stickyUserQuestion;

  static final MarkdownStyleSheet _sharedMarkdownStyle = MarkdownStyleSheet(
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
    blockSpacing: 6.0,
    listBullet: const TextStyle(fontSize: 10.0, color: AppColors.textMuted),
    listBulletPadding: const EdgeInsets.only(right: 8, top: 4),
    listIndent: 16.0,
    code: const TextStyle(
      fontFamily: 'monospace',
      backgroundColor: AppColors.codeBg,
      color: AppColors.terminalGreen,
      fontSize: 12,
    ),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
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
  );

  String _getMessageKey(ChatMessageModel msg, [int? index]) {
    if (msg.id != null) return 'msg_id_${msg.id}';
    return 'msg_${msg.createdAt.millisecondsSinceEpoch}_${msg.role}';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);
    _inputFocusNode.onKeyEvent = _handleInputKeyEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      final server = context.read<ServerProvider>();
      server.loadServers().then((_) {
        chat.loadSessions().then((_) {
          if (chat.currentSession != null) {
            chat.selectSession(chat.currentSession!).then((_) {
              server.selectServerByTarget(chat.currentSession!.targetServer);
              _safeScrollToBottom(instant: true);
            });
          } else if (chat.sessions.isNotEmpty) {
            chat.selectSession(chat.sessions.first).then((_) {
              server.selectServerByTarget(chat.sessions.first.targetServer);
              _safeScrollToBottom(instant: true);
            });
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _dirDebounceTimer?.cancel();
    _stickyScrollThrottleTimer?.cancel();
    _messageKeys.clear();
    _textController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _inputFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isPastingImage = false;
  DateTime _lastPasteTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _checkAndPasteClipboardImage() async {
    final now = DateTime.now();
    if (_isPastingImage || now.difference(_lastPasteTime).inMilliseconds < 800) {
      return;
    }
    _isPastingImage = true;
    _lastPasteTime = now;
    try {
      final img = await ClipboardService.getClipboardImage();
      if (img != null && mounted) {
        // Prevent duplicate addition if already attached
        final isDuplicate = _attachedFiles.any((a) =>
            a.name == img.name ||
            (a.rawBytes != null &&
                img.rawBytes != null &&
                listEquals(a.rawBytes, img.rawBytes)));
        if (!isDuplicate) {
          setState(() {
            _attachedFiles.add(img);
          });
          AppToast.success(context, 'Đã đính kèm ảnh chụp màn hình (${img.name})');
        }
      }
    } finally {
      _isPastingImage = false;
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
      if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
        _checkAndPasteClipboardImage();
      }
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_inlineDirSuggestions.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            _inlineActiveIndex = (_inlineActiveIndex + 1) % _inlineDirSuggestions.length;
          });
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            _inlineActiveIndex = (_inlineActiveIndex - 1 + _inlineDirSuggestions.length) % _inlineDirSuggestions.length;
          });
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          if (_inlineActiveIndex >= 0 && _inlineActiveIndex < _inlineDirSuggestions.length) {
            final selectedDir = _inlineDirSuggestions[_inlineActiveIndex];
            _applyInlineDirAsScope(selectedDir);
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.tab) {
          if (_inlineActiveIndex >= 0 && _inlineActiveIndex < _inlineDirSuggestions.length) {
            final selectedDir = _inlineDirSuggestions[_inlineActiveIndex];
            _insertInlineDirIntoText(selectedDir);
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() {
            _inlineDirSuggestions.clear();
            _currentSlashWord = '';
          });
          return KeyEventResult.handled;
        }
      } else {
        // Lấy danh sách lịch sử câu hỏi của session hiện tại từ provider
        final chat = context.read<ChatProvider>();
        final currentMessages = chat.messages;
        final history = <String>[];
        for (final m in currentMessages) {
          if (m.role == 'user' && m.content.trim().isNotEmpty) {
            final trimmed = m.content.trim();
            if (history.isEmpty || history.last != trimmed) {
              history.add(trimmed);
            }
          }
        }

        if (history.isNotEmpty) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final selection = _textController.selection;
            final isCursorAtStart = selection.baseOffset <= 0 || _textController.text.isEmpty || !_textController.text.contains('\n');
            if (isCursorAtStart || _promptHistoryIndex != -1) {
              if (_promptHistoryIndex == -1) {
                _draftPrompt = _textController.text;
                _promptHistoryIndex = history.length - 1;
              } else if (_promptHistoryIndex > 0) {
                _promptHistoryIndex--;
              }

              final targetText = history[_promptHistoryIndex];
              _textController.value = TextEditingValue(
                text: targetText,
                selection: TextSelection.collapsed(offset: targetText.length),
              );
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_promptHistoryIndex != -1) {
              if (_promptHistoryIndex < history.length - 1) {
                _promptHistoryIndex++;
                final targetText = history[_promptHistoryIndex];
                _textController.value = TextEditingValue(
                  text: targetText,
                  selection: TextSelection.collapsed(offset: targetText.length),
                );
              } else {
                _promptHistoryIndex = -1;
                _textController.value = TextEditingValue(
                  text: _draftPrompt,
                  selection: TextSelection.collapsed(offset: _draftPrompt.length),
                );
              }
              return KeyEventResult.handled;
            }
          }
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _onTextChanged() {
    final text = _textController.text;
    final selection = _textController.selection;
    if (selection.baseOffset < 0 || text.length > 50000) {
      if (_inlineDirSuggestions.isNotEmpty || _isInlineDirLoading) {
        _dirDebounceTimer?.cancel();
        setState(() {
          _inlineDirSuggestions.clear();
          _isInlineDirLoading = false;
          _currentSlashWord = '';
        });
      }
      return;
    }

    final cursor = selection.baseOffset.clamp(0, text.length);
    // Chỉ kiểm tra tối đa 200 ký tự trước con trỏ để tránh lag regex khi text dài
    final startIdx = (cursor - 200).clamp(0, cursor);
    final textNearCursor = text.substring(startIdx, cursor);
    final match = RegExp(r'(?:^|\s)(/[^\s]*)$').firstMatch(textNearCursor);

    if (match != null) {
      final word = match.group(1) ?? '/';
      _currentSlashWord = word;
      _dirDebounceTimer?.cancel();
      _dirDebounceTimer = Timer(const Duration(milliseconds: 180), () async {
        if (!mounted) return;
        setState(() => _isInlineDirLoading = true);
        final dirs = await _apiService.listDirectories(prefix: word);
        if (mounted && _currentSlashWord == word) {
          setState(() {
            _inlineDirSuggestions = dirs;
            _inlineActiveIndex = 0;
            _isInlineDirLoading = false;
          });
        }
      });
    } else {
      if (_inlineDirSuggestions.isNotEmpty || _isInlineDirLoading) {
        _dirDebounceTimer?.cancel();
        setState(() {
          _inlineDirSuggestions.clear();
          _inlineActiveIndex = 0;
          _isInlineDirLoading = false;
          _currentSlashWord = '';
        });
      }
    }
  }

  void _applyInlineDirAsScope(String dir) {
    context.read<ChatProvider>().setScopeForCurrentSession(dir);
    final text = _textController.text;
    final idx = text.lastIndexOf(_currentSlashWord);
    if (idx != -1) {
      _textController.text = (text.substring(0, idx) + text.substring(idx + _currentSlashWord.length)).trim();
    }
    setState(() {
      _inlineDirSuggestions.clear();
      _currentSlashWord = '';
    });
    AppToast.success(context, 'Đã gán Scope cho cuộc hội thoại này: $dir');
  }

  void _insertInlineDirIntoText(String dir) {
    final text = _textController.text;
    final idx = text.lastIndexOf(_currentSlashWord);
    if (idx != -1) {
      final newText = '${text.substring(0, idx)}$dir ${text.substring(idx + _currentSlashWord.length)}';
      _textController.text = newText;
      _textController.selection = TextSelection.fromPosition(TextPosition(offset: idx + dir.length + 1));
    }
    setState(() {
      _inlineDirSuggestions.clear();
      _currentSlashWord = '';
    });
  }

  Future<void> _handleLoadMore(ChatProvider chat) async {
    if (_isLoadingOlder || !chat.hasMoreMessages || chat.isLoadingMore || chat.isLoading) return;
    _isLoadingOlder = true;
    try {
      await chat.loadMoreMessages();
    } finally {
      _isLoadingOlder = false;
    }
  }

  void _updateStickyQuestion() {
    if (!_scrollController.hasClients || !mounted) return;
    final chat = context.read<ChatProvider>();
    if (chat.messages.isEmpty) {
      if (_stickyUserQuestion != null) {
        setState(() => _stickyUserQuestion = null);
      }
      return;
    }

    // Nếu đang ở gần cuối (scroll offset <= 30px), người dùng đang nhìn thấy tin nhắn mới nhất
    final currentPixels = _scrollController.position.pixels;
    if (currentPixels <= 30.0) {
      if (_stickyUserQuestion != null) {
        setState(() => _stickyUserQuestion = null);
      }
      return;
    }

    // Duyệt tìm câu hỏi người dùng gần nhất ở vị trí phía trên
    // Chỉ cần kiểm tra tối đa 20 tin nhắn gần nhất để tránh lag danh sách dài
    ChatMessageModel? targetStickyQuestion;
    final checkLimit = chat.messages.length > 20 ? 20 : chat.messages.length;
    for (int i = 0; i < checkLimit; i++) {
      final msg = chat.messages[chat.messages.length - 1 - i];
      if (msg.role == 'user') {
        final keyStr = _getMessageKey(msg, chat.messages.length - 1 - i);
        final gKey = _messageKeys[keyStr];
        if (gKey?.currentContext != null) {
          final renderBox = gKey!.currentContext!.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            final position = renderBox.localToGlobal(Offset.zero);
            // Header topbar cao 66px. Nếu bubble câu hỏi đã cuộn vượt qua đỉnh màn hình:
            if (position.dy + renderBox.size.height <= 80) {
              targetStickyQuestion = msg;
              break;
            }
          }
        } else {
          // Nếu RenderBox chưa sẵn sàng nhưng scroll đã vượt qua khá nhiều
          if (currentPixels > 100.0 && targetStickyQuestion == null) {
            targetStickyQuestion = msg;
            break;
          }
        }
      }
    }

    // Fallback: nếu scroll sâu mà không tính được vị trí, lấy user message gần nhất trước tin nhắn cuối
    if (targetStickyQuestion == null && currentPixels > 120.0) {
      final fallbackLimit = chat.messages.length > 30 ? chat.messages.length - 30 : 0;
      for (int i = chat.messages.length - 1; i >= fallbackLimit; i--) {
        if (chat.messages[i].role == 'user') {
          targetStickyQuestion = chat.messages[i];
          break;
        }
      }
    }

    if (_stickyUserQuestion?.id != targetStickyQuestion?.id ||
        _stickyUserQuestion?.content != targetStickyQuestion?.content) {
      setState(() {
        _stickyUserQuestion = targetStickyQuestion;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingOlder) return;
    
    // Throttle _updateStickyQuestion để tránh tính toán RenderBox liên tục trên từng pixel scroll
    if (_stickyScrollThrottleTimer == null || !_stickyScrollThrottleTimer!.isActive) {
      _stickyScrollThrottleTimer = Timer(const Duration(milliseconds: 60), () {
        if (mounted) _updateStickyQuestion();
      });
    }

    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 80) {
      final chat = context.read<ChatProvider>();
      if (chat.hasMoreMessages && !chat.isLoadingMore && !chat.isLoading) {
        _handleLoadMore(chat);
      }
    }
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_scrollController.hasClients) return;
    try {
      if (instant) {
        _scrollController.jumpTo(0.0);
      } else {
        _scrollController.animateTo(
          0.0,
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


  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final startIdx = _attachedFiles.length;
        for (final f in result.files) {
          AttachmentItem? item;
          if (f.bytes != null) {
            item = AttachmentItem.fromBytes(
              name: f.name,
              bytes: f.bytes!,
              path: f.path,
            );
          } else if (f.path != null) {
            final file = File(f.path!);
            if (file.existsSync()) {
              item = await AttachmentItem.fromFile(file, fileName: f.name);
            }
          }
          if (item != null) {
            _attachedFiles.add(item);
          }
        }
        if (mounted) {
          setState(() {});
          // Trigger background upload to VPS with progress tracking
          for (int i = startIdx; i < _attachedFiles.length; i++) {
            _uploadAttachment(i);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi chọn tệp: $e');
      }
    }
  }

  Future<void> _uploadAttachment(int index) async {
    if (index >= _attachedFiles.length) return;
    final item = _attachedFiles[index];
    if (item.isUploaded || item.isUploading) return;

    setState(() {
      _attachedFiles[index] = item.copyWith(isUploading: true, uploadProgress: 0.01);
    });

    try {
      Uint8List? fileBytes = item.rawBytes;
      if (fileBytes == null && item.path != null) {
        final f = File(item.path!);
        if (f.existsSync()) {
          fileBytes = await f.readAsBytes();
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        if (mounted) {
          final idx = _attachedFiles.indexWhere((x) => x.name == item.name);
          if (idx != -1) {
            setState(() {
              _attachedFiles[idx] = _attachedFiles[idx].copyWith(
                isUploading: false,
                isUploaded: false,
                error: 'Không đọc được dữ liệu',
              );
            });
          }
        }
        return;
      }

      if (!mounted) return;
      final currentScope = context.read<ChatProvider>().currentSessionScope;
      final currentServer = context.read<ServerProvider>().selectedServer;
      final res = await _api.uploadFile(
        fileName: item.name,
        bytes: fileBytes,
        targetDir: currentScope,
        server: currentServer,
        onProgress: (sent, total, prog) {
          if (!mounted) return;
          final idx = _attachedFiles.indexWhere((x) => x.name == item.name);
          if (idx != -1) {
            setState(() {
              _attachedFiles[idx] = _attachedFiles[idx].copyWith(
                uploadProgress: prog,
                isUploading: prog < 1.0,
                isUploaded: prog >= 1.0,
              );
            });
          }
        },
      );

      if (mounted) {
        final idx = _attachedFiles.indexWhere((x) => x.name == item.name);
        if (idx != -1) {
          if (res['status'] == 'success') {
            setState(() {
              _attachedFiles[idx] = _attachedFiles[idx].copyWith(
                isUploading: false,
                isUploaded: true,
                uploadProgress: 1.0,
                remotePath: res['remote_path']?.toString(),
              );
            });
          } else {
            setState(() {
              _attachedFiles[idx] = _attachedFiles[idx].copyWith(
                isUploading: false,
                isUploaded: false,
                error: res['message']?.toString() ?? 'Lỗi tải lên',
              );
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final idx = _attachedFiles.indexWhere((x) => x.name == item.name);
        if (idx != -1) {
          setState(() {
            _attachedFiles[idx] = _attachedFiles[idx].copyWith(
              isUploading: false,
              isUploaded: false,
              error: e.toString(),
            );
          });
        }
      }
    }
  }

  Future<void> _downloadAttachment(AttachmentItem att) async {
    final remotePath = att.remotePath ?? '/opt/ai_agent/uploads/${att.name}';
    final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final downloadsDir = Directory('$homeDir/Downloads');
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }
    final destFile = File('${downloadsDir.path}/${att.name}');

    double progress = 0.0;
    int received = 0;
    int total = att.size;
    bool isDone = false;
    String? errorMsg;
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          dialogSetState = setDState;
          final pct = (progress * 100).toInt();
          final receivedFormatted = received < 1024 * 1024
              ? '${(received / 1024).toStringAsFixed(1)} KB'
              : '${(received / (1024 * 1024)).toStringAsFixed(1)} MB';
          final totalFormatted = total > 0
              ? (total < 1024 * 1024
                  ? '${(total / 1024).toStringAsFixed(1)} KB'
                  : '${(total / (1024 * 1024)).toStringAsFixed(1)} MB')
              : att.formattedSize;

          return AlertDialog(
            backgroundColor: AppColors.cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: AppColors.borderDark),
            ),
            title: Row(
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : (errorMsg != null ? Icons.error_outline_rounded : Icons.download_rounded),
                  color: isDone ? AppColors.accent : (errorMsg != null ? AppColors.danger : AppColors.accentCyan),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isDone ? 'Tải xuống hoàn tất' : (errorMsg != null ? 'Lỗi tải xuống' : 'Đang tải xuống từ VPS'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(att.isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded, size: 16, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          att.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isDone ? 1.0 : (total > 0 ? progress : null),
                      minHeight: 8,
                      backgroundColor: AppColors.bgDark,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDone ? AppColors.accent : (errorMsg != null ? AppColors.danger : AppColors.accentCyan),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isDone
                              ? 'Đã lưu: ${destFile.path}'
                              : (errorMsg ?? '$receivedFormatted / $totalFormatted'),
                          style: TextStyle(
                            fontSize: 11,
                            color: errorMsg != null ? AppColors.danger : AppColors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isDone && errorMsg == null)
                        Text(
                          '$pct%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              if (isDone)
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open_rounded, size: 14),
                  label: const Text('Mở thư mục'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (Platform.isLinux) {
                      Process.run('xdg-open', [downloadsDir.path]);
                    } else if (Platform.isWindows) {
                      Process.run('explorer.exe', [downloadsDir.path]);
                    } else if (Platform.isMacOS) {
                      Process.run('open', [downloadsDir.path]);
                    }
                  },
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(isDone ? 'Đóng' : 'Huỷ'),
              ),
            ],
          );
        },
      ),
    );

    try {
      final bytes = await _api.downloadFile(
        remotePath: remotePath,
        onProgress: (rec, tot, prog) {
          received = rec;
          if (tot > 0) total = tot;
          progress = prog;
          dialogSetState?.call(() {});
        },
      );

      if (bytes != null && bytes.isNotEmpty) {
        await destFile.writeAsBytes(bytes);
        isDone = true;
        progress = 1.0;
        dialogSetState?.call(() {});
        if (mounted) {
          AppToast.success(context, 'Đã tải xuống: ${att.name}');
        }
      } else {
        errorMsg = 'Không tải được nội dung tệp từ server';
        dialogSetState?.call(() {});
      }
    } catch (e) {
      errorMsg = 'Lỗi: $e';
      dialogSetState?.call(() {});
    }
  }

  Future<void> _handleSend(ChatProvider chat, ServerProvider serverProvider) async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _attachedFiles.isEmpty) || chat.isGenerating) return;

    // Await any in-flight uploads if necessary
    if (_attachedFiles.any((a) => a.isUploading)) {
      int waitMs = 0;
      while (_attachedFiles.any((a) => a.isUploading) && waitMs < 12000 && mounted) {
        await Future.delayed(const Duration(milliseconds: 250));
        waitMs += 250;
      }
    }

    final attachmentsToSend = _attachedFiles.isNotEmpty ? List<AttachmentItem>.from(_attachedFiles) : null;
    _textController.clear();
    _promptHistoryIndex = -1;
    _draftPrompt = '';
    setState(() {
      _attachedFiles.clear();
    });

    final activeServerName = serverProvider.selectedServer?.name ?? 'Local Machine';
    chat.sendMessage(
      text,
      model: serverProvider.currentAiModel,
      attachments: attachmentsToSend,
      workingDir: chat.currentSessionScope,
      targetServer: activeServerName,
    );
    _safeScrollToBottom();
  }

  void _triggerScopePicker() async {
    final chat = context.read<ChatProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _ScopePickerDialog(
        currentScope: chat.currentSessionScope,
        currentDocFiles: chat.currentSessionDocFiles,
        onSelect: (val, docs) {
          chat.setScopeForCurrentSession(val, docFiles: docs);
          if (val != null) {
            final docCount = docs.length;
            final docNote = docCount > 0 ? ' (Kèm $docCount file tài liệu)' : '';
            AppToast.success(context, 'Đã gán Scope cho cuộc hội thoại này: $val$docNote');
          } else {
            AppToast.info(context, 'Đã xóa giới hạn Scope của cuộc hội thoại');
          }
        },
      ),
    );
  }

  Widget _buildServerDropdown(ServerProvider serverProvider) {
    final isLocal = serverProvider.selectedServer == null ||
        serverProvider.selectedServer!.serverIp == '127.0.0.1' ||
        serverProvider.selectedServer!.serverIp == 'localhost';
    final currentServerName = isLocal ? 'Local Machine' : serverProvider.selectedServer!.name;
    final currentServerIp = isLocal
        ? '${Platform.operatingSystem.toUpperCase()} (Cục bộ)'
        : serverProvider.selectedServer!.serverIp;

    return PopupMenuButton<ServerModel>(
      tooltip: 'Chuyển đổi Máy chủ / Local',
      offset: const Offset(0, 44),
      color: AppColors.cardBg,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 290),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      onSelected: (srv) async {
        if (srv.id == '__manage_servers__') {
          widget.onNavigateToServers?.call();
        } else if (srv.id == 'local' || srv.serverIp == '127.0.0.1' || srv.serverIp == 'localhost') {
          await serverProvider.selectServer(ServerModel(
            id: 'local',
            name: 'Local Machine',
            serverIp: '127.0.0.1',
          ));
          if (mounted) {
            AppToast.success(context, 'Đã chuyển sang chế độ Local Machine');
          }
        } else {
          await serverProvider.selectServer(srv);
          if (mounted) {
            AppToast.success(context, 'Đã chuyển sang máy chủ: ${srv.name}');
          }
        }
      },
      itemBuilder: (ctx) {
        final list = <PopupMenuEntry<ServerModel>>[];

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
                if (isLocal) const Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
              ],
            ),
          ),
        );

        // 2. VPS Servers list
        if (serverProvider.servers.isNotEmpty) {
          list.add(const PopupMenuDivider());
          for (final s in serverProvider.servers) {
            final isSel = !isLocal &&
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
        if (widget.onNavigateToServers != null) {
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
        }

        return list;
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isLocal
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                isLocal ? Icons.laptop_chromebook_rounded : Icons.dns_rounded,
                size: 14,
                color: isLocal ? AppColors.accent : AppColors.primaryLight,
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentServerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite, height: 1.1),
                  ),
                  Text(
                    currentServerIp,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted, height: 1.1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more_rounded, size: 14, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final serverProvider = context.watch<ServerProvider>();

    // 1. Chỉ cuộn xuống cuối và nạp lịch sử câu hỏi gần đây khi lần đầu chọn/mở Hộp hội thoại
    if (_lastSessionId != chat.currentSession?.id) {
      _lastSessionId = chat.currentSession?.id;
      _messageKeys.clear();
      _promptHistoryIndex = -1;
      _draftPrompt = '';
      _stickyUserQuestion = null;
      _wasGenerating = chat.isGenerating;
      _safeScrollToBottom(instant: true);
      if (chat.currentSession != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            serverProvider.selectServerByTarget(chat.currentSession!.targetServer);
          }
        });
      }
    }
    // 2. Chỉ cuộn xuống cuối khi Agent trả lời xong câu hỏi (chuyển từ generating sang done)
    else if (_wasGenerating && !chat.isGenerating) {
      _wasGenerating = false;
      _safeScrollToBottom();
    } else {
      _wasGenerating = chat.isGenerating;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _checkAndPasteClipboardImage,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _checkAndPasteClipboardImage,
      },
      child: Focus(
        autofocus: false,
        child: Scaffold(
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
                // Left: Session & Server Info
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (context) {
                          final currentServerName = (chat.currentSession?.targetServer != null && chat.currentSession!.targetServer!.isNotEmpty)
                              ? chat.currentSession!.targetServer!
                              : (serverProvider.selectedServer?.name ?? 'Local Machine');
                          return Stack(
                            children: [
                              ChatAvatar(
                                serverName: currentServerName,
                                server: serverProvider.selectedServer,
                                size: 34,
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
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    chat.currentSession?.title ?? 'AI Type Agent',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                  ),
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
                            Builder(
                              builder: (context) {
                                final currentServerName = (chat.currentSession?.targetServer != null && chat.currentSession!.targetServer!.isNotEmpty)
                                    ? chat.currentSession!.targetServer!
                                    : (serverProvider.selectedServer?.name ?? 'Local Machine');
                                final isLocal = currentServerName == 'Local Machine' ||
                                    currentServerName == 'Local' ||
                                    currentServerName == 'localhost' ||
                                    currentServerName == '127.0.0.1';

                                if (isLocal) {
                                  return Text(
                                    'Gắn với: Local Machine (${Platform.operatingSystem}) • Thực thi an toàn trên shell cục bộ',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                  );
                                } else {
                                  return Text(
                                    'Gắn với Máy chủ: $currentServerName • Mọi lệnh terminal được gửi qua SSH tới máy chủ này',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.primaryLight),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Right: Server Selector Dropdown
                _buildServerDropdown(serverProvider),
              ],
            ),
          ),

          // 2. Main Content Split 50-50: Left is Chat Feed, Right is Terminal Screen
          Expanded(
            child: Row(
              children: [
                // Left Column (50%): Chat Center Feed View & Input Bar
                Expanded(
                  child: Column(
                    children: [
                      // Message Stream & Sticky Question Header
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: chat.isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : ListView.builder(
                                      controller: _scrollController,
                                      reverse: true,
                                      cacheExtent: 250.0,
                                      addRepaintBoundaries: true,
                                      addAutomaticKeepAlives: false,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      itemCount: chat.messages.isEmpty
                                          ? 1
                                          : chat.messages.length + (chat.hasMoreMessages ? 1 : 1),
                                      itemBuilder: (context, idx) {
                                        if (chat.messages.isEmpty) {
                                          return _buildGreetingBubble(chat, serverProvider);
                                        }
                                        if (idx == chat.messages.length) {
                                          if (chat.hasMoreMessages) {
                                            return _buildLoadMoreBanner(chat);
                                          }
                                          return _buildGreetingBubble(chat, serverProvider);
                                        }
                                        final msgIndex = chat.messages.length - 1 - idx;
                                        final msg = chat.messages[msgIndex];
                                        return RepaintBoundary(
                                          child: _buildMessageItem(msg, chat, msgIndex),
                                        );
                                      },
                                    ),
                            ),

                            // Sticky Question Header
                            if (_stickyUserQuestion != null)
                              Positioned(
                                top: 8,
                                left: 20,
                                right: 20,
                                child: _buildStickyQuestionHeader(_stickyUserQuestion!, chat),
                              ),
                          ],
                        ),
                      ),

                      // Input Bar
                      _buildInputBar(chat, serverProvider),
                    ],
                  ),
                ),

                // Vertical Divider between Chat and Terminal
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.borderDark,
                ),

                // Right Column (50%): Terminal Screen
                const Expanded(
                  child: TerminalScreen(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildStickyQuestionHeader(ChatMessageModel question, ChatProvider chat) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131920).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            offset: const Offset(0, 4),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.help_outline_rounded, size: 14, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'CÂU HỎI ĐANG XEM',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatSessionTime(question.createdAt),
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textDim,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  question.content.replaceAll('\n', ' ').trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Nút đóng sticky
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
            tooltip: 'Ẩn thanh ghim',
            onPressed: () {
              setState(() {
                _stickyUserQuestion = null;
              });
            },
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
                borderRadius: BorderRadius.circular(4),
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
              onTap: () => _handleLoadMore(chat),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(4),
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
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Xin chào! Tôi là AI Type Agent (${serverProvider.currentAiModel})',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
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
                label: 'Kiểm tra RAM & Ổ đĩa',
                prompt: 'Kiểm tra dung lượng ổ đĩa và RAM hiện tại',
                chat: chat,
              ),
              _buildPromptChip(
                label: 'Top tiến trình CPU',
                prompt: 'Xem danh sách tiến trình đang chạy và chiếm nhiều CPU nhất',
                chat: chat,
              ),
              _buildPromptChip(
                label: 'Cổng đang mở',
                prompt: 'Kiểm tra các cổng mạng đang mở (listening ports)',
                chat: chat,
              ),
              _buildPromptChip(
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
    required String label,
    required String prompt,
    required ChatProvider chat,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.borderDark),
        backgroundColor: AppColors.inputBg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: chat.isGenerating
          ? null
          : () {
              chat.sendMessage(prompt);
              _safeScrollToBottom();
            },
      child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textBody)),
    );
  }

  Widget _buildMessageItem(ChatMessageModel msg, ChatProvider chat, int index) {
    final isUser = msg.role == 'user';
    final keyStr = _getMessageKey(msg, index);
    final isTargetHighlighted = _highlightedMessageKey == keyStr;

    return Padding(
      key: isUser
          ? _messageKeys.putIfAbsent(keyStr, () => GlobalKey())
          : ValueKey(keyStr),
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: ChatAvatar(
                isUser: false,
                serverName: chat.currentSession?.targetServer,
                size: 30,
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isTargetHighlighted
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : (isUser
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.cardBg),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isTargetHighlighted
                          ? AppColors.accentCyan
                          : (isUser
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : AppColors.borderDark),
                      width: isTargetHighlighted ? 1.8 : 1,
                    ),
                    boxShadow: isTargetHighlighted
                        ? [
                            BoxShadow(
                              color: AppColors.accentCyan.withValues(alpha: 0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.attachments.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: msg.attachments.map((att) {
                            return AttachmentHoverPreview(
                              item: att,
                              child: Material(
                                color: AppColors.bgDark,
                                borderRadius: BorderRadius.circular(4),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => _downloadAttachment(att),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 160),
                                          child: Text(
                                            att.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '(${att.formattedSize})',
                                          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Tải xuống',
                                          style: TextStyle(fontSize: 10, color: AppColors.accentCyan, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // 1. Tool Executions (Terminal actions & commands) rendered first
                      if (msg.toolExecutions.isNotEmpty) ...[
                        ...msg.toolExecutions.map((tool) => _buildToolCard(tool)),
                        if (msg.content.isNotEmpty || (msg.content.isEmpty && msg.isStreaming))
                          const SizedBox(height: 10),
                      ],

                      // 2. Reply Answer Content rendered below tool executions
                      if (msg.content.isNotEmpty)
                        MarkdownBody(
                          data: msg.content,
                          selectable: true,
                          onTapLink: (text, href, title) async {
                            if (href != null && href.trim().isNotEmpty) {
                              var rawUrl = href.trim();
                              // Tự động bổ sung scheme https:// nếu người dùng/mô hình viết url dạng www. hoặc domain thông thường
                              if (!rawUrl.startsWith(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'))) {
                                rawUrl = 'https://$rawUrl';
                              }
                              final uri = Uri.tryParse(rawUrl);
                              bool launched = false;
                              if (uri != null) {
                                try {
                                  launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } catch (_) {
                                  try {
                                    launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
                                  } catch (_) {}
                                }
                              }
                              // Fallback hệ thống trên Linux/Desktop nếu url_launcher không kích hoạt được trình duyệt
                              if (!launched) {
                                try {
                                  if (Platform.isLinux) {
                                    final res = await Process.run('xdg-open', [rawUrl]);
                                    if (res.exitCode == 0) launched = true;
                                  } else if (Platform.isMacOS) {
                                    final res = await Process.run('open', [rawUrl]);
                                    if (res.exitCode == 0) launched = true;
                                  } else if (Platform.isWindows) {
                                    final res = await Process.run('cmd', ['/c', 'start', '', rawUrl]);
                                    if (res.exitCode == 0) launched = true;
                                  }
                                } catch (_) {}
                              }
                              if (!launched) {
                                await Clipboard.setData(ClipboardData(text: rawUrl));
                                if (mounted) {
                                  AppToast.info(context, 'Đã sao chép liên kết vào bộ nhớ tạm: $rawUrl');
                                }
                              }
                            }
                          },
                          builders: {
                            'code': CodeElementBuilder(context),
                          },
                          styleSheet: _sharedMarkdownStyle,
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
                    ],
                  ),
                ),

                // Message Action Bar (Timestamp, Copy, Retry, PDF)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatSessionTime(msg.createdAt),
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textDim, fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 8),
                      const Text('•', style: TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: msg.content));
                          AppToast.success(context, 'Đã sao chép nội dung vào bộ nhớ tạm!');
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text('Sao chép', style: TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                        ),
                      ),
                      if (!isUser) ...[
                        const SizedBox(width: 6),
                        const Text('•', style: TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
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
                            child: Text('Tải PDF A4', style: TextStyle(fontSize: 10.5, color: AppColors.primaryLight, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ],
                      if (isUser) ...[
                        const SizedBox(width: 6),
                        const Text('•', style: TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            final serverProvider = context.read<ServerProvider>();
                            final activeServerName = serverProvider.selectedServer?.name ?? 'Local Machine';
                            chat.sendMessage(
                              msg.content,
                              model: serverProvider.currentAiModel,
                              workingDir: chat.currentSessionScope,
                              targetServer: activeServerName,
                            );
                            _safeScrollToBottom();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text('Hỏi lại', style: TextStyle(fontSize: 10.5, color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard(ToolExecutionItem tool) {
    IconData icon = Icons.terminal_rounded;
    Color iconColor = AppColors.primaryLight;
    final cleanTool = tool.tool.toLowerCase();
    if (cleanTool.contains('file') || cleanTool.contains('read') || cleanTool.contains('view')) {
      icon = Icons.description_outlined;
      iconColor = AppColors.accentCyan;
    } else if (cleanTool.contains('edit') || cleanTool.contains('write') || cleanTool.contains('replace')) {
      icon = Icons.edit_note_rounded;
      iconColor = Colors.amber;
    } else if (cleanTool.contains('search') || cleanTool.contains('grep') || cleanTool.contains('find')) {
      icon = Icons.search_rounded;
      iconColor = Colors.purpleAccent;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
            ),
            child: Row(
              children: [
                Icon(icon, size: 13, color: iconColor),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tool.tool.isNotEmpty ? tool.tool : 'command',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tool.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Command body / Output
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  tool.command,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.accentCyan,
                    height: 1.4,
                  ),
                ),
                if (tool.output.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D13),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF21262D)),
                    ),
                    child: SelectableText(
                      tool.output.trim(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chat.currentSessionScope != null && chat.currentSessionScope!.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    hoverColor: AppColors.primary.withValues(alpha: 0.22),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onTap: _triggerScopePicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open_rounded, size: 14, color: AppColors.primaryLight),
                          const SizedBox(width: 6),
                          const Text('Scope Hội Thoại: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          Flexible(
                            child: Text(
                              chat.currentSessionScope!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                          if (chat.currentSessionDocFiles.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.accentCyan.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.description_rounded, size: 11, color: AppColors.accentCyan),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${chat.currentSessionDocFiles.length} tài liệu',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.accentCyan,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Xóa Scope',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              hoverColor: AppColors.danger.withValues(alpha: 0.2),
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              onTap: () {
                                chat.setScopeForCurrentSession(null);
                                AppToast.info(context, 'Đã xóa giới hạn Scope của cuộc hội thoại');
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (_attachedFiles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _attachedFiles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final att = entry.value;
                      final Color chipBorderColor = att.error != null
                          ? AppColors.danger.withValues(alpha: 0.5)
                          : (att.isUploaded
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : AppColors.accentCyan.withValues(alpha: 0.5));
                      final Color chipBgColor = att.error != null
                          ? AppColors.danger.withValues(alpha: 0.12)
                          : (att.isUploaded
                              ? AppColors.accent.withValues(alpha: 0.12)
                              : AppColors.accentCyan.withValues(alpha: 0.12));

                      return AttachmentHoverPreview(
                        item: att,
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: chipBgColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: chipBorderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    att.isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                                    size: 14,
                                    color: att.isImage ? AppColors.accentCyan : AppColors.warning,
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 160),
                                    child: Text(
                                      att.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textWhite),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${att.formattedSize})',
                                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                  ),
                                  const SizedBox(width: 6),
                                  if (att.isUploading) ...[
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        value: att.uploadProgress > 0 ? att.uploadProgress : null,
                                        strokeWidth: 1.5,
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${(att.uploadProgress * 100).toInt()}%',
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: AppColors.accentCyan,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ] else if (att.isUploaded) ...[
                                    const Tooltip(
                                      message: 'Đã lưu trên VPS',
                                      child: Icon(Icons.check_circle_rounded, size: 14, color: AppColors.accent),
                                    ),
                                    const SizedBox(width: 6),
                                  ] else if (att.error != null) ...[
                                    Tooltip(
                                      message: att.error!,
                                      child: const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _attachedFiles.removeAt(idx);
                                      });
                                    },
                                    child: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                                  ),
                                ],
                              ),
                              if (att.isUploading) ...[
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    width: 160,
                                    child: LinearProgressIndicator(
                                      value: att.uploadProgress > 0 ? att.uploadProgress : null,
                                      minHeight: 2.5,
                                      backgroundColor: AppColors.bgDark,
                                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            if (_inlineDirSuggestions.isNotEmpty || _isInlineDirLoading) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Gợi ý thư mục (${_currentSlashWord.isNotEmpty ? _currentSlashWord : '/'}):',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                        if (_isInlineDirLoading)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                          )
                        else
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _inlineDirSuggestions.clear();
                                _currentSlashWord = '';
                              });
                            },
                            child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
                          ),
                      ],
                    ),
                    if (_inlineDirSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _inlineDirSuggestions.length,
                          itemBuilder: (ctx, idx) {
                            final dir = _inlineDirSuggestions[idx];
                            final isHighlighted = idx == _inlineActiveIndex;
                            return MouseRegion(
                              onEnter: (_) => setState(() => _inlineActiveIndex = idx),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isHighlighted
                                      ? AppColors.primary.withValues(alpha: 0.25)
                                      : AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isHighlighted
                                        ? AppColors.primaryLight
                                        : AppColors.borderDark,
                                    width: isHighlighted ? 1.2 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.folder_rounded,
                                      size: 14,
                                      color: isHighlighted ? AppColors.primaryLight : AppColors.warning,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        dir,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11.5,
                                          color: isHighlighted ? AppColors.primaryLight : AppColors.textWhite,
                                          fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _applyInlineDirAsScope(dir),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isHighlighted ? '⏎ Đặt Scope' : 'Đặt Scope',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _insertInlineDirIntoText(dir),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.inputBg,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.borderDark),
                                        ),
                                        child: const Text('Tab: Chèn', style: TextStyle(fontSize: 10, color: AppColors.textBody)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            TextField(
              controller: _textController,
              focusNode: _inputFocusNode,
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
                Expanded(
                  child: Row(
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
                          side: BorderSide(
                            color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.borderDark,
                          ),
                          backgroundColor: _attachedFiles.isNotEmpty ? AppColors.accentCyan.withValues(alpha: 0.1) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: Icon(
                          Icons.attach_file_rounded,
                          size: 14,
                          color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.accentCyan,
                        ),
                        label: Text(
                          _attachedFiles.isNotEmpty ? 'Attach (${_attachedFiles.length})' : 'Attach',
                          style: TextStyle(
                            fontSize: 11,
                            color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.textBody,
                            fontWeight: _attachedFiles.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onPressed: _pickFiles,
                      ),
                      const SizedBox(width: 8),
                      // Model Selector Button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryLight, width: 0.8),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: const Icon(Icons.smart_toy_rounded, size: 14, color: AppColors.primaryLight),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                serverProvider.currentAiModel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down_rounded, size: 14, color: AppColors.primaryLight),
                          ],
                        ),
                        onPressed: () => ModelPickerDialog.show(context, serverProvider),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final server = serverProvider.selectedServer;
                            final isLocal = server == null || server.serverIp == '127.0.0.1' || server.serverIp == 'localhost';
                            final targetHintText = isLocal
                                ? 'AI Type Agent đang tương tác với Local Machine ${Platform.operatingSystem.toUpperCase()}'
                                : 'AI Type Agent đang tương tác với ${server.name} (${server.serverIp})';

                            return Text(
                              targetHintText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (chat.isGenerating)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 14),
                    label: const Text('Dừng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => chat.stopGenerating(),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Gửi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _handleSend(chat, serverProvider),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSessionTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

}

class _ScopePickerDialog extends StatefulWidget {
  final String? currentScope;
  final List<String> currentDocFiles;
  final void Function(String? scope, List<String> docFiles) onSelect;

  const _ScopePickerDialog({
    required this.currentScope,
    this.currentDocFiles = const [],
    required this.onSelect,
  });

  @override
  State<_ScopePickerDialog> createState() => _ScopePickerDialogState();
}

class _ScopePickerDialogState extends State<_ScopePickerDialog> {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  late final TextEditingController _controller;
  final FocusNode _dialogFocusNode = FocusNode();
  List<String> _suggestions = [];
  List<String> _recentScopes = [];
  List<String> _selectedDocs = [];
  bool _isLoading = false;
  int _selectedIndex = 0;
  Timer? _debounce;

  static List<String> get _presets {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final list = <String>[];
    if (home.isNotEmpty) {
      list.add(home);
      final doc = '$home/Documents';
      final proj = '$home/Projects';
      final dl = '$home/Downloads';
      if (Directory(doc).existsSync() && !list.contains(doc)) list.add(doc);
      if (Directory(proj).existsSync() && !list.contains(proj)) list.add(proj);
      if (Directory(dl).existsSync() && !list.contains(dl)) list.add(dl);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentScope ?? '');
    _selectedDocs = List<String>.from(widget.currentDocFiles);
    _dialogFocusNode.onKeyEvent = _handleDialogKeyEvent;
    _loadRecentScopes();
    _loadSuggestions(_controller.text);
  }

  Future<void> _loadRecentScopes() async {
    final list = await _storage.getRecentScopes();
    if (mounted) {
      setState(() {
        _recentScopes = list;
      });
    }
  }

  Future<void> _removeRecentScope(String path) async {
    await _storage.removeRecentScope(path);
    await _loadRecentScopes();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dialogFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleDialogKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_suggestions.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
            _controller.text = _suggestions[_selectedIndex];
            _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
          });
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            _selectedIndex = (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
            _controller.text = _suggestions[_selectedIndex];
            _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
          });
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          if (_selectedIndex >= 0 && _selectedIndex < _suggestions.length) {
            final val = _suggestions[_selectedIndex];
            widget.onSelect(val, _selectedDocs);
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _loadSuggestions(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      setState(() => _isLoading = true);
      final list = await _api.listDirectories(prefix: query.trim());
      if (mounted) {
        setState(() {
          _suggestions = list;
          _selectedIndex = 0;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _pickLocalDirectory() async {
    try {
      final initialDir = _controller.text.isNotEmpty && Directory(_controller.text).existsSync()
          ? _controller.text
          : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');

      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Chọn thư mục dự án cục bộ (Local Scope)',
        initialDirectory: initialDir,
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        setState(() {
          _controller.text = selectedDirectory;
        });
        _loadSuggestions(selectedDirectory);
      }
    } catch (_) {}
  }

  Future<void> _pickDocFiles() async {
    try {
      final initialDir = _controller.text.isNotEmpty && Directory(_controller.text).existsSync()
          ? _controller.text
          : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        dialogTitle: 'Chọn các tệp tài liệu cho Scope dự án',
        initialDirectory: initialDir,
        type: FileType.custom,
        allowedExtensions: [
          'md',
          'txt',
          'pdf',
          'doc',
          'docx',
          'json',
          'yaml',
          'yml',
          'sql',
          'html',
          'xml',
          'csv',
        ],
      );

      if (result != null && result.paths.isNotEmpty) {
        final validPaths = result.paths
            .where((p) => p != null && p.trim().isNotEmpty)
            .cast<String>()
            .toList();

        if (validPaths.isNotEmpty) {
          setState(() {
            for (final path in validPaths) {
              if (!_selectedDocs.contains(path)) {
                _selectedDocs.add(path);
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return TaduDialog(
      minWidth: 560,
      maxWidth: 660,
      title: const Row(
        children: [
          Icon(Icons.folder_open_rounded, color: AppColors.primaryLight, size: 20),
          SizedBox(width: 8),
          Text('Phạm Vi Thư Mục Làm Việc Cục Bộ (Scope)'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Giới hạn phạm vi thao tác của AI Agent trong thư mục này trên máy tính:',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardBg,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.drive_folder_upload_rounded, size: 14, color: AppColors.primaryLight),
                  label: const Text('Duyệt máy tính...', style: TextStyle(fontSize: 11.5, color: AppColors.primaryLight)),
                  onPressed: _pickLocalDirectory,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Recent Scopes History Section
            if (_recentScopes.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_rounded, size: 12, color: AppColors.accentCyan),
                      SizedBox(width: 4),
                      Text(
                        'Lịch sử thư mục đã làm việc:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentCyan,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () async {
                      await _storage.clearRecentScopes();
                      await _loadRecentScopes();
                    },
                    borderRadius: BorderRadius.circular(3),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Xóa lịch sử',
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _recentScopes.map((scopePath) {
                  final isSelected = _controller.text.trim() == scopePath;
                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.22)
                          : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _controller.text = scopePath;
                          _loadSuggestions(scopePath);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_special_rounded,
                                size: 12,
                                color: isSelected ? AppColors.primaryLight : AppColors.accentCyan,
                              ),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 320),
                                child: Text(
                                  scopePath,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: isSelected ? AppColors.primaryLight : AppColors.textBody,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _removeRecentScope(scopePath),
                                borderRadius: BorderRadius.circular(3),
                                child: const Padding(
                                  padding: EdgeInsets.all(1),
                                  child: Icon(Icons.close_rounded, size: 12, color: AppColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],

            // Quick preset chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _presets.map((preset) {
                final isSelected = _controller.text.trim() == preset;
                return InkWell(
                  onTap: () {
                    _controller.text = preset;
                    _loadSuggestions(preset);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.borderDark,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_rounded,
                          size: 12,
                          color: isSelected ? AppColors.primaryLight : AppColors.accentCyan,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          preset,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isSelected ? AppColors.primaryLight : AppColors.textBody,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Input with auto-complete
            TextField(
              controller: _controller,
              focusNode: _dialogFocusNode,
              onChanged: _loadSuggestions,
              decoration: InputDecoration(
                hintText: 'Nhập đường dẫn thư mục cục bộ, dùng ↑ ↓ Enter để chọn...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                        ),
                      )
                    : (_controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () {
                              _controller.clear();
                              _loadSuggestions('');
                            },
                          )
                        : null),
              ),
            ),
            const SizedBox(height: 10),

            // Suggestions List
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: _suggestions.isEmpty
                  ? Center(
                      child: Text(
                        _isLoading ? 'Đang đọc danh sách thư mục cục bộ...' : 'Không có thư mục con nào',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, idx) {
                        final dir = _suggestions[idx];
                        final isHighlighted = idx == _selectedIndex || _controller.text.trim() == dir;
                        return MouseRegion(
                          onEnter: (_) => setState(() => _selectedIndex = idx),
                          child: InkWell(
                            onTap: () {
                              _controller.text = dir;
                              _loadSuggestions(dir);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isHighlighted
                                    ? AppColors.primary.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                border: Border(
                                  bottom: const BorderSide(color: AppColors.borderDark, width: 0.5),
                                  left: isHighlighted
                                      ? const BorderSide(color: AppColors.primaryLight, width: 3)
                                      : BorderSide.none,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_rounded,
                                    size: 16,
                                    color: isHighlighted ? AppColors.primaryLight : AppColors.accentCyan,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dir,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: isHighlighted ? AppColors.primaryLight : AppColors.textWhite,
                                        fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isHighlighted ? AppColors.primary : AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: isHighlighted ? AppColors.primaryLight : AppColors.borderDark),
                                    ),
                                    child: Text(
                                      isHighlighted ? '⏎ Chọn' : 'Chọn',
                                      style: const TextStyle(fontSize: 10, color: AppColors.textWhite, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),

            // Section: Scope Documentation Files
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 14, color: AppColors.accentCyan),
                    const SizedBox(width: 6),
                    const Text(
                      'Tài liệu dự án đính kèm (Scope Docs):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textWhite,
                      ),
                    ),
                    if (_selectedDocs.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accentCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${_selectedDocs.length}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentCyan,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardBg,
                    side: const BorderSide(color: AppColors.accentCyan),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.note_add_rounded, size: 14, color: AppColors.accentCyan),
                  label: const Text(
                    'Chọn nhiều file...',
                    style: TextStyle(fontSize: 11.5, color: AppColors.accentCyan),
                  ),
                  onPressed: _pickDocFiles,
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Các file được chọn sẽ được tự động nạp vào chỉ thị bối cảnh của Scope để Agent tham chiếu khi làm việc:',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),

            if (_selectedDocs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderDark, width: 0.8),
                ),
                child: const Text(
                  'Chưa chọn file tài liệu nào (Hỗ trợ .md, .txt, .pdf, .json, .yaml, .doc...)',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                ),
              )
            else
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 110),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.4), width: 0.8),
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedDocs.map((docPath) {
                      final fileName = p.basename(docPath);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.description_rounded, size: 12, color: AppColors.accentCyan),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Tooltip(
                                message: docPath,
                                child: Text(
                                  fileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: AppColors.textBody,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedDocs.remove(docPath);
                                });
                              },
                              borderRadius: BorderRadius.circular(3),
                              child: const Padding(
                                padding: EdgeInsets.all(1),
                                child: Icon(Icons.close_rounded, size: 12, color: AppColors.danger),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onSelect(null, const []);
            Navigator.pop(context);
          },
          child: const Text('Xóa giới hạn', style: TextStyle(color: AppColors.danger)),
        ),
        ElevatedButton(
          onPressed: () {
            final val = _controller.text.trim();
            widget.onSelect(val.isEmpty ? null : val, _selectedDocs);
            Navigator.pop(context);
          },
          child: const Text('Áp dụng Scope'),
        ),
      ],
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      final lg = element.attributes['class'] as String;
      if (lg.startsWith('language-')) {
        language = lg.substring('language-'.length);
      }
    }

    final code = element.textContent;
    final isMultiLine = code.contains('\n') || language.isNotEmpty;

    if (!isMultiLine) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: AppColors.codeBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Text(
          code,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: AppColors.terminalGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return _CodeBlockWidget(
      code: code.trim(),
      language: language.trim(),
    );
  }
}

class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;

  const _CodeBlockWidget({required this.code, required this.language});

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;
  bool _isExpanded = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      setState(() => _copied = true);
      AppToast.success(context, 'Đã sao chép vào bộ nhớ tạm!');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  void _runCommand() {
    final chat = context.read<ChatProvider>();
    final serverProvider = context.read<ServerProvider>();
    final workingDir = chat.currentSession?.workingDirScope;
    final server = serverProvider.selectedServer;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.12),
      builder: (ctx) => _CommandRunnerModal(
        command: widget.code,
        workingDir: workingDir,
        server: server,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanLg = widget.language.toLowerCase().trim();
    
    // Danh sách ngôn ngữ thuần mã nguồn / cấu hình không phải lệnh thực thi terminal
    const nonExecutableLangs = {
      'dart', 'flutter', 'javascript', 'js', 'typescript', 'ts', 'jsx', 'tsx',
      'python', 'py', 'java', 'c', 'cpp', 'csharp', 'cs', 'go', 'golang', 'rust', 'rs',
      'html', 'css', 'scss', 'sass', 'json', 'yaml', 'yml', 'xml', 'sql', 'php',
      'kotlin', 'kt', 'swift', 'ruby', 'rb', 'scala', 'r', 'markdown', 'md', 'text', 'txt'
    };

    const shellLangs = {
      'bash', 'sh', 'shell', 'zsh', 'cmd', 'terminal', 'powershell', 'ps1', 'env'
    };

    bool isRunnable = false;
    if (shellLangs.contains(cleanLg)) {
      isRunnable = true;
    } else if (nonExecutableLangs.contains(cleanLg)) {
      isRunnable = false;
    } else if (cleanLg.isEmpty) {
      // Trường hợp không khai báo language: kiểm tra cú pháp dòng lệnh phổ biến
      final trimmed = widget.code.trim();
      if (trimmed.startsWith('\$ ') ||
          trimmed.startsWith('# ') ||
          trimmed.startsWith('sudo ') ||
          trimmed.startsWith('npm ') ||
          trimmed.startsWith('npx ') ||
          trimmed.startsWith('pnpm ') ||
          trimmed.startsWith('yarn ') ||
          trimmed.startsWith('docker ') ||
          trimmed.startsWith('git ') ||
          trimmed.startsWith('systemctl ') ||
          trimmed.startsWith('apt ') ||
          trimmed.startsWith('apt-get ') ||
          trimmed.startsWith('curl ') ||
          trimmed.startsWith('wget ') ||
          trimmed.startsWith('pip ') ||
          trimmed.startsWith('python3 ') ||
          trimmed.startsWith('flutter ')) {
        isRunnable = true;
      }
    }

    final IconData langIcon;
    if (isRunnable) {
      langIcon = Icons.terminal_rounded;
    } else if (cleanLg == 'json' || cleanLg == 'yaml' || cleanLg == 'yml' || cleanLg == 'xml') {
      langIcon = Icons.data_object_rounded;
    } else {
      langIcon = Icons.code_rounded;
    }

    final lineCount = '\n'.allMatches(widget.code).length + 1;
    final isVeryLong = lineCount > 40 || widget.code.length > 2500;
    final langLabel = widget.language.isNotEmpty ? widget.language.toUpperCase() : (isRunnable ? 'BASH' : 'CODE');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                Icon(langIcon, size: 13, color: AppColors.primaryLight),
                const SizedBox(width: 6),
                Text(
                  langLabel,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                    letterSpacing: 0.5,
                  ),
                ),
                if (lineCount > 1) ...[
                  const SizedBox(width: 8),
                  Text(
                    '($lineCount dòng)',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
                const Spacer(),
                if (isRunnable) ...[
                  Tooltip(
                    message: 'Chạy lệnh',
                    child: InkWell(
                      onTap: _runCommand,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 16,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                Tooltip(
                  message: _copied ? 'Đã sao chép' : 'Sao chép',
                  child: InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 15,
                        color: _copied ? AppColors.accent : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (isVeryLong && !_isExpanded) ? 360.0 : double.infinity,
            ),
            child: SingleChildScrollView(
              physics: (isVeryLong && !_isExpanded) ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  widget.code,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: isRunnable ? const Color(0xFF4ADE80) : AppColors.textBody,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          if (isVeryLong)
            InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  border: Border(top: BorderSide(color: Color(0xFF1E293B))),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: AppColors.accentCyan,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isExpanded ? 'Thu gọn code' : 'Mở rộng toàn bộ ($lineCount dòng)',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommandRunnerModal extends StatefulWidget {
  final String command;
  final String? workingDir;
  final ServerModel? server;

  const _CommandRunnerModal({
    required this.command,
    this.workingDir,
    this.server,
  });

  @override
  State<_CommandRunnerModal> createState() => _CommandRunnerModalState();
}

class _CommandRunnerModalState extends State<_CommandRunnerModal> {
  final StringBuffer _logs = StringBuffer();
  final ScrollController _scrollController = ScrollController();
  Process? _localProcess;
  SSHClient? _sshClient;
  bool _isRunning = false;
  bool _isMinimized = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _startExecution();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startExecution() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
    });

    final isLocal = widget.server == null ||
        widget.server!.name == 'Local Machine' ||
        widget.server!.name == 'Local' ||
        widget.server!.name == 'localhost' ||
        widget.server!.serverIp == '127.0.0.1';

    if (isLocal) {
      try {
        final home = Platform.environment['HOME'] ?? (Platform.isLinux ? '/home/yenai' : '');
        final env = Map<String, String>.from(Platform.environment);
        final extraPaths = <String>[
          '$home/.gemini/antigravity-cli/bin',
          '$home/.local/go/bin',
          '$home/.local/bin',
          '$home/bin',
          '$home/.cargo/bin',
          '$home/.bun/bin',
          '/usr/local/sbin',
          '/usr/local/bin',
          '/usr/sbin',
          '/usr/bin',
          '/sbin',
          '/bin',
          '/snap/bin',
        ];
        final nvmDir = Directory('$home/.nvm/versions/node');
        if (nvmDir.existsSync()) {
          try {
            for (final dir in nvmDir.listSync()) {
              final binPath = '${dir.path}/bin';
              if (Directory(binPath).existsSync()) {
                extraPaths.add(binPath);
              }
            }
          } catch (_) {}
        }
        final currentPath = env['PATH'] ?? '';
        final fullPath = '${extraPaths.join(':')}:$currentPath';
        env['PATH'] = fullPath;
        if (home.isNotEmpty) env['HOME'] = home;

        String effectiveDir = widget.workingDir ?? Directory.current.path;
        if (!Directory(effectiveDir).existsSync()) {
          effectiveDir = Directory.current.path;
        }

        _logs.writeln('[Local]: $effectiveDir');
        _logs.writeln('\$ ${widget.command}\n');
        setState(() {});

        final fullCommand = 'export PATH="$fullPath"; [ -f "\$HOME/.nvm/nvm.sh" ] && . "\$HOME/.nvm/nvm.sh" 2>/dev/null; ${widget.command}';
        final process = await Process.start(
          'bash',
          ['-c', fullCommand],
          workingDirectory: effectiveDir,
          environment: env,
          runInShell: true,
        );
        _localProcess = process;

        process.stdout.transform(utf8.decoder).listen((data) {
          if (!mounted) return;
          setState(() {
            _logs.write(data);
          });
          _scrollToBottom();
        });

        process.stderr.transform(utf8.decoder).listen((data) {
          if (!mounted) return;
          setState(() {
            _logs.write(data);
          });
          _scrollToBottom();
        });

        final code = await process.exitCode.timeout(
          const Duration(minutes: 5),
          onTimeout: () {
            try {
              process.kill(ProcessSignal.sigkill);
            } catch (_) {}
            return -999;
          },
        );
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          if (code == -999) {
            _logs.writeln('\n[Hết thời gian chờ]: Lệnh đã tự động dừng sau 5 phút.');
          } else {
            _logs.writeln('\n[Hoàn tất]: Tiến trình kết thúc ($code)');
          }
        });
        _scrollToBottom();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          _logs.writeln('\n[Lỗi thực thi]: $e');
        });
      }
    } else {
      // Remote SSH execution
      try {
        _logs.writeln('🖥️ [Máy chủ ${widget.server!.name}]: Khởi chạy SSH...');
        _logs.writeln('\$ ${widget.command}\n');
        setState(() {});

        final sshService = NativeSshService();
        final client = await sshService.getClient(server: widget.server!);
        _sshClient = client;

        String remoteCmd = widget.command;
        if (widget.workingDir != null && widget.workingDir!.isNotEmpty) {
          remoteCmd = 'cd ${widget.workingDir} && ${widget.command}';
        }

        final session = await client.execute(remoteCmd);

        session.stdout.listen((data) {
          if (!mounted) return;
          setState(() {
            _logs.write(utf8.decode(data, allowMalformed: true));
          });
          _scrollToBottom();
        });

        session.stderr.listen((data) {
          if (!mounted) return;
          setState(() {
            _logs.write(utf8.decode(data, allowMalformed: true));
          });
          _scrollToBottom();
        });

        await session.done;
        client.close();
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          _logs.writeln('\n[Hoàn tất]: Lệnh SSH đã xong.');
        });
        _scrollToBottom();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          _logs.writeln('\n[Lỗi SSH]: $e');
        });
      }
    }
  }

  void _stopExecution() {
    try {
      _localProcess?.kill(ProcessSignal.sigkill);
      _localProcess = null;
    } catch (_) {}
    try {
      _sshClient?.close();
      _sshClient = null;
    } catch (_) {}
    setState(() {
      _isRunning = false;
      _logs.writeln('\n[Đã dừng bởi người dùng]');
    });
  }

  void _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _logs.toString()));
    if (mounted) {
      AppToast.success(context, 'Đã sao chép toàn bộ log!');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    try {
      _localProcess?.kill();
    } catch (_) {}
    try {
      _sshClient?.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLocal = widget.server == null ||
        widget.server!.name == 'Local Machine' ||
        widget.server!.name == 'Local' ||
        widget.server!.name == 'localhost' ||
        widget.server!.serverIp == '127.0.0.1';

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final double dialogWidth = _isMaximized
        ? (screenWidth * 0.85).clamp(600.0, 900.0)
        : (_isMinimized ? 380.0 : 500.0);
    final double dialogHeight = _isMaximized
        ? (screenHeight * 0.8).clamp(450.0, 650.0)
        : (_isMinimized ? 44.0 : 310.0);

    return Dialog(
      alignment: _isMaximized ? Alignment.center : Alignment.bottomLeft,
      insetPadding: _isMaximized
          ? const EdgeInsets.all(24)
          : const EdgeInsets.only(left: 20, bottom: 20),
      backgroundColor: const Color(0xFF090D16),
      elevation: 20,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF30363D), width: 1.2),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        width: dialogWidth,
        height: dialogHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            children: [
              // Header Bar (always visible)
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF161B22),
                  border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal_rounded, size: 15, color: AppColors.accentCyan),
                    const SizedBox(width: 7),
                    Text(
                      _isMinimized ? 'Console: ${widget.command}' : 'Console Runner',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textWhite,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: (isLocal ? AppColors.accent : AppColors.primaryLight).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isLocal ? 'Local' : (widget.server?.name ?? 'Server'),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: isLocal ? AppColors.accent : AppColors.primaryLight,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_isRunning) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.accentCyan,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Đang chạy',
                        style: TextStyle(fontSize: 10, color: AppColors.accentCyan, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Minimize / Restore Toggle
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isMinimized = !_isMinimized;
                          if (_isMinimized) _isMaximized = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _isMinimized ? Icons.open_in_full_rounded : Icons.remove_rounded,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (!_isMinimized) ...[
                      const SizedBox(width: 4),
                      // Maximize / Normalize Toggle
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isMaximized = !_isMaximized;
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            _isMaximized ? Icons.close_fullscreen_rounded : Icons.crop_square_rounded,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    // Close Button
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),

              // Body content (only rendered when NOT minimized)
              if (!_isMinimized) ...[
                // Command banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  color: const Color(0xFF0F172A),
                  child: Text(
                    '\$ ${widget.command.replaceAll('\n', ' && ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF67E8F9),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Console output stream
                Expanded(
                  child: Container(
                    color: const Color(0xFF070A10),
                    padding: const EdgeInsets.all(10),
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Text(
                          _logs.toString().isNotEmpty ? _logs.toString() : 'Đang chuẩn bị...',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Color(0xFFE2E8F0),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Footer Actions
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161B22),
                    border: Border(top: BorderSide(color: Color(0xFF30363D))),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _logs.isNotEmpty ? _copyLogs : null,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF21262D),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF30363D)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded, size: 11, color: AppColors.textBody),
                              SizedBox(width: 4),
                              Text('Chép Log', style: TextStyle(fontSize: 10.5, color: AppColors.textBody)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isRunning)
                        InkWell(
                          onTap: _stopExecution,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.6)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stop_rounded, size: 12, color: AppColors.danger),
                                SizedBox(width: 4),
                                Text('Dừng', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.danger)),
                              ],
                            ),
                          ),
                        )
                      else
                        InkWell(
                          onTap: _startExecution,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.6)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh_rounded, size: 12, color: AppColors.primaryLight),
                                SizedBox(width: 4),
                                Text('Chạy lại', style: TextStyle(fontSize: 10.5, color: AppColors.primaryLight)),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF21262D),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Đóng',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
                  message: 'Cuộn tới câu hỏi này',
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
