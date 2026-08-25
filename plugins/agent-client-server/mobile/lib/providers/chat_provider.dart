import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<ChatSessionModel> _sessions = [];
  ChatSessionModel? _currentSession;
  List<ChatMessageModel> _messages = [];
  bool _isLoading = false;
  bool _isGenerating = false;
  String _currentStatus = '';
  StreamSubscription? _streamSub;

  List<ChatSessionModel> get sessions => _sessions;
  ChatSessionModel? get currentSession => _currentSession;
  List<ChatMessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
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

  Future<void> initChat() async {
    await loadSessions();
    if (_sessions.isNotEmpty) {
      if (_currentSession == null || !_sessions.any((s) => s.id == _currentSession!.id)) {
        await selectSession(_sessions.first);
      }
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
      if (list.isNotEmpty) {
        _sessions = list;
        if (_currentSession == null) {
          _currentSession = _sessions.first;
        } else {
          // Update reference
          final match = _sessions.where((s) => s.id == _currentSession!.id);
          if (match.isNotEmpty) {
            _currentSession = match.first;
          }
        }
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createNewSession({String title = 'Cuộc hội thoại mới'}) async {
    try {
      final newSess = await _api.createChatSession(title: title);
      _sessions.insert(0, newSess);
      await selectSession(newSess);
    } catch (_) {
      final fallbackSess = ChatSessionModel(
        id: 'sess_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
      );
      _sessions.insert(0, fallbackSess);
      await selectSession(fallbackSess);
    }
  }

  Future<void> selectSession(ChatSessionModel session) async {
    _currentSession = session;
    _messages = [];
    _isLoading = true;
    notifyListeners();

    try {
      final history = await _api.getChatHistory(session.id);
      _messages = history;
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> pinSession(ChatSessionModel session) async {
    final newPinState = !session.isPinned;
    await _api.pinChatSession(session.id, newPinState);
    await loadSessions(silent: true);
  }

  Future<void> renameSession(ChatSessionModel session, String newTitle) async {
    if (newTitle.trim().isEmpty) return;
    await _api.renameChatSession(session.id, newTitle.trim());
    await loadSessions(silent: true);
  }

  Future<void> deleteSession(String sessionId) async {
    await _api.deleteChatSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isNotEmpty) {
        await selectSession(_sessions.first);
      } else {
        await createNewSession();
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    if (_currentSession == null) return;
    await _api.clearChatHistory(_currentSession!.id);
    _messages.clear();
    notifyListeners();
  }

  Future<void> sendMessage(String text, {String? model}) async {
    final query = text.trim();
    if (query.isEmpty || _isGenerating) return;

    if (_currentSession == null) {
      await createNewSession();
    }

    final sessionId = _currentSession!.id;

    // 1. Add User Message
    final userMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'user',
      content: query,
      model: model ?? 'glm-5.3',
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
      message: query,
      model: model,
      history: historySnap,
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
