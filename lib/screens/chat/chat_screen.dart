import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/clipboard_service.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/server_model.dart';
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
  final TextEditingController _sessionSearchCtrl = TextEditingController();
  final FocusNode _sessionSearchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isRightSidebarOpen = true;
  bool _isSessionSearchOpen = false;
  final List<AttachmentItem> _attachedFiles = [];
  String _sessionSearchQuery = '';

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

  String _getMessageKey(ChatMessageModel msg, int index) {
    if (msg.id != null) return 'msg_id_${msg.id}';
    return 'msg_${msg.createdAt.millisecondsSinceEpoch}_${msg.role}_$index';
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
      server.loadServers();
      chat.loadSessions().then((_) {
        if (chat.currentSession != null) {
          chat.selectSession(chat.currentSession!).then((_) {
            _safeScrollToBottom(instant: true);
          });
        } else if (chat.sessions.isNotEmpty) {
          chat.selectSession(chat.sessions.first).then((_) {
            _safeScrollToBottom(instant: true);
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _dirDebounceTimer?.cancel();
    _sessionSearchFocusNode.dispose();
    _sessionSearchCtrl.dispose();
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
      }
    }
    return KeyEventResult.ignored;
  }

  void _onTextChanged() {
    final text = _textController.text;
    final selection = _textController.selection;
    if (selection.baseOffset < 0) {
      if (_inlineDirSuggestions.isNotEmpty) {
        setState(() => _inlineDirSuggestions.clear());
      }
      return;
    }

    final cursor = selection.baseOffset;
    final textUpToCursor = text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)(/[^\s]*)$').firstMatch(textUpToCursor);

    if (match != null) {
      final word = match.group(1) ?? '/';
      _currentSlashWord = word;
      _dirDebounceTimer?.cancel();
      _dirDebounceTimer = Timer(const Duration(milliseconds: 120), () async {
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

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingOlder) return;
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
        onSelect: (val) {
          chat.setScopeForCurrentSession(val);
          if (val != null) {
            AppToast.success(context, 'Đã gán Scope cho cuộc hội thoại này: $val');
          } else {
            AppToast.info(context, 'Đã xóa giới hạn Scope của cuộc hội thoại');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final serverProvider = context.watch<ServerProvider>();

    // 1. Chỉ cuộn xuống cuối khi lần đầu chọn/mở Hộp hội thoại
    if (_lastSessionId != chat.currentSession?.id) {
      _lastSessionId = chat.currentSession?.id;
      _wasGenerating = chat.isGenerating;
      _safeScrollToBottom(instant: true);
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
                Row(
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
                              chat.currentSession?.title ?? 'AI Type Agent',
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
                                '💻 Gắn với: Local Machine (${Platform.operatingSystem}) • Thực thi an toàn trên shell cục bộ',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              );
                            } else {
                              return Text(
                                '🖥️ Gắn với Máy chủ: $currentServerName • Mọi lệnh terminal được gửi qua SSH tới máy chủ này',
                                style: const TextStyle(fontSize: 11, color: AppColors.primaryLight),
                              );
                            }
                          },
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
                      onPressed: () => chat.createNewSession(
                        targetServer: serverProvider.selectedServer?.name ?? 'Local Machine',
                      ),
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
                                reverse: true,
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
                                  return _buildMessageItem(msg, chat, msgIndex);
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
    ),
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

    return Padding(
      key: _messageKeys.putIfAbsent(keyStr, () => GlobalKey()),
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
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
                    borderRadius: BorderRadius.circular(4),
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
                          builders: {
                            'code': CodeElementBuilder(context),
                          },
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
                            codeblockPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
        borderRadius: BorderRadius.circular(6),
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
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
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
                    borderRadius: BorderRadius.circular(3),
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
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Xóa Scope',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
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

  Widget _buildRightSessionsSidebar(ChatProvider chat) {
    final serverProvider = context.watch<ServerProvider>();
    final query = _sessionSearchQuery.trim().toLowerCase();
    final displaySessions = query.isEmpty
        ? chat.sessions
        : chat.sessions.where((s) {
            final titleMatch = s.title.toLowerCase().contains(query);
            final serverMatch = (s.targetServer ?? '').toLowerCase().contains(query);
            final dirMatch = (s.workingDirScope ?? '').toLowerCase().contains(query);
            return titleMatch || serverMatch || dirMatch;
          }).toList();

    return Container(
      width: 270,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(left: BorderSide(color: AppColors.borderDark, width: 1)),
      ),
      child: Column(
        children: [
          // Header with inline expandable Search Box
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
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
                                  borderRadius: BorderRadius.circular(10),
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
                            Icon(Icons.layers_rounded, size: 16, color: AppColors.primaryLight),
                            SizedBox(width: 8),
                            Text('Hộp Hội Thoại', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
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
                          ],
                        ),
                      ],
                    ),
            ),
          ),

          // 3. Session List
          Expanded(
            child: chat.sessions.isEmpty
                ? const Center(
                    child: Text('Chưa có hội thoại nào', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  )
                : displaySessions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.search_off_rounded, size: 28, color: AppColors.textDim),
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
                    : ListView.builder(
                        padding: const EdgeInsets.all(6),
                        itemCount: displaySessions.length,
                        itemBuilder: (context, idx) {
                          final sess = displaySessions[idx];
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
                                hoverColor: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () {
                                  chat.selectSession(sess).then((_) {
                                    _scrollToBottom(instant: true);
                                  });
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
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  child: Row(
                                    children: [
                                      // Left Pin Button
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                        hoverColor: Colors.transparent,
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        icon: Transform.rotate(
                                          angle: sess.isPinned ? -0.5 : 0,
                                          child: Icon(
                                            sess.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                            size: 13,
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
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                if (sess.isPinned)
                                                  Container(
                                                    margin: const EdgeInsets.only(right: 6),
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.warning.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                                    ),
                                                    child: const Text(
                                                      'Ghim',
                                                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.warning),
                                                    ),
                                                  ),
                                                // Target Server Badge (Static to this conversation)
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
                                                      margin: const EdgeInsets.only(right: 6),
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                      decoration: BoxDecoration(
                                                        color: badgeColor.withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            isLocal ? Icons.laptop_chromebook_rounded : Icons.dns_rounded,
                                                            size: 9.5,
                                                            color: badgeColor,
                                                          ),
                                                          const SizedBox(width: 3),
                                                          ConstrainedBox(
                                                            constraints: const BoxConstraints(maxWidth: 90),
                                                            child: Text(
                                                              serverName,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 8.5,
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
                                                Text(
                                                  _formatSessionTime(sess.updatedAt),
                                                  style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Edit Button (Rename & Server Select)
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                        hoverColor: Colors.transparent,
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        icon: const Icon(Icons.edit_outlined, size: 13, color: AppColors.textDim),
                                        tooltip: 'Chỉnh sửa hội thoại (Tên & Máy chủ)',
                                        onPressed: () => _showEditSessionDialog(chat, sess),
                                      ),
                                      // Delete Button
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                        hoverColor: Colors.transparent,
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
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
                Text(
                  query.isNotEmpty ? '${displaySessions.length}/${chat.sessions.length} hội thoại' : '${chat.sessions.length} hội thoại',
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
                if (chat.sessions.isNotEmpty)
                  TextButton(
                    onPressed: () => _showClearAllSessionsDialog(chat),
                    child: const Text('Xoá tất cả', style: TextStyle(fontSize: 11, color: AppColors.danger)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
}

class _ScopePickerDialog extends StatefulWidget {
  final String? currentScope;
  final ValueChanged<String?> onSelect;

  const _ScopePickerDialog({
    required this.currentScope,
    required this.onSelect,
  });

  @override
  State<_ScopePickerDialog> createState() => _ScopePickerDialogState();
}

class _ScopePickerDialogState extends State<_ScopePickerDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _controller;
  final FocusNode _dialogFocusNode = FocusNode();
  List<String> _suggestions = [];
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
    _dialogFocusNode.onKeyEvent = _handleDialogKeyEvent;
    _loadSuggestions(_controller.text);
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
            widget.onSelect(val);
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onSelect(null);
            Navigator.pop(context);
          },
          child: const Text('Xóa giới hạn', style: TextStyle(color: AppColors.danger)),
        ),
        ElevatedButton(
          onPressed: () {
            final val = _controller.text.trim();
            widget.onSelect(val.isEmpty ? null : val);
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
          borderRadius: BorderRadius.circular(3),
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
      language: language.isNotEmpty ? language : 'sh',
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

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      setState(() => _copied = true);
      AppToast.success(context, 'Đã sao chép câu lệnh vào bộ nhớ tạm!');
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
    final cleanLg = widget.language.toLowerCase();
    final isRunnable = cleanLg == 'bash' ||
        cleanLg == 'sh' ||
        cleanLg == 'shell' ||
        cleanLg == 'zsh' ||
        cleanLg == 'cmd' ||
        cleanLg == 'terminal' ||
        cleanLg == 'powershell' ||
        cleanLg == '' ||
        cleanLg == 'env';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 13, color: AppColors.primaryLight),
                const SizedBox(width: 6),
                Text(
                  widget.language.isNotEmpty ? widget.language.toUpperCase() : 'BASH',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (isRunnable) ...[
                  InkWell(
                    onTap: _runCommand,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 13,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Chạy lệnh',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _copied
                          ? AppColors.primary.withValues(alpha: 0.25)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _copied ? AppColors.primaryLight : const Color(0xFF334155),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 12,
                          color: _copied ? AppColors.primaryLight : AppColors.textBody,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Đã chép' : 'Sao chép',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _copied ? AppColors.primaryLight : AppColors.textBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF4ADE80),
                height: 1.45,
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

        _logs.writeln('⚡ [Local]: $effectiveDir');
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

        final code = await process.exitCode;
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          _logs.writeln('\n[Hoàn tất]: Tiến trình kết thúc ($code)');
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
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF30363D), width: 1.2),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        width: dialogWidth,
        height: dialogHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
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
                      _isMinimized ? 'Console: ${widget.command}' : '⚡ Console Runner',
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
                        borderRadius: BorderRadius.circular(3),
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
