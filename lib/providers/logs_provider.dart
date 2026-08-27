import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/native_ssh_service.dart';
import '../models/server_model.dart';

class LogsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final NativeSshService _ssh = NativeSshService();

  String _logs = 'Đang tải nhật ký...';
  bool _isLoading = false;
  int _refreshInterval = 0; // 0 = Tắt/Thủ công, 3 = 3s, 5 = 5s, 10 = 10s, 30 = 30s
  int _lines = 100;
  ServerModel? _selectedServer; // null = Local Machine
  String _logType = 'agent'; // 'agent', 'syslog', 'auth', 'nginx', 'dmesg'
  Timer? _timer;

  String get logs => _logs;
  bool get isLoading => _isLoading;
  int get refreshInterval => _refreshInterval;
  bool get isAutoRefresh => _refreshInterval > 0;
  int get lines => _lines;
  ServerModel? get selectedServer => _selectedServer;
  bool get isLocal => _selectedServer == null || _selectedServer!.serverIp == '127.0.0.1' || _selectedServer!.serverIp == 'localhost';
  String get logType => _logType;

  LogsProvider() {
    fetchLogs();
  }

  void setServer(ServerModel? srv) {
    _selectedServer = (srv == null || srv.serverIp == '127.0.0.1' || srv.serverIp == 'localhost') ? null : srv;
    notifyListeners();
    fetchLogs();
  }

  void setLogType(String type) {
    _logType = type;
    notifyListeners();
    fetchLogs();
  }

  void setRefreshInterval(int seconds) {
    _refreshInterval = seconds;
    notifyListeners();
    _restartTimer();
  }

  void setLines(int count) {
    _lines = count;
    notifyListeners();
    fetchLogs();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_refreshInterval > 0) {
      _timer = Timer.periodic(Duration(seconds: _refreshInterval), (_) {
        fetchLogs(silent: true);
      });
    }
  }

  void pauseAutoRefresh() {
    _timer?.cancel();
    _timer = null;
  }

  void resumeAutoRefresh() {
    _restartTimer();
  }

  Future<void> fetchLogs({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      if (isLocal) {
        final data = await _api.getServerLogs(lines: _lines);
        _logs = data;
      } else {
        final data = await _ssh.getServerLogs(
          lines: _lines,
          server: _selectedServer,
          logType: _logType,
        );
        _logs = data;
      }
    } catch (e) {
      _logs = 'Lỗi tải nhật ký: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
