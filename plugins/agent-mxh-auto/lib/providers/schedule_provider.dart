import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/database_service.dart';
import '../core/services/persona_service.dart';
import '../core/services/socks5_proxy_service.dart';
import '../models/persona_profile_model.dart';
import '../models/schedule_task_model.dart';
import '../models/server_model.dart';

class ScheduleProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final PersonaService _personaService = PersonaService();
  final Socks5ProxyService _socks5Service = Socks5ProxyService();

  List<ScheduleTaskModel> _tasks = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  String _filterType = 'all'; // 'all' | 'like' | 'comment' | 'livestream' | 'post'
  String _filterStatus = 'all'; // 'all' | 'pending' | 'completed' | 'failed'
  Timer? _schedulerTimer;

  List<ScheduleTaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;
  String get filterType => _filterType;
  String get filterStatus => _filterStatus;

  ScheduleProvider() {
    loadTasks();
    _startBackgroundTicker();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }

  void _startBackgroundTicker() {
    _schedulerTimer?.cancel();
    // Quét mỗi 30 giây để kích hoạt tác vụ đến hạn
    _schedulerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkAndRunDueTasks();
    });
  }

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  void setFilterType(String type) {
    _filterType = type;
    notifyListeners();
  }

  void setFilterStatus(String status) {
    _filterStatus = status;
    notifyListeners();
  }

  /// Lấy danh sách nhiệm vụ của ngày đang chọn
  List<ScheduleTaskModel> get tasksForSelectedDate {
    return _tasks.where((t) {
      final isSameDay = t.scheduledTime.year == _selectedDate.year &&
          t.scheduledTime.month == _selectedDate.month &&
          t.scheduledTime.day == _selectedDate.day;
      if (!isSameDay) return false;

      if (_filterType != 'all' && t.taskType != _filterType) return false;
      if (_filterStatus != 'all' && t.status != _filterStatus) return false;

      return true;
    }).toList();
  }

  /// Danh sách tất cả các ngày có tác vụ trong tháng
  Set<DateTime> getTaskDatesInMonth(DateTime monthDate) {
    final res = <DateTime>{};
    for (final t in _tasks) {
      if (t.scheduledTime.year == monthDate.year && t.scheduledTime.month == monthDate.month) {
        res.add(DateTime(t.scheduledTime.year, t.scheduledTime.month, t.scheduledTime.day));
      }
    }
    return res;
  }

  Future<void> loadTasks() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tasks = await _dbService.getScheduleTasks();
    } catch (_) {
      _tasks = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createTask({
    required String title,
    required String taskType,
    required String targetUrl,
    String? commentContent,
    required List<String> personaIps,
    required DateTime scheduledTime,
  }) async {
    final task = ScheduleTaskModel(
      title: title.trim(),
      taskType: taskType,
      targetUrl: targetUrl.trim(),
      commentContent: commentContent?.trim(),
      personaIps: personaIps,
      scheduledTime: scheduledTime,
      status: 'pending',
    );

    final id = await _dbService.insertScheduleTask(task);
    if (id > 0) {
      final savedTask = task.copyWith(id: id);
      _tasks.add(savedTask);
      _tasks.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> deleteTask(int id) async {
    final success = await _dbService.deleteScheduleTask(id);
    if (success) {
      _tasks.removeWhere((t) => t.id == id);
      notifyListeners();
    }
    return success;
  }

  Future<bool> updateTaskStatus(ScheduleTaskModel task, String newStatus, {String? note}) async {
    final updated = task.copyWith(
      status: newStatus,
      resultNote: note ?? task.resultNote,
      completedAt: (newStatus == 'completed' || newStatus == 'failed') ? DateTime.now() : task.completedAt,
    );
    final ok = await _dbService.updateScheduleTask(updated);
    if (ok) {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) {
        _tasks[idx] = updated;
        notifyListeners();
      }
    }
    return ok;
  }

  /// Kích hoạt và thực thi ngay lập tức một tác vụ
  Future<void> executeTaskNow(ScheduleTaskModel task, {ServerModel? defaultServer}) async {
    if (task.id == null) return;
    await updateTaskStatus(task, 'running', note: 'Đang thực thi tác vụ...');

    try {
      final personasMap = await _personaService.loadSavedPersonas();
      final targetPersonas = task.personaIps
          .map((ip) => personasMap[ip])
          .whereType<PersonaProfile>()
          .toList();

      if (targetPersonas.isEmpty) {
        await updateTaskStatus(task, 'failed', note: 'Không tìm thấy thông tin nhân vật nào phù hợp với danh sách IP.');
        return;
      }

      int successCount = 0;
      for (final p in targetPersonas) {
        try {
          if (p.useExternalDevice || p.externalDeviceAddress != null || p.avdName != null) {
            // Mở thiết bị máy ảo / ngoại vi
            if (defaultServer != null) {
              await _socks5Service.launchDeviceWithSocks5(
                server: defaultServer,
                ip: p.ip,
                deviceType: p.deviceType,
                avdName: p.avdName,
                remoteDeviceAddress: p.externalDeviceAddress,
                startUrl: task.targetUrl,
              );
            }
          } else {
            // Mở trình duyệt độc lập với Profile IP
            if (defaultServer != null) {
              await _socks5Service.launchBrowserWithSocks5(
                server: defaultServer,
                ip: p.ip,
                startUrl: task.targetUrl,
              );
            }
          }
          successCount++;
        } catch (_) {}
      }

      final note = 'Đã tự động kích hoạt cho $successCount/${targetPersonas.length} nhân vật thành công vào lúc ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}.';
      await updateTaskStatus(task, successCount > 0 ? 'completed' : 'failed', note: note);
    } catch (e) {
      await updateTaskStatus(task, 'failed', note: 'Lỗi thực thi: $e');
    }
  }

  /// Kiểm tra các tác vụ đã đến thời hạn (due) để thực thi
  Future<void> checkAndRunDueTasks() async {
    final now = DateTime.now();
    final dueTasks = _tasks.where((t) {
      return t.status == 'pending' && t.scheduledTime.isBefore(now);
    }).toList();

    for (final task in dueTasks) {
      await executeTaskNow(task);
    }
  }
}
