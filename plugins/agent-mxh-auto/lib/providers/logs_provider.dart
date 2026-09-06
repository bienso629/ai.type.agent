import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';

class LogsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  String _logs = 'Đang tải nhật ký...';
  bool _isLoading = false;
  int _lines = 100;

  String get logs => _logs;
  bool get isLoading => _isLoading;
  int get lines => _lines;

  LogsProvider() {
    fetchLogs();
  }

  void setLines(int count) {
    _lines = count;
    notifyListeners();
    fetchLogs();
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

}
