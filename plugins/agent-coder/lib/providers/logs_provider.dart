import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';

class LogsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  String _logs = 'Đang tải nhật ký...';
  bool _isLoading = false;
  bool _autoRefresh = true;
  int _lines = 100;
  Timer? _timer;

  String get logs => _logs;
  bool get isLoading => _isLoading;
  bool get autoRefresh => _autoRefresh;
  int get lines => _lines;

  LogsProvider() {
    fetchLogs();
    startAutoRefresh();
  }

  void setAutoRefresh(bool val) {
    _autoRefresh = val;
    notifyListeners();
    if (_autoRefresh) {
      startAutoRefresh();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void setLines(int count) {
    _lines = count;
    notifyListeners();
    fetchLogs();
  }

  void startAutoRefresh() {
    _timer?.cancel();
    if (!_autoRefresh) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      fetchLogs(silent: true);
    });
  }

  Future<void> fetchLogs({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final data = await _api.getServerLogs(lines: _lines);
      _logs = data;
    } catch (e) {
      _logs = 'Lỗi tải log: $e';
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
