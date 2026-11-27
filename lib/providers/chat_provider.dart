import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/primary_host_server_service.dart';
import '../core/services/storage_service.dart';
import '../core/services/knowledge_index_service.dart';
import '../core/services/system_notification_service.dart';
import '../models/attachment_item.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api;
  final PrimaryHostServerService _hostServer;

  List<ChatSessionModel> _sessions = [];
  ChatSessionModel? _currentSession;

  // Per-session message storage and streaming states
  final Map<String, List<ChatMessageModel>> _sessionMessages = {};
  final Map<String, bool> _sessionGenerating = {};
  final Set<String> _localGeneratingSessions = {};
  final Set<String> _remoteGeneratingSessions = {};
  final Map<String, ChatMessageModel> _remoteStreamingMessages = {};
  final Map<String, ChatMessageModel> _remoteUserMessages = {};
  final Map<String, Timer> _remoteTokenThrottleTimers = {};
  final Map<String, String> _sessionStatuses = {};
  final Map<String, StreamSubscription> _sessionStreams = {};
  final Map<String, bool> _sessionHasMore = {};
  final Map<String, int> _sessionOldestId = {};

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

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
      sessionId != null &&
      (_sessionGenerating[sessionId] == true ||
          _remoteGeneratingSessions.contains(sessionId) ||
          _hostServer.isRemoteSessionGenerating(sessionId));

  bool get isRemoteGenerating => isSessionRemoteGenerating(_currentSession?.id);
  bool isSessionRemoteGenerating(String? sessionId) =>
      sessionId != null &&
      (_remoteGeneratingSessions.contains(sessionId) ||
          _hostServer.isRemoteSessionGenerating(sessionId));

  String get currentStatus =>
      _currentSession != null ? (_sessionStatuses[_currentSession!.id] ?? '') : '';
  String getSessionStatus(String? sessionId) =>
      sessionId != null ? (_sessionStatuses[sessionId] ?? '') : '';

  bool get anySessionGenerating =>
      _sessionGenerating.values.any((v) => v == true) ||
      _remoteGeneratingSessions.isNotEmpty ||
      _hostServer.activeChatCount > 0;

  // Quick Action Chips
  final List<String> quickPrompts = [
    '📊 Kiểm tra tài nguyên CPU/RAM',
    '🔄 Khởi động lại Nginx Web Server',
    'Top 5 tiến trình ngốn CPU nhất',
    '🛡️ Kiểm tra trạng thái tường lửa UFW',
    '🧹 Dọn dẹp RAM Cache & Disk Log',
    '🔍 Xem 20 dòng log lỗi mới nhất',
  ];

  StreamSubscription<String>? _remoteMutationSub;
  StreamSubscription<RemoteChatSyncEvent>? _remoteChatSyncSub;

  ChatProvider({
    ApiService? apiService,
    PrimaryHostServerService? hostServer,
    bool autoInit = true,
  })  : _api = apiService ?? ApiService(),
        _hostServer = hostServer ?? PrimaryHostServerService.instance {
    _hostServer.isLocalSessionGenerating = (sessionId) => _localGeneratingSessions.contains(sessionId);

    // Đồng bộ ngay các phiên App Phụ đã chạy trước khi ChatProvider khởi tạo
    for (final sId in _hostServer.activeRemoteSessionIds) {
      final snap = _hostServer.getActiveRemoteChatSnapshot(sId);
      if (snap != null) {
        _hydrateRemoteRunFromSnapshot(snap, notify: false);
      }
    }

    if (autoInit) {
      initChat();
    }

    _remoteChatSyncSub = _hostServer.onRemoteChatSync.listen(_handleRemoteChatSyncEvent);
    _remoteMutationSub = _hostServer.onRemoteMutation.listen((topic) {
      if (topic == 'sessions') {
        loadSessions(silent: true);
      } else if (topic.startsWith('chat:')) {
        final sId = topic.substring(5);
        loadSessions(silent: true);
        if (_sessionMessages.containsKey(sId) && !isSessionGenerating(sId)) {
          _reloadSessionHistorySilent(sId);
        }
      }
    });
  }

  void _hydrateRemoteRunFromSnapshot(RemoteChatLiveSnapshot snap, {bool notify = true}) {
    final sId = snap.sessionId;
    _sessionGenerating[sId] = true;
    _remoteGeneratingSessions.add(sId);
    _sessionStatuses[sId] = snap.status;
    _remoteUserMessages.putIfAbsent(
      sId,
      () => ChatMessageModel(
        sessionId: sId,
        role: 'user',
        content: snap.userMessage.trim().isNotEmpty
            ? snap.userMessage.trim()
            : 'Đã đính kèm ${snap.attachments?.length ?? 0} tệp',
        model: snap.model,
        attachments: snap.attachments,
      ),
    );
    _remoteStreamingMessages.putIfAbsent(
      sId,
      () => ChatMessageModel(
        sessionId: sId,
        role: 'assistant',
        content: snap.content,
        model: snap.model,
        isStreaming: true,
        statusMessage: snap.content.isEmpty ? snap.status : null,
        toolExecutions: List<ToolExecutionItem>.from(snap.toolExecutions),
      ),
    );
    if (_sessionMessages.containsKey(sId)) {
      _attachLiveRemoteMessagesToSession(sId);
    }
    if (notify) notifyListeners();
  }

  void _attachLiveRemoteMessagesToSession(String sessionId) {
    final list = _sessionMessages[sessionId];
    if (list == null) return;
    final snap = _hostServer.getActiveRemoteChatSnapshot(sessionId);
    if (snap != null && !_remoteStreamingMessages.containsKey(sessionId)) {
      _hydrateRemoteRunFromSnapshot(snap, notify: false);
    }
    final userMsg = _remoteUserMessages[sessionId];
    final assistantMsg = _remoteStreamingMessages[sessionId];
    if (userMsg != null) {
      final alreadyHasUser = list.contains(userMsg) ||
          (list.isNotEmpty && list.last.role == 'user' && list.last.content.trim() == userMsg.content.trim()) ||
          (list.length >= 2 &&
              list[list.length - 2].role == 'user' &&
              list[list.length - 2].content.trim() == userMsg.content.trim() &&
              list.last.isStreaming);
      if (!alreadyHasUser) {
        list.add(userMsg);
      }
    }
    if (assistantMsg != null && !list.contains(assistantMsg)) {
      list.add(assistantMsg);
    }
  }

  void _ensureRemoteRunTracked(String sessionId) {
    if (_remoteStreamingMessages.containsKey(sessionId)) return;
    final snap = _hostServer.getActiveRemoteChatSnapshot(sessionId);
    if (snap != null) {
      _hydrateRemoteRunFromSnapshot(snap, notify: false);
      return;
    }
    _sessionGenerating[sessionId] = true;
    _remoteGeneratingSessions.add(sessionId);
    _sessionStatuses.putIfAbsent(sessionId, () => 'App Phụ đang hỏi Agent...');
    _remoteStreamingMessages[sessionId] = ChatMessageModel(
      sessionId: sessionId,
      role: 'assistant',
      content: '',
      model: 'glm-5.3',
      isStreaming: true,
      statusMessage: _sessionStatuses[sessionId],
    );
    if (_sessionMessages.containsKey(sessionId)) {
      _attachLiveRemoteMessagesToSession(sessionId);
    }
  }

  void _handleRemoteChatSyncEvent(RemoteChatSyncEvent event) {
    final sId = event.sessionId;
    switch (event.type) {
      case RemoteChatSyncType.start:
        _remoteTokenThrottleTimers.remove(sId)?.cancel();
        _sessionGenerating[sId] = true;
        _remoteGeneratingSessions.add(sId);
        final initStatus = event.status ?? 'App Phụ đang hỏi Agent...';
        _sessionStatuses[sId] = initStatus;

        final now = DateTime.now();
        final sIdx = _sessions.indexWhere((s) => s.id == sId);
        if (sIdx != -1) {
          final updated = _sessions[sIdx].copyWith(updatedAt: now);
          _sessions[sIdx] = updated;
          if (_currentSession?.id == sId) {
            _currentSession = updated;
          }
          _sortSessions();
        } else {
          loadSessions(silent: true);
        }

        final query = (event.userMessage ?? '').trim();
        final modelName = (event.model != null && event.model!.isNotEmpty) ? event.model! : 'glm-5.3';
        _remoteUserMessages[sId] = ChatMessageModel(
          sessionId: sId,
          role: 'user',
          content: query.isNotEmpty ? query : 'Đã đính kèm ${event.attachments?.length ?? 0} tệp',
          model: modelName,
          attachments: event.attachments,
        );
        _remoteStreamingMessages[sId] = ChatMessageModel(
          sessionId: sId,
          role: 'assistant',
          content: '',
          model: modelName,
          isStreaming: true,
          statusMessage: initStatus,
        );
        if (_sessionMessages.containsKey(sId)) {
          _attachLiveRemoteMessagesToSession(sId);
        }
        notifyListeners();
        break;

      case RemoteChatSyncType.status:
        _ensureRemoteRunTracked(sId);
        _remoteTokenThrottleTimers[sId]?.cancel();
        final st = event.status ?? '';
        _sessionStatuses[sId] = st;
        _remoteStreamingMessages[sId]?.statusMessage = st;
        notifyListeners();
        break;

      case RemoteChatSyncType.token:
        _ensureRemoteRunTracked(sId);
        final msg = _remoteStreamingMessages[sId];
        final delta = event.token ?? '';
        if (msg != null) {
          if (delta == '__CLEAR_INTERMEDIATE_THOUGHTS__') {
            msg.content = '';
          } else {
            msg.content += delta;
          }
          msg.statusMessage = null;
        }
        final existingTimer = _remoteTokenThrottleTimers[sId];
        if (existingTimer == null || !existingTimer.isActive) {
          _remoteTokenThrottleTimers[sId] = Timer(const Duration(milliseconds: 120), () {
            notifyListeners();
          });
        }
        break;

      case RemoteChatSyncType.tool:
        _ensureRemoteRunTracked(sId);
        _remoteTokenThrottleTimers[sId]?.cancel();
        final tool = event.tool;
        final msg = _remoteStreamingMessages[sId];
        if (tool != null && msg != null) {
          var existingIdx = msg.toolExecutions.lastIndexWhere(
            (t) => t.tool == tool.tool && t.command == tool.command && t.output == 'Đang thực thi...',
          );
          if (existingIdx == -1 && tool.output != 'Đang thực thi...') {
            existingIdx = msg.toolExecutions.lastIndexWhere(
              (t) => t.tool == tool.tool && t.command == tool.tool && t.output == 'Đang thực thi...',
            );
          }
          if (existingIdx != -1) {
            msg.toolExecutions[existingIdx] = tool;
          } else {
            msg.toolExecutions.add(tool);
          }
          if (msg.toolExecutions.length > 30) {
            msg.toolExecutions.removeRange(0, msg.toolExecutions.length - 30);
          }
          if (tool.output != 'Đang thực thi...') {
            final doneStatus = 'Đã thực hiện: ${tool.command}';
            _sessionStatuses[sId] = doneStatus;
            msg.statusMessage = doneStatus;
          }
        }
        notifyListeners();
        break;

      case RemoteChatSyncType.done:
      case RemoteChatSyncType.error:
      case RemoteChatSyncType.stop:
        _remoteTokenThrottleTimers.remove(sId)?.cancel();
        final msg = _remoteStreamingMessages.remove(sId);
        _remoteUserMessages.remove(sId);
        if (msg != null) {
          for (var i = 0; i < msg.toolExecutions.length; i++) {
            final item = msg.toolExecutions[i];
            if (item.output == 'Đang thực thi...') {
              msg.toolExecutions[i] = ToolExecutionItem(
                tool: item.tool,
                command: item.command,
                output: '',
              );
            }
          }
          msg.isStreaming = false;
          msg.statusMessage = null;
          if (event.type == RemoteChatSyncType.done && (event.reply?.isNotEmpty ?? false)) {
            msg.content = event.reply!;
          } else if (event.type == RemoteChatSyncType.stop && msg.content.isEmpty) {
            msg.content = event.reply ?? 'Đã dừng phản hồi.';
          } else if (event.type == RemoteChatSyncType.error && msg.content.isEmpty) {
            msg.content = event.error ?? 'Không thể hoàn tất câu trả lời từ App Phụ.';
          }
        }
        _remoteGeneratingSessions.remove(sId);
        if (!_localGeneratingSessions.contains(sId)) {
          _sessionGenerating[sId] = false;
          _sessionStatuses.remove(sId);
        }
        notifyListeners();
        loadSessions(silent: true);
        if (_sessionMessages.containsKey(sId) && !isSessionGenerating(sId)) {
          _reloadSessionHistorySilent(sId);
        }
        break;
    }
  }

  Future<void> _reloadSessionHistorySilent(String sessionId) async {
    try {
      final result = await _api.getChatHistory(sessionId, limitQuestions: 5);
      if (isSessionGenerating(sessionId)) return;
      _sessionMessages[sessionId] = result.messages;
      _sessionHasMore[sessionId] = result.hasMore;
      _sessionOldestId[sessionId] = result.oldestId;
      notifyListeners();
    } catch (_) {}
  }

  /// Tải lại toàn bộ phiên hội thoại và tin nhắn (dùng khi chuyển vai trò App Chính <-> App Phụ).
  Future<void> reloadAll() async {
    for (final sub in _sessionStreams.values) {
      sub.cancel();
    }
    for (final t in _remoteTokenThrottleTimers.values) {
      t.cancel();
    }
    _sessionStreams.clear();
    _remoteTokenThrottleTimers.clear();
    _sessionMessages.clear();
    _sessionGenerating.clear();
    _localGeneratingSessions.clear();
    _remoteGeneratingSessions.clear();
    _remoteStreamingMessages.clear();
    _remoteUserMessages.clear();
    _sessionStatuses.clear();
    _sessionHasMore.clear();
    _sessionOldestId.clear();
    _sessions = [];
    _currentSession = null;
    notifyListeners();
    await initChat();
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

  Future<void> createNewSession({String title = 'Cuộc hội thoại mới', String? targetServer, List<String>? targetServers}) async {
    try {
      final newSess = await _api.createChatSession(title: title, targetServer: targetServer, targetServers: targetServers);
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
        targetServers: (targetServers != null && targetServers.isNotEmpty)
            ? targetServers
            : [if (targetServer != null && targetServer.isNotEmpty) targetServer],
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

  Future<void> setServerForCurrentSession(String? serverName, {List<String>? targetServers}) async {
    if (_currentSession == null) {
      await createNewSession(targetServer: serverName, targetServers: targetServers);
      return;
    }
    final cleanServer = (serverName != null && serverName.trim().isNotEmpty) ? serverName.trim() : null;
    final now = DateTime.now();
    final updated = _currentSession!.copyWith(
      targetServer: cleanServer,
      clearTargetServer: cleanServer == null,
      targetServers: targetServers,
      clearTargetServers: targetServers != null && targetServers.isEmpty,
      updatedAt: now,
    );
    _currentSession = updated;
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _sessions[idx] = updated;
      _sortSessions();
    }
    notifyListeners();
    await _api.updateChatSessionServer(updated.id, cleanServer, targetServers: updated.targetServers);
  }

  /// Gán nhanh danh sách nhiều server cho phiên hiện tại (giữ nguyên server chính).
  Future<void> setServersForCurrentSession(List<String> servers) async {
    final clean = servers.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final primary = clean.isNotEmpty ? clean.first : null;
    await setServerForCurrentSession(primary, targetServers: clean);
  }

  String? get currentSessionScope => _currentSession?.workingDirScope;
  List<String> get currentSessionDocFiles => _currentSession?.docFiles ?? const [];

  Future<void> setScopeForCurrentSession(String? scope, {List<String>? docFiles}) async {
    if (_currentSession == null) {
      await createNewSession();
    }
    final cleanScope = (scope != null && scope.trim().isNotEmpty) ? scope.trim() : null;
    final cleanDocs = docFiles ?? _currentSession!.docFiles;
    final now = DateTime.now();
    final updated = _currentSession!.copyWith(
      workingDirScope: cleanScope,
      clearWorkingDirScope: cleanScope == null,
      docFiles: cleanDocs,
      clearDocFiles: cleanScope == null && docFiles == null,
      updatedAt: now,
    );
    _currentSession = updated;
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _sessions[idx] = updated;
      _sortSessions();
    }
    notifyListeners();
    await _api.updateChatSessionScope(updated.id, cleanScope, docFiles: updated.docFiles);
    if (cleanScope != null && cleanScope.isNotEmpty) {
      await StorageService().addRecentScope(cleanScope);
      // Kich hoat dong bo tai lieu phan tich o nen cho Scope moi gan.
      KnowledgeIndexService.instance.currentScope = cleanScope;
    }
  }

  Future<void> selectSession(ChatSessionModel session) async {
    final sId = session.id;
    final isDifferentSession = _currentSession?.id != sId;
    _currentSession = session;

    // Giu cho tai lieu phan tich cua Scope cua phien nay luon tuoi moi o nen.
    final scopeForSync = session.workingDirScope;
    if (scopeForSync != null && scopeForSync.trim().isNotEmpty) {
      KnowledgeIndexService.instance.currentScope = scopeForSync.trim();
    }

    // If this session is already loaded in memory (or generating), maintain live state without reloading
    if (_sessionMessages.containsKey(sId)) {
      if (isSessionRemoteGenerating(sId)) {
        _attachLiveRemoteMessagesToSession(sId);
      }
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

    // Nếu App Phụ đang hỏi Agent ngay trên phiên vừa mở -> ghép luồng live đang chạy vào cuối danh sách
    if (isSessionRemoteGenerating(sId)) {
      _attachLiveRemoteMessagesToSession(sId);
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
    final isLocalTarget = finalServer == 'Local Machine' ||
        finalServer == 'Local' ||
        finalServer == 'localhost' ||
        finalServer == '127.0.0.1';

    // 1. Optimistic local update
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      final updated = session.copyWith(
        title: finalTitle,
        targetServer: finalServer,
        clearTargetServers: isLocalTarget,
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
      await _api.updateChatSessionServer(session.id, cleanServer, targetServers: isLocalTarget ? const [] : null);
    }
    await loadSessions(silent: true);
  }

  Future<void> renameSession(ChatSessionModel session, String newTitle) async {
    await updateSession(session, newTitle: newTitle);
  }

  Future<void> deleteSession(String sessionId) async {
    _sessionStreams[sessionId]?.cancel();
    _sessionStreams.remove(sessionId);
    _remoteTokenThrottleTimers.remove(sessionId)?.cancel();
    if (isSessionRemoteGenerating(sessionId)) {
      unawaited(_hostServer.stopActiveChat(sessionId, reason: 'Cuộc hội thoại đã bị xóa trên App Chính.'));
    }
    _sessionMessages.remove(sessionId);
    _sessionGenerating.remove(sessionId);
    _localGeneratingSessions.remove(sessionId);
    _remoteGeneratingSessions.remove(sessionId);
    _remoteStreamingMessages.remove(sessionId);
    _remoteUserMessages.remove(sessionId);
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
    for (final t in _remoteTokenThrottleTimers.values) {
      t.cancel();
    }
    for (final sId in _remoteGeneratingSessions.toList()) {
      unawaited(_hostServer.stopActiveChat(sId, reason: 'Tất cả cuộc hội thoại đã bị xóa trên App Chính.'));
    }
    _sessionStreams.clear();
    _remoteTokenThrottleTimers.clear();
    _sessionMessages.clear();
    _sessionGenerating.clear();
    _localGeneratingSessions.clear();
    _remoteGeneratingSessions.clear();
    _remoteStreamingMessages.clear();
    _remoteUserMessages.clear();
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
    await resetSessionHistory(_currentSession!.id);
  }

  Future<void> resetSessionHistory(String sessionId) async {
    // 1. Cancel running stream if any
    _sessionStreams[sessionId]?.cancel();
    _sessionStreams.remove(sessionId);
    _remoteTokenThrottleTimers.remove(sessionId)?.cancel();
    if (isSessionRemoteGenerating(sessionId)) {
      unawaited(_hostServer.stopActiveChat(sessionId, reason: 'Lịch sử hội thoại đã được đặt lại trên App Chính.'));
    }
    _sessionGenerating[sessionId] = false;
    _localGeneratingSessions.remove(sessionId);
    _remoteGeneratingSessions.remove(sessionId);
    _remoteStreamingMessages.remove(sessionId);
    _remoteUserMessages.remove(sessionId);
    _sessionStatuses.remove(sessionId);

    // 2. Clear memory messages & paging
    _sessionMessages[sessionId] = [];
    _sessionHasMore[sessionId] = false;
    _sessionOldestId[sessionId] = 0;

    // 3. Clear database messages
    await _api.clearChatHistory(sessionId);

    // 4. Update session model counts (questionCount = 0, answerCount = 0)
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final sess = _sessions[idx];
      final updated = sess.copyWith(
        questionCount: 0,
        answerCount: 0,
        updatedAt: DateTime.now(),
      );
      _sessions[idx] = updated;
      if (_currentSession?.id == sessionId) {
        _currentSession = updated;
      }
    }
    notifyListeners();
  }

  void stopGenerating({String? sessionId}) {
    final targetId = sessionId ?? _currentSession?.id;
    if (targetId == null) return;
    _sessionStreams[targetId]?.cancel();
    _sessionStreams.remove(targetId);
    _remoteTokenThrottleTimers.remove(targetId)?.cancel();
    if (isSessionRemoteGenerating(targetId)) {
      unawaited(_hostServer.stopActiveChat(targetId, reason: 'Đã dừng phản hồi từ App Chính.'));
    }
    unawaited(_api.stopRemoteChat(targetId));
    _sessionGenerating[targetId] = false;
    _localGeneratingSessions.remove(targetId);
    _remoteGeneratingSessions.remove(targetId);
    _remoteStreamingMessages.remove(targetId);
    _remoteUserMessages.remove(targetId);
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
    List<String>? targetServers,
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
    _localGeneratingSessions.add(sessionId);
    _sessionStatuses[sessionId] = 'Đang suy nghĩ...';
    notifyListeners();

    // Prepare history snapshot (excluding current user message and placeholder)
    final historySnap = _sessionMessages[sessionId]!
        .where((m) => m.content.isNotEmpty && m != assistantMsg && m != userMsg)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    _sessionStreams[sessionId]?.cancel();
    Timer? tokenThrottleTimer;
    _sessionStreams[sessionId] = _api.streamChatMessage(
      sessionId: sessionId,
      message: query.isNotEmpty ? query : 'Vui lòng đọc và phân tích các tệp đính kèm.',
      model: model,
      attachments: attachments,
      history: historySnap,
      workingDir: workingDir ?? _currentSession?.workingDirScope,
      docFiles: _currentSession?.docFiles,
      targetServer: targetServer ?? _currentSession?.targetServer,
      targetServers: (targetServers != null && targetServers.isNotEmpty)
          ? targetServers
          : (_currentSession?.targetServers ?? const []),
      onToken: (token) {
        if (token == '__CLEAR_INTERMEDIATE_THOUGHTS__') {
          assistantMsg.content = '';
        } else {
          assistantMsg.content += token;
        }
        assistantMsg.statusMessage = null;
        if (tokenThrottleTimer == null || !tokenThrottleTimer!.isActive) {
          tokenThrottleTimer = Timer(const Duration(milliseconds: 120), () {
            notifyListeners();
          });
        }
      },
      onStatus: (status) {
        tokenThrottleTimer?.cancel();
        _sessionStatuses[sessionId] = status;
        assistantMsg.statusMessage = status;
        notifyListeners();
      },
      onTool: (tool) {
        tokenThrottleTimer?.cancel();
        // Tránh trùng lặp thẻ tool (ACTIVE -> FINISHED) và giới hạn độ dài output hiển thị trên UI
        final cappedOutput = tool.output.length > 4000
            ? '${tool.output.substring(0, 4000)}\n... [Đã rút gọn ${tool.output.length - 4000} ký tự để chống lag UI]'
            : tool.output;
        final cappedTool = ToolExecutionItem(
          tool: tool.tool,
          command: tool.command,
          output: cappedOutput,
        );
        var existingIdx = assistantMsg.toolExecutions.lastIndexWhere(
          (t) => t.tool == tool.tool && t.command == tool.command && t.output == 'Đang thực thi...',
        );
        if (existingIdx == -1 && tool.output != 'Đang thực thi...') {
          existingIdx = assistantMsg.toolExecutions.lastIndexWhere(
            (t) => t.tool == tool.tool && t.command == tool.tool && t.output == 'Đang thực thi...',
          );
        }
        if (existingIdx != -1) {
          assistantMsg.toolExecutions[existingIdx] = cappedTool;
        } else {
          assistantMsg.toolExecutions.add(cappedTool);
        }
        // Giữ tối đa 30 tool card gần nhất trên UI để tránh phình cây Widget
        if (assistantMsg.toolExecutions.length > 30) {
          assistantMsg.toolExecutions.removeRange(0, assistantMsg.toolExecutions.length - 30);
        }
        if (tool.output != 'Đang thực thi...') {
          final doneStatus = 'Đã thực hiện: ${tool.command}';
          _sessionStatuses[sessionId] = doneStatus;
          assistantMsg.statusMessage = doneStatus;
        }
        notifyListeners();
      },
      onDone: (fullReply) {
        tokenThrottleTimer?.cancel();
        for (var i = 0; i < assistantMsg.toolExecutions.length; i++) {
          final item = assistantMsg.toolExecutions[i];
          if (item.output == 'Đang thực thi...') {
            assistantMsg.toolExecutions[i] = ToolExecutionItem(
              tool: item.tool,
              command: item.command,
              output: '',
            );
          }
        }
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (fullReply.isNotEmpty) {
          assistantMsg.content = fullReply;
        }
        _sessionGenerating[sessionId] = false;
        _localGeneratingSessions.remove(sessionId);
        _sessionStatuses.remove(sessionId);
        _sessionStreams.remove(sessionId);
        notifyListeners();
        loadSessions(silent: true); // Refresh session list & titles

        // Gửi Notification thông báo cho người dùng khi Bot trả lời xong
        final sessionTitle = _currentSession?.title ?? 'AI Type Agent';
        final snippet = assistantMsg.content.trim();
        final preview = snippet.length > 80 ? '${snippet.substring(0, 80)}...' : snippet;
        SystemNotificationService.notifyReplyFinished(
          title: sessionTitle,
          message: preview.isNotEmpty ? preview : 'Bot đã hoàn tất câu trả lời!',
        );
      },
      onError: (err) {
        tokenThrottleTimer?.cancel();
        for (var i = 0; i < assistantMsg.toolExecutions.length; i++) {
          final item = assistantMsg.toolExecutions[i];
          if (item.output == 'Đang thực thi...') {
            assistantMsg.toolExecutions[i] = ToolExecutionItem(
              tool: item.tool,
              command: item.command,
              output: '',
            );
          }
        }
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (assistantMsg.content.isEmpty) {
          final errStr = err.toString();

          String cause;
          String solution;

          if (errStr.contains('SocketException') || errStr.contains('Connection refused') || errStr.contains('Không thể kết nối')) {
            cause = 'Không thể kết nối đến máy chủ AI hoặc dịch vụ mạng cục bộ bị gián đoạn.';
            solution = '1. Kiểm tra lại kết nối mạng Internet hoặc cấu hình địa chỉ IP máy chủ trong mục Cài đặt.\n2. Đảm bảo dịch vụ AI backend/máy chủ đang được bật và cho phép kết nối cổng.';
          } else if (errStr.contains('timeout') || errStr.contains('TimeoutException')) {
            cause = 'Yêu cầu xử lý hoặc prompt quá phức tạp/quá dài dẫn đến vượt quá thời gian phản hồi quy định.';
            solution = '1. **Chia nhỏ yêu cầu**: Thay vì yêu cầu làm toàn bộ hệ thống cùng lúc, hãy yêu cầu từng phần nhỏ (ví dụ: làm giao diện trước, sau đó mới viết logic xử lý).\n2. **Rút gọn ngữ cảnh**: Xóa bớt các đoạn log rác hoặc tệp đính kèm không cần thiết để giảm tải lượng token.';
          } else if (errStr.contains('401') || errStr.contains('Unauthorized') || errStr.contains('API key')) {
            cause = 'Khóa xác thực API (API Key) bị thiếu, không hợp lệ hoặc đã hết hạn sử dụng.';
            solution = '1. Vào phần **Cấu hình AI** kiểm tra lại API Key xem đã nhập chính xác chưa.\n2. Xác nhận tài khoản API của mô hình còn hạn mức lượt gọi.';
          } else if (errStr.contains('429') || errStr.contains('Rate limit') || errStr.contains('quota')) {
            cause = 'Mô hình AI đã đạt giới hạn số lượng request hoặc hết hạn mức sử dụng (Quota Exceeded).';
            solution = '1. Đợi khoảng 1 - 2 phút rồi thử gửi lại yêu cầu.\n2. Chuyển sang sử dụng mô hình AI khác trong danh sách (như Claude, Gemini hoặc CLI Agent).';
          } else {
            cause = 'Yêu cầu hiện tại vượt quá phạm vi xử lý tức thời hoặc prompt bị thiếu thông tin/ngữ cảnh thực thi.';
            solution = '1. **Cụ thể hóa mục tiêu**: Nêu rõ ngôn ngữ lập trình, file mục tiêu, hoặc chức năng cụ thể cần làm.\n2. **Cung cấp ngữ cảnh**: Gắn thẻ Scope thư mục làm việc hoặc đính kèm file code liên quan để Bot hiểu rõ môi trường.\n3. **Đặt câu lệnh ngắn gọn**: Sử dụng các động từ hành động rõ ràng (ví dụ: "Viết hàm...", "Sửa lỗi tại file...", "Chạy lệnh...").';
          }

          assistantMsg.content = '''### Không thể hoàn tất câu trả lời

Bot chưa thể phản hồi trọn vẹn yêu cầu này. Dưới đây là phân tích nguyên nhân và cách khắc phục để bạn tinh chỉnh prompt:

#### 1. Nguyên nhân chính
- $cause

#### 2. Hướng dẫn khắc phục & Tối ưu Prompt
$solution

---
*(Thông tin kỹ thuật hệ thống: `$err`)*''';
        }
        _sessionGenerating[sessionId] = false;
        _localGeneratingSessions.remove(sessionId);
        _sessionStatuses.remove(sessionId);
        _sessionStreams.remove(sessionId);
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _hostServer.isLocalSessionGenerating = null;
    _remoteChatSyncSub?.cancel();
    _remoteMutationSub?.cancel();
    for (final t in _remoteTokenThrottleTimers.values) {
      t.cancel();
    }
    _remoteTokenThrottleTimers.clear();
    for (final sub in _sessionStreams.values) {
      sub.cancel();
    }
    _sessionStreams.clear();
    super.dispose();
  }
}
