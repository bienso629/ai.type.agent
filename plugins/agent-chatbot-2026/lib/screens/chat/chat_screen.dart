import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo_widget.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/attachment_item.dart';
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
  final ApiService _apiService = ApiService();
  ApiService get _api => _apiService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isRightSidebarOpen = true;
  final TextEditingController _sessionSearchController = TextEditingController();
  bool _isSearchingSessions = false;
  String? _workingDirScope;
  final List<AttachmentItem> _attachedFiles = [];

  // Inline slash autocomplete state
  List<String> _inlineDirSuggestions = [];
  bool _isInlineDirLoading = false;
  String _currentSlashWord = '';
  int _inlineActiveIndex = 0;
  Timer? _dirDebounceTimer;
  int _inputCharCount = 0;
  static const int _maxInputChars = 100000;

  String? _lastSessionId;
  String _lastTrackedContent = '';
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);
    _inputFocusNode.onKeyEvent = _handleInputKeyEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      final server = context.read<ServerProvider>();
      server.loadServers();
      if (chat.currentSession != null) {
        _safeScrollToBottom(instant: true);
      } else if (chat.sessions.isNotEmpty) {
        chat.selectSession(chat.sessions.first).then((_) {
          _safeScrollToBottom(instant: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _dirDebounceTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _sessionSearchController.dispose();
    _inputFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
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
      }
    }
    return KeyEventResult.ignored;
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (_inputCharCount != text.length) {
      if ((text.length > 5000 && (_inputCharCount / 1000).floor() != (text.length / 1000).floor()) ||
          (text.length <= 5000 && (_inputCharCount == 0 || text.isEmpty || (_inputCharCount - text.length).abs() > 20))) {
        setState(() {
          _inputCharCount = text.length;
        });
      } else {
        _inputCharCount = text.length;
      }
    }

    final selection = _textController.selection;
    if (selection.baseOffset < 0) {
      if (_inlineDirSuggestions.isNotEmpty) {
        setState(() => _inlineDirSuggestions.clear());
      }
      return;
    }

    final cursor = selection.baseOffset;
    // Tối ưu: Chỉ quét 60 ký tự gần nhất trước con trỏ để tìm '/' thay vì quét toàn bộ chuỗi siêu dài
    final searchStart = (cursor > 60) ? cursor - 60 : 0;
    final textUpToCursor = text.substring(searchStart, cursor);
    final match = RegExp(r'(?:^|\s)(/[^\s]*)$').firstMatch(textUpToCursor);

    if (match != null) {
      final word = match.group(1) ?? '/';
      _currentSlashWord = word;
      _dirDebounceTimer?.cancel();
      _dirDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
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
    setState(() {
      _workingDirScope = dir;
      final text = _textController.text;
      final idx = text.lastIndexOf(_currentSlashWord);
      if (idx != -1) {
        _textController.text = (text.substring(0, idx) + text.substring(idx + _currentSlashWord.length)).trim();
      }
      _inlineDirSuggestions.clear();
      _currentSlashWord = '';
    });
    AppToast.success(context, 'Đã đặt phạm vi Agent: $dir');
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
              path: kIsWeb ? null : f.path,
            );
          } else if (!kIsWeb && f.path != null) {
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
      final res = await _api.uploadFile(
        fileName: item.name,
        bytes: item.rawBytes,
        localFilePath: item.path,
        targetDir: _workingDirScope,
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
              borderRadius: BorderRadius.circular(8),
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

    if (text.length > _maxInputChars) {
      AppToast.error(context, 'Prompt quá dài (${text.length}/$_maxInputChars ký tự). Vui lòng rút gọn để tránh treo app!');
      return;
    }

    // Await any in-flight uploads if necessary (cho phép tối đa 600s = 10 phút cho tệp 5-10GB)
    if (_attachedFiles.any((a) => a.isUploading)) {
      int waitMs = 0;
      while (_attachedFiles.any((a) => a.isUploading) && waitMs < 600000 && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        waitMs += 500;
      }
    }

    final attachmentsToSend = _attachedFiles.isNotEmpty ? List<AttachmentItem>.from(_attachedFiles) : null;
    _textController.clear();
    setState(() {
      _attachedFiles.clear();
    });

    chat.sendMessage(
      text,
      model: serverProvider.currentAiModel,
      attachments: attachmentsToSend,
      workingDir: _workingDirScope,
    );
    _safeScrollToBottom();
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
      final isNearBottom = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent - _scrollController.position.pixels < 300);
      final isNewUserMessage = chat.messages.isNotEmpty && chat.messages.last.role == 'user';
      _lastMessageCount = chat.messages.length;
      _lastTrackedContent = chat.messages.isNotEmpty ? chat.messages.last.content : '';
      if (isNearBottom || isNewUserMessage) {
        _safeScrollToBottom();
      }
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
                        const AppLogoWidget(
                          width: 32,
                          height: 32,
                          borderRadius: 6,
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
                              chat.currentSession?.title ?? 'AI Chatbot Assistant',
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
                          'AI Agent hiểu mục tiêu, lập kế hoạch cho công việc của bạn.',
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
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                // ignore: deprecated_member_use
                                cacheExtent: 400.0,
                                itemCount: chat.hasMoreMessages
                                    ? chat.messages.length + 1
                                    : chat.messages.length,
                                findChildIndexCallback: (Key key) {
                                  if (key is ValueKey<String>) {
                                    final val = key.value;
                                    if (val.startsWith('msg_')) {
                                      final idStr = val.split('_')[1];
                                      final id = int.tryParse(idStr);
                                      if (id != null) {
                                        final idx = chat.messages.indexWhere((m) => m.id == id);
                                        if (idx != -1) return chat.hasMoreMessages ? idx + 1 : idx;
                                      }
                                    }
                                  }
                                  return null;
                                },
                                itemBuilder: (context, idx) {
                                  if (chat.hasMoreMessages) {
                                    if (idx == 0) {
                                      return _buildLoadMoreBanner(chat);
                                    }
                                    final msg = chat.messages[idx - 1];
                                    return _buildMessageItem(msg, chat);
                                  }
                                  final msg = chat.messages[idx];
                                  return _buildMessageItem(msg, chat);
                                },
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


  Widget _buildMessageItem(ChatMessageModel msg, ChatProvider chat) {
    return _MessageItemWidget(
      key: ValueKey('msg_${msg.id}_${msg.role}_${msg.isStreaming}'),
      msg: msg,
      onDownloadAttachment: _downloadAttachment,
      onRetry: (content) {
        chat.sendMessage(content);
        _safeScrollToBottom();
      },
      onExportPdf: (m) async {
        final server = context.read<ServerProvider>().selectedServer;
        final srvInfo = server?.name ?? 'AI Agent Local';
        AppToast.info(context, 'Đang tạo và lưu tài liệu PDF chuẩn A4...');
        try {
          final path = await PdfExportService.exportMessageToPdf(m, serverInfo: srvInfo);
          if (mounted) {
            AppToast.success(context, 'Đã lưu PDF tại Downloads: ${path?.split('/').last ?? ''}');
          }
        } catch (e) {
          if (mounted) {
            AppToast.error(context, 'Lỗi xuất PDF: $e');
          }
        }
      },
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

                      return Container(
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
                                borderRadius: BorderRadius.circular(2),
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
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            if (_inlineDirSuggestions.isNotEmpty || _isInlineDirLoading) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.flash_on_rounded, size: 14, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Text(
                              'Gợi ý thư mục VPS (${_currentSlashWord.isNotEmpty ? _currentSlashWord : '/'}):',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                            ),
                          ],
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
                                      borderRadius: BorderRadius.circular(3),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(3),
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
                                      borderRadius: BorderRadius.circular(3),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.inputBg,
                                          borderRadius: BorderRadius.circular(3),
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
              maxLines: 8,
              maxLength: _maxInputChars,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                if (currentLength > 1000) {
                  final isNearLimit = currentLength > (_maxInputChars * 0.8);
                  return Container(
                    padding: const EdgeInsets.only(top: 2),
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$currentLength / $maxLength ký tự',
                      style: TextStyle(
                        fontSize: 10,
                        color: isNearLimit ? AppColors.danger : AppColors.textMuted,
                        fontWeight: isNearLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }
                return null;
              },
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
                        side: BorderSide(
                          color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.borderDark,
                        ),
                        backgroundColor: _attachedFiles.isNotEmpty ? AppColors.accentCyan.withValues(alpha: 0.1) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
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
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: chat.isGenerating ? AppColors.danger : AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: Icon(chat.isGenerating ? Icons.stop_rounded : Icons.send_rounded, size: 14),
                  label: Text(chat.isGenerating ? 'Dừng' : 'Gửi', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: chat.isGenerating
                      ? () => chat.stopGenerating()
                      : () => _handleSend(chat, serverProvider),
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
            child: _isSearchingSessions
                ? SizedBox(
                    height: 24,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_rounded, size: 16, color: AppColors.primaryLight),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _sessionSearchController,
                            autofocus: true,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                            decoration: const InputDecoration(
                              hintText: 'Tìm kiếm hội thoại...',
                              hintStyle: TextStyle(fontSize: 12, color: AppColors.textDim),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textDim),
                          tooltip: 'Đóng tìm kiếm',
                          onPressed: () {
                            setState(() {
                              _isSearchingSessions = false;
                              _sessionSearchController.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  )
                : Row(
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
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        icon: const Icon(Icons.search_rounded, size: 18, color: AppColors.primaryLight),
                        tooltip: 'Tìm kiếm hội thoại',
                        onPressed: () {
                          setState(() {
                            _isSearchingSessions = true;
                          });
                        },
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: () {
              final query = _sessionSearchController.text.trim().toLowerCase();
              final filteredSessions = query.isEmpty
                  ? chat.sessions
                  : chat.sessions.where((s) => s.title.toLowerCase().contains(query)).toList();

              if (filteredSessions.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      query.isEmpty ? 'Chưa có hội thoại nào' : 'Không tìm thấy hội thoại phù hợp',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(6),
                itemCount: filteredSessions.length,
                itemBuilder: (context, idx) {
                  final sess = filteredSessions[idx];
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
                    );
              }(),
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



// ---------------------------------------------------------------------------
// High-Performance Virtualized Message Item Widget
// ---------------------------------------------------------------------------

class _MessageItemWidget extends StatelessWidget {
  final ChatMessageModel msg;
  final void Function(AttachmentItem) onDownloadAttachment;
  final void Function(String) onRetry;
  final void Function(ChatMessageModel) onExportPdf;

  const _MessageItemWidget({
    super.key,
    required this.msg,
    required this.onDownloadAttachment,
    required this.onRetry,
    required this.onExportPdf,
  });

  static final MarkdownStyleSheet _sharedStyleSheet = MarkdownStyleSheet(
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
  );

  String _formatSessionTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const AppLogoWidget(
                width: 30,
                height: 30,
                borderRadius: 6,
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
                        if (msg.attachments.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: msg.attachments.map((att) {
                              return Material(
                                color: AppColors.bgDark,
                                borderRadius: BorderRadius.circular(4),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => onDownloadAttachment(att),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
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
                                            style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '(${att.formattedSize})',
                                          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.download_rounded,
                                          size: 14,
                                          color: AppColors.accentCyan,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (msg.content.isNotEmpty) const SizedBox(height: 8),
                        ],
                        if (msg.content.isNotEmpty)
                          MarkdownBody(
                            data: msg.content,
                            selectable: true,
                            styleSheet: _sharedStyleSheet,
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
                          ...msg.toolExecutions.map((tool) => _ToolCardWidget(tool: tool)),
                        ],
                      ],
                    ),
                  ),

                  // Message Action Bar (Timestamp, Copy, Retry, PDF)
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
                            onTap: () => onExportPdf(msg),
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
                            onTap: () => onRetry(msg.content),
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
      ),
    );
  }
}

class _ToolCardWidget extends StatelessWidget {
  final ToolExecutionItem tool;

  const _ToolCardWidget({required this.tool});

  @override
  Widget build(BuildContext context) {
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
}

