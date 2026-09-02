import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/storage_service.dart';
import '../models/attachment_item.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<ChatSessionModel> _sessions = [];
  ChatSessionModel? _currentSession;

  // Per-session message storage and streaming states
  final Map<String, List<ChatMessageModel>> _sessionMessages = {};
  final Map<String, bool> _sessionGenerating = {};
  final Map<String, String> _sessionStatuses = {};
  final Map<String, StreamSubscription> _sessionStreams = {};
  final Map<String, bool> _sessionHasMore = {};
  final Map<String, int> _sessionOldestId = {};

  bool _isLoading = false;
  bool _isLoadingMore = false;

  List<ChatSessionModel> get sessions => _sessions;
  ChatSessionModel? get currentSession => _currentSession;

  List<ChatMessageModel> get messages =>
      _currentSession != null ? (_sessionMessages[_currentSession!.id] ?? []) : [];

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;

  bool get hasMoreMessages =>
      _currentSession != null ? (_sessionHasMore[_currentSession!.id] ?? false) : false;

  int get oldestMessageId =>
      _currentSession != null ? (_sessionOldestId[_currentSession!.id] ?? 0) : 0;

  bool get isGenerating => isSessionGenerating(_currentSession?.id);
  bool isSessionGenerating(String? sessionId) =>
      sessionId != null && (_sessionGenerating[sessionId] == true);

  String get currentStatus =>
      _currentSession != null ? (_sessionStatuses[_currentSession!.id] ?? '') : '';
  String getSessionStatus(String? sessionId) =>
      sessionId != null ? (_sessionStatuses[sessionId] ?? '') : '';

  bool get anySessionGenerating => _sessionGenerating.values.any((v) => v == true);

  // Quick Action Chips
  final List<String> quickPrompts = [
    '📊 Kiểm tra tài nguyên CPU/RAM',
    '🔄 Khởi động lại Nginx Web Server',
    'Top 5 tiến trình ngốn CPU nhất',
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
      _sessionMessages[newSess.id] = [];
      _sessionHasMore[newSess.id] = false;
      _sessionOldestId[newSess.id] = 0;
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
      _sessionMessages[fallbackSess.id] = [];
      _sessionHasMore[fallbackSess.id] = false;
      _sessionOldestId[fallbackSess.id] = 0;
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
    if (cleanScope != null && cleanScope.isNotEmpty) {
      await StorageService().addRecentScope(cleanScope);
    }
  }

  Future<void> selectSession(ChatSessionModel session) async {
    final sId = session.id;
    final isDifferentSession = _currentSession?.id != sId;
    _currentSession = session;

    // If this session is already loaded in memory (or generating), maintain live state without reloading
    if (_sessionMessages.containsKey(sId)) {
      if (isDifferentSession) {
        notifyListeners();
      }
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.getChatHistory(
        sId,
        limit: 20,
        beforeId: 0,
      );
      _sessionMessages[sId] = result.messages;
      _sessionHasMore[sId] = result.hasMore;
      _sessionOldestId[sId] = result.oldestId;
    } catch (_) {
      _sessionMessages[sId] = [];
      _sessionHasMore[sId] = false;
      _sessionOldestId[sId] = 0;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreMessages() async {
    final sId = _currentSession?.id;
    if (sId == null || _isLoadingMore || !(_sessionHasMore[sId] ?? false)) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final oldestId = _sessionOldestId[sId] ?? 0;
      final result = await _api.getChatHistory(
        sId,
        limitQuestions: 3,
        beforeId: oldestId,
      );

      if (result.messages.isNotEmpty) {
        _sessionMessages.putIfAbsent(sId, () => []);
        _sessionMessages[sId]!.insertAll(0, result.messages);
        _sessionHasMore[sId] = result.hasMore;
        if (result.oldestId > 0) {
          _sessionOldestId[sId] = result.oldestId;
        }
      } else {
        _sessionHasMore[sId] = false;
      }
    } catch (_) {
      _sessionHasMore[sId] = false;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  int get pinnedSessionsCount => _sessions.where((s) => s.isPinned).length;

  Future<bool> pinSession(ChatSessionModel session) async {
    final newPinState = !session.isPinned;
    if (newPinState) {
      final currentPinnedCount = _sessions.where((s) => s.isPinned).length;
      if (currentPinnedCount >= 3) {
        return false;
      }
    }

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
    return true;
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
    _sessionStreams[sessionId]?.cancel();
    _sessionStreams.remove(sessionId);
    _sessionMessages.remove(sessionId);
    _sessionGenerating.remove(sessionId);
    _sessionStatuses.remove(sessionId);
    _sessionHasMore.remove(sessionId);
    _sessionOldestId.remove(sessionId);

    await _api.deleteChatSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isNotEmpty) {
        await selectSession(_sessions.first);
      } else {
        _currentSession = null;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
    await loadSessions(silent: true);
  }

  Future<void> deleteAllSessions() async {
    for (final sub in _sessionStreams.values) {
      sub.cancel();
    }
    _sessionStreams.clear();
    _sessionMessages.clear();
    _sessionGenerating.clear();
    _sessionStatuses.clear();
    _sessionHasMore.clear();
    _sessionOldestId.clear();

    await _api.deleteAllChatSessions();
    _sessions.clear();
    _currentSession = null;
    notifyListeners();
    await loadSessions(silent: true);
  }

  Future<void> clearHistory() async {
    if (_currentSession == null) return;
    final sId = _currentSession!.id;
    await _api.clearChatHistory(sId);
    _sessionMessages[sId]?.clear();
    _sessionHasMore[sId] = false;
    _sessionOldestId[sId] = 0;
    notifyListeners();
  }

  void stopGenerating({String? sessionId}) {
    final targetId = sessionId ?? _currentSession?.id;
    if (targetId == null) return;
    _sessionStreams[targetId]?.cancel();
    _sessionStreams.remove(targetId);
    _sessionGenerating[targetId] = false;
    _sessionStatuses.remove(targetId);
    final msgs = _sessionMessages[targetId];
    if (msgs != null && msgs.isNotEmpty) {
      for (final m in msgs) {
        if (m.isStreaming) {
          m.isStreaming = false;
          m.statusMessage = null;
          if (m.content.isEmpty) {
            m.content = 'Đã dừng phản hồi.';
          }
        }
      }
    }
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
    if (query.isEmpty && (attachments == null || attachments.isEmpty)) return;

    if (_currentSession == null) {
      await createNewSession(targetServer: targetServer);
    } else if (targetServer != null && targetServer.isNotEmpty && (_currentSession!.targetServer == null || _currentSession!.targetServer!.isEmpty)) {
      await setServerForCurrentSession(targetServer);
    }

    final sessionId = _currentSession!.id;
    if (isSessionGenerating(sessionId)) return;

    // Touch and update session timestamp so it moves to top
    final now = DateTime.now();
    _currentSession = _currentSession!.copyWith(updatedAt: now);
    final sIdx = _sessions.indexWhere((s) => s.id == sessionId);
    if (sIdx != -1) {
      _sessions[sIdx] = _currentSession!;
      _sortSessions();
    }

    _sessionMessages.putIfAbsent(sessionId, () => []);

    // 1. Add User Message
    final userMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'user',
      content: query.isNotEmpty ? query : 'Đã đính kèm ${attachments?.length ?? 0} tệp',
      model: model ?? 'glm-5.3',
      attachments: attachments,
    );
    _sessionMessages[sessionId]!.add(userMsg);

    // 2. Add Placeholder Assistant Message
    final assistantMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'assistant',
      content: '',
      model: model ?? 'glm-5.3',
      isStreaming: true,
      statusMessage: 'Đang kết nối AI...',
    );
    _sessionMessages[sessionId]!.add(assistantMsg);

    _sessionGenerating[sessionId] = true;
    _sessionStatuses[sessionId] = 'Đang suy nghĩ...';
    notifyListeners();

    // Prepare history snapshot (excluding current user message and placeholder)
    final historySnap = _sessionMessages[sessionId]!
        .where((m) => m.content.isNotEmpty && m != assistantMsg && m != userMsg)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    _sessionStreams[sessionId]?.cancel();
    _sessionStreams[sessionId] = _api.streamChatMessage(
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
        _sessionStatuses[sessionId] = status;
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
        _sessionGenerating[sessionId] = false;
        _sessionStatuses.remove(sessionId);
        _sessionStreams.remove(sessionId);
        notifyListeners();
        loadSessions(silent: true); // Refresh session list & titles
      },
      onError: (err) {
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (assistantMsg.content.isEmpty) {
          final errStr = err.toString();
          // Xử lý câu trả lời "người" hơn, hóm hỉnh và chân thực khi bot gặp câu hỏi quá khó hoặc không thể trả lời
          final List<String> humanFallbackReplies = [
            'Câu hỏi quá khó rồi... Đầu óc em giờ như bị quá tải, đại ca hỏi câu khác dễ thở hơn chút đi!',
            'Chịu! Câu này ngoài tầm hiểu biết của em rồi, ca này khó quá em xin đầu hàng!',
            'Khó vậy cũng nghĩ ra hỏi được... Em chịu thua rồi đấy!',
            'Đang vò đầu bứt tai mà vẫn chưa nghĩ ra cách trả lời câu này cho mượt. Hỏi lại câu khác xem nào!',
            'Chịu luôn! Câu này hack não quá, em bot quèn không gánh nổi rồi!',
          ];
          final randomIndex = DateTime.now().millisecondsSinceEpoch % humanFallbackReplies.length;
          final fallbackText = humanFallbackReplies[randomIndex];

          if (errStr.contains('SocketException') || errStr.contains('Connection refused') || errStr.contains('Không thể kết nối')) {
            assistantMsg.content = 'Chịu! Không kết nối được tới máy chủ/mô hình AI rồi. Đại ca kiểm tra lại mạng hoặc server giúp em cái nhé!';
          } else if (errStr.contains('timeout') || errStr.contains('TimeoutException')) {
            assistantMsg.content = 'Câu hỏi quá khó rồi... Suy nghĩ lâu quá nên bị quá giờ, đại ca thử chia nhỏ câu hỏi ra xem sao!';
          } else {
            assistantMsg.content = '$fallbackText\n\n*(Chi tiết kỹ thuật nếu cần xem lại: $err)*';
          }
        }
        _sessionGenerating[sessionId] = false;
        _sessionStatuses.remove(sessionId);
        _sessionStreams.remove(sessionId);
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    for (final sub in _sessionStreams.values) {
      sub.cancel();
    }
    _sessionStreams.clear();
    super.dispose();
  }
}
