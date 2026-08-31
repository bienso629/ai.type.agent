import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/services/api_service.dart';
import '../models/metrics_model.dart';

class MetricsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  SystemMetricsModel _metrics = SystemMetricsModel();
  bool _isLoading = false;
  String? _error;
  Timer? _timer;

  // Real-time History for Charts (max 15 points)
  final List<FlSpot> _cpuHistory = [];
  final List<FlSpot> _ramHistory = [];
  int _pointIndex = 0;

  SystemMetricsModel get metrics => _metrics;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<FlSpot> get cpuHistory => _cpuHistory;
  List<FlSpot> get ramHistory => _ramHistory;

  MetricsProvider() {
    // Không tự động polling chạy ngầm liên tục để tránh chiếm dụng tài nguyên hệ thống và làm lag máy.
    // Chỉ kích hoạt lấy thông số khi người dùng chủ động yêu cầu hoặc mở màn hình giám sát.
  }

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchMetrics(silent: true);
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetchMetrics({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final data = await _api.getSystemMetrics();
      _metrics = data;
      _error = null;

      // Update Chart History
      _pointIndex++;
      _cpuHistory.add(FlSpot(_pointIndex.toDouble(), data.cpuPercent));
      _ramHistory.add(FlSpot(_pointIndex.toDouble(), data.ramPercent));

      if (_cpuHistory.length > 15) _cpuHistory.removeAt(0);
      if (_ramHistory.length > 15) _ramHistory.removeAt(0);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> executeServiceAction(String service, String action) async {
    try {
      final res = await _api.executeServiceAction(service, action);
      final ok = res['status'] == 'success' || res['status'] == 'ok';
      if (ok) {
        await Future.delayed(const Duration(seconds: 1));
        await fetchMetrics(silent: true);
      }
      return res;
    } catch (e) {
      return {'status': 'error', 'error': e.toString(), 'output': e.toString()};
    }
  }

  Future<bool> startService(String service) async {
    final res = await executeServiceAction(service, 'start');
    return res['status'] == 'success' || res['status'] == 'ok';
  }

  Future<bool> restartService(String service) async {
    final res = await executeServiceAction(service, 'restart');
    return res['status'] == 'success' || res['status'] == 'ok';
  }

  Future<bool> stopService(String service) async {
    final res = await executeServiceAction(service, 'stop');
    return res['status'] == 'success' || res['status'] == 'ok';
  }

  Future<String> getServiceStatus(String service) async {
    final res = await executeServiceAction(service, 'status');
    return (res['output'] ?? res['message'] ?? 'Không lấy được thông tin trạng thái.').toString();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
