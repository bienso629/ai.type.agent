import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../models/attachment_item.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<ChatSessionModel> _sessions = [];
  ChatSessionModel? _currentSession;
  List<ChatMessageModel> _messages = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = false;
  int _oldestMessageId = 0;
  bool _isGenerating = false;
  String _currentStatus = '';
  StreamSubscription? _streamSub;

  List<ChatSessionModel> get sessions => _sessions;
  ChatSessionModel? get currentSession => _currentSession;
  List<ChatMessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreMessages => _hasMoreMessages;
  int get oldestMessageId => _oldestMessageId;
  bool get isGenerating => _isGenerating;
  String get currentStatus => _currentStatus;

  // Quick Action Chips
  final List<String> quickPrompts = [
    '📊 Kiểm tra tài nguyên CPU/RAM',
    '🔄 Khởi động lại Nginx Web Server',
    '⚡ Top 5 tiến trình ngốn CPU nhất',
    '🛡️ Kiểm tra trạng thái tường lửa UFW',
    '🧹 Dọn dẹp RAM Cache & Disk Log',
    '🔍 Xem 20 dòng log lỗi mới nhất',
  ];

  ChatProvider() {
    initChat();
  }

  void _sortSessions() {
    _sessions.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> initChat() async {
    await loadSessions(silent: true);
    if (_sessions.isNotEmpty) {
      final target = (_currentSession != null && _sessions.any((s) => s.id == _currentSession!.id))
          ? _sessions.firstWhere((s) => s.id == _currentSession!.id)
          : _sessions.first;
      await selectSession(target);
    } else {
      await createNewSession();
    }
  }

  Future<void> loadSessions({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final list = await _api.getChatSessions();
      _sessions = list;
      _sortSessions();
      if (_currentSession != null) {
        final match = _sessions.where((s) => s.id == _currentSession!.id);
        if (match.isNotEmpty) {
          _currentSession = match.first;
        } else {
          if (_sessions.isNotEmpty) {
            _currentSession = _sessions.first;
          } else {
            _currentSession = null;
          }
        }
      } else if (_sessions.isNotEmpty) {
        _currentSession = _sessions.first;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createNewSession({String title = 'Cuộc hội thoại mới', String? targetServer}) async {
    try {
      final newSess = await _api.createChatSession(title: title, targetServer: targetServer);
      _sessions.removeWhere((s) => s.id == newSess.id);
      _sessions.insert(0, newSess);
      _sortSessions();
      await selectSession(newSess);
    } catch (_) {
      final fallbackSess = ChatSessionModel(
        id: 'sess_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        targetServer: targetServer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _sessions.insert(0, fallbackSess);
      _sortSessions();
      await selectSession(fallbackSess);
    }
  }

  Future<void> setServerForCurrentSession(String? serverName) async {
    if (_currentSession == null) {
      await createNewSession(targetServer: serverName);
      return;
    }
    final cleanServer = (serverName != null && serverName.trim().isNotEmpty) ? serverName.trim() : null;
    final now = DateTime.now();
    final updated = _currentSession!.copyWith(
      targetServer: cleanServer,
      clearTargetServer: cleanServer == null,
      updatedAt: now,
    );
    _currentSession = updated;
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _sessions[idx] = updated;
      _sortSessions();
    }
    notifyListeners();
    await _api.updateChatSessionServer(updated.id, cleanServer);
  }

  String? get currentSessionScope => _currentSession?.workingDirScope;

  Future<void> setScopeForCurrentSession(String? scope) async {
    if (_currentSession == null) {
      await createNewSession();
    }
    final cleanScope = (scope != null && scope.trim().isNotEmpty) ? scope.trim() : null;
    final now = DateTime.now();
    final updated = _currentSession!.copyWith(
      workingDirScope: cleanScope,
      clearWorkingDirScope: cleanScope == null,
      updatedAt: now,
    );
    _currentSession = updated;
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _sessions[idx] = updated;
      _sortSessions();
    }
    notifyListeners();
    await _api.updateChatSessionScope(updated.id, cleanScope);
  }

  Future<void> selectSession(ChatSessionModel session) async {
    _currentSession = session;
    _messages = [];
    _hasMoreMessages = false;
    _isLoadingMore = false;
    _oldestMessageId = 0;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.getChatHistory(
        session.id,
        limitQuestions: 3,
        beforeId: 0,
      );
      _messages = result.messages;
      _hasMoreMessages = result.hasMore;
      _oldestMessageId = result.oldestId;
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreMessages() async {
    if (_currentSession == null || _isLoadingMore || !_hasMoreMessages) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _api.getChatHistory(
        _currentSession!.id,
        limitQuestions: 3,
        beforeId: _oldestMessageId,
      );

      if (result.messages.isNotEmpty) {
        _messages.insertAll(0, result.messages);
        _hasMoreMessages = result.hasMore;
        if (result.oldestId > 0) {
          _oldestMessageId = result.oldestId;
        }
      } else {
        _hasMoreMessages = false;
      }
    } catch (_) {
      _hasMoreMessages = false;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> pinSession(ChatSessionModel session) async {
    final newPinState = !session.isPinned;
    // 1. Optimistic local update
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      final updated = session.copyWith(
        isPinned: newPinState,
      );
      _sessions[idx] = updated;
      _sortSessions();
      if (_currentSession?.id == session.id) {
        _currentSession = updated;
      }
      notifyListeners();
    }

    // 2. Sync with SQLite
    await _api.pinChatSession(session.id, newPinState);
    await loadSessions(silent: true);
  }

  Future<void> updateSession(
    ChatSessionModel session, {
    String? newTitle,
    String? newTargetServer,
  }) async {
    final cleanTitle = newTitle?.trim();
    final cleanServer = newTargetServer?.trim();

    final finalTitle = (cleanTitle != null && cleanTitle.isNotEmpty) ? cleanTitle : session.title;
    final finalServer = (cleanServer != null && cleanServer.isNotEmpty) ? cleanServer : (session.targetServer ?? 'Local Machine');

    // 1. Optimistic local update
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      final updated = session.copyWith(
        title: finalTitle,
        targetServer: finalServer,
        updatedAt: DateTime.now(),
      );
      _sessions[idx] = updated;
      _sortSessions();
      if (_currentSession?.id == session.id) {
        _currentSession = updated;
      }
      notifyListeners();
    }

    // 2. Sync with SQLite
    if (cleanTitle != null && cleanTitle.isNotEmpty && cleanTitle != session.title) {
      await _api.renameChatSession(session.id, cleanTitle);
    }
    if (cleanServer != null && cleanServer.isNotEmpty && cleanServer != session.targetServer) {
      await _api.updateChatSessionServer(session.id, cleanServer);
    }
    await loadSessions(silent: true);
  }

  Future<void> renameSession(ChatSessionModel session, String newTitle) async {
    await updateSession(session, newTitle: newTitle);
  }

  Future<void> deleteSession(String sessionId) async {
    await _api.deleteChatSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isNotEmpty) {
        await selectSession(_sessions.first);
      } else {
        _currentSession = null;
        _messages = [];
        _hasMoreMessages = false;
        _oldestMessageId = 0;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
    await loadSessions(silent: true);
  }

  Future<void> deleteAllSessions() async {
    await _api.deleteAllChatSessions();
    _sessions.clear();
    _currentSession = null;
    _messages.clear();
    _hasMoreMessages = false;
    _oldestMessageId = 0;
    notifyListeners();
    await loadSessions(silent: true);
  }

  Future<void> clearHistory() async {
    if (_currentSession == null) return;
    await _api.clearChatHistory(_currentSession!.id);
    _messages.clear();
    _hasMoreMessages = false;
    _oldestMessageId = 0;
    notifyListeners();
  }

  Future<void> sendMessage(
    String text, {
    String? model,
    List<AttachmentItem>? attachments,
    String? workingDir,
    String? targetServer,
  }) async {
    final query = text.trim();
    if ((query.isEmpty && (attachments == null || attachments.isEmpty)) || _isGenerating) return;

    if (_currentSession == null) {
      await createNewSession(targetServer: targetServer);
    } else if (targetServer != null && targetServer.isNotEmpty && (_currentSession!.targetServer == null || _currentSession!.targetServer!.isEmpty)) {
      await setServerForCurrentSession(targetServer);
    }

    final sessionId = _currentSession!.id;

    // Touch and update session timestamp so it moves to top
    final now = DateTime.now();
    _currentSession = _currentSession!.copyWith(updatedAt: now);
    final sIdx = _sessions.indexWhere((s) => s.id == sessionId);
    if (sIdx != -1) {
      _sessions[sIdx] = _currentSession!;
      _sortSessions();
    }

    // 1. Add User Message
    final userMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'user',
      content: query.isNotEmpty ? query : 'Đã đính kèm ${attachments?.length ?? 0} tệp',
      model: model ?? 'glm-5.3',
      attachments: attachments,
    );
    _messages.add(userMsg);

    // 2. Add Placeholder Assistant Message
    final assistantMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'assistant',
      content: '',
      model: model ?? 'glm-5.3',
      isStreaming: true,
      statusMessage: 'Đang kết nối AI...',
    );
    _messages.add(assistantMsg);

    _isGenerating = true;
    _currentStatus = 'Đang suy nghĩ...';
    notifyListeners();

    // Prepare history snapshot
    final historySnap = _messages
        .where((m) => m.content.isNotEmpty && m != assistantMsg)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    _streamSub?.cancel();
    _streamSub = _api.streamChatMessage(
      sessionId: sessionId,
      message: query.isNotEmpty ? query : 'Vui lòng đọc và phân tích các tệp đính kèm.',
      model: model,
      attachments: attachments,
      history: historySnap,
      workingDir: workingDir ?? _currentSession?.workingDirScope,
      targetServer: targetServer ?? _currentSession?.targetServer,
      onToken: (token) {
        assistantMsg.content += token;
        assistantMsg.statusMessage = null;
        notifyListeners();
      },
      onStatus: (status) {
        _currentStatus = status;
        assistantMsg.statusMessage = status;
        notifyListeners();
      },
      onTool: (tool) {
        assistantMsg.toolExecutions.add(tool);
        assistantMsg.statusMessage = 'Đã chạy lệnh: ${tool.command}';
        notifyListeners();
      },
      onDone: (fullReply) {
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (fullReply.isNotEmpty && assistantMsg.content.isEmpty) {
          assistantMsg.content = fullReply;
        }
        _isGenerating = false;
        _currentStatus = '';
        notifyListeners();
        loadSessions(silent: true); // Refresh session list & titles
      },
      onError: (err) {
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (assistantMsg.content.isEmpty) {
          assistantMsg.content = '❌ Lỗi: $err';
        }
        _isGenerating = false;
        _currentStatus = '';
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
