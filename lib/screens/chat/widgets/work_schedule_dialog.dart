import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

/// Một đầu việc trong lịch làm việc do Agent sinh ra.
class ScheduleTask {
  final String id;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final String priority; // high | medium | low
  final String phase;
  final String sourceDoc;
  bool done;

  ScheduleTask({
    required this.id,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    required this.priority,
    required this.phase,
    required this.sourceDoc,
    this.done = false,
  });

  static DateTime _parseDate(dynamic raw, DateTime fallback) {
    final parsed = DateTime.tryParse(raw?.toString().trim() ?? '');
    if (parsed == null) return fallback;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  factory ScheduleTask.fromJson(Map<String, dynamic> json, int index) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = _parseDate(json['start_date'] ?? json['start'], today);
    var end = _parseDate(json['end_date'] ?? json['end'], start);
    if (end.isBefore(start)) end = start;
    final pr = (json['priority']?.toString().toLowerCase() ?? 'medium').trim();
    return ScheduleTask(
      id: json['id']?.toString() ?? 'task_$index',
      title: json['title']?.toString().trim().isNotEmpty == true ? json['title'].toString().trim() : 'Công việc ${index + 1}',
      description: json['description']?.toString().trim() ?? '',
      start: start,
      end: end,
      priority: (pr == 'high' || pr == 'low') ? pr : 'medium',
      phase: json['phase']?.toString().trim() ?? '',
      sourceDoc: json['source_doc']?.toString().trim() ?? '',
      done: json['done'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'start_date': _fmt(start),
        'end_date': _fmt(end),
        'priority': priority,
        'phase': phase,
        'source_doc': sourceDoc,
        'done': done,
      };

  bool coversDay(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Dialog hiển thị / tạo lịch làm việc từ danh sách tài liệu của dự án.
class WorkScheduleDialog extends StatefulWidget {
  final String sessionId;
  final String? workingDir;
  final List<String> docFiles;
  final String model;

  const WorkScheduleDialog({
    super.key,
    required this.sessionId,
    required this.workingDir,
    required this.docFiles,
    required this.model,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    required String? workingDir,
    required List<String> docFiles,
    required String model,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => WorkScheduleDialog(
        sessionId: sessionId,
        workingDir: workingDir,
        docFiles: docFiles,
        model: model,
      ),
    );
  }

  @override
  State<WorkScheduleDialog> createState() => _WorkScheduleDialogState();
}

class _WorkScheduleDialogState extends State<WorkScheduleDialog> {
  final ApiService _api = ApiService();

  List<ScheduleTask> _tasks = [];
  String _projectName = '';
  String _summary = '';
  DateTime? _generatedAt;

  bool _isLoadingCache = true;
  bool _isGenerating = false;
  String _status = '';
  String? _error;
  StreamSubscription<String>? _aiSub;

  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  static const _weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month);
    _loadCacheOrGenerate();
  }

  @override
  void dispose() {
    _aiSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lưu trữ cache lịch làm việc theo từng phiên
  // ---------------------------------------------------------------------------
  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    final scheduleDir = Directory(p.join(dir.path, 'work_schedules'));
    if (!scheduleDir.existsSync()) scheduleDir.createSync(recursive: true);
    final safeId = widget.sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    return File(p.join(scheduleDir.path, '$safeId.json'));
  }

  Future<void> _saveCache() async {
    try {
      final f = await _cacheFile();
      await f.writeAsString(jsonEncode({
        'project_name': _projectName,
        'summary': _summary,
        'generated_at': _generatedAt?.toIso8601String(),
        'doc_files': widget.docFiles,
        'tasks': _tasks.map((t) => t.toJson()).toList(),
      }));
    } catch (_) {}
  }

  Future<void> _loadCacheOrGenerate() async {
    try {
      final f = await _cacheFile();
      if (f.existsSync()) {
        final data = jsonDecode(await f.readAsString());
        if (data is Map<String, dynamic>) {
          _applySchedule(data);
          _generatedAt = DateTime.tryParse(data['generated_at']?.toString() ?? '');
          if (mounted) setState(() => _isLoadingCache = false);
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCache = false);
    _generate();
  }

  void _applySchedule(Map<String, dynamic> data) {
    final rawTasks = data['tasks'];
    final tasks = <ScheduleTask>[];
    if (rawTasks is List) {
      for (var i = 0; i < rawTasks.length; i++) {
        final t = rawTasks[i];
        if (t is Map) tasks.add(ScheduleTask.fromJson(Map<String, dynamic>.from(t), i));
      }
    }
    tasks.sort((a, b) => a.start.compareTo(b.start));
    _tasks = tasks;
    _projectName = data['project_name']?.toString() ?? '';
    _summary = data['summary']?.toString() ?? '';
    if (tasks.isNotEmpty) {
      final first = tasks.first.start;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final anyToday = tasks.any((t) => t.coversDay(today));
      _selectedDay = anyToday ? today : first;
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    }
  }

  // ---------------------------------------------------------------------------
  // Đọc nội dung tài liệu
  // ---------------------------------------------------------------------------
  Future<String> _readDocText(String path) async {
    final file = File(path);
    if (!file.existsSync()) return '';
    final ext = p.extension(path).toLowerCase();
    try {
      if (ext == '.pdf') {
        final res = await Process.run('pdftotext', ['-layout', path, '-']);
        return res.exitCode == 0 ? res.stdout.toString() : '';
      }
      if (ext == '.docx') {
        const script = r'''
import sys, zipfile, re
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        xml = z.read('word/document.xml').decode('utf-8', 'ignore')
    xml = re.sub(r'</w:p>', '\n', xml)
    xml = re.sub(r'<w:tab/>', '\t', xml)
    text = re.sub(r'<[^>]+>', '', xml)
    import html
    print(html.unescape(text))
except Exception as e:
    print('')
''';
        final res = await Process.run('python3', ['-c', script, path]);
        return res.exitCode == 0 ? res.stdout.toString() : '';
      }
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Gọi Agent lập lịch
  // ---------------------------------------------------------------------------
  Future<void> _generate() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _error = null;
      _status = 'Đang đọc nội dung tài liệu dự án...';
    });

    try {
      const perDocLimit = 15000;
      const totalLimit = 60000;
      final buf = StringBuffer();
      for (final doc in widget.docFiles) {
        if (buf.length >= totalLimit) break;
        var text = (await _readDocText(doc)).trim();
        if (text.isEmpty) continue;
        if (text.length > perDocLimit) text = '${text.substring(0, perDocLimit)}\n...[đã cắt bớt]';
        buf.writeln('=== TÀI LIỆU: ${p.basename(doc)} ===');
        buf.writeln(text);
        buf.writeln('=== HẾT TÀI LIỆU: ${p.basename(doc)} ===\n');
      }
      if (buf.isEmpty) {
        throw 'Không đọc được nội dung từ bất kỳ tài liệu nào của dự án.';
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr = ScheduleTask._fmt(today);
      const weekdayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

      final prompt = '''
Bạn là một Project Manager / Tech Lead giàu kinh nghiệm. Nhiệm vụ: dựa vào TOÀN BỘ tài liệu dự án bên dưới, hãy lập LỊCH LÀM VIỆC chuẩn nhất, thực tế nhất để triển khai dự án.

NGÀY BẮT ĐẦU: $todayStr (${weekdayNames[today.weekday - 1]}).

QUY TẮC LẬP LỊCH:
- Chia dự án thành các giai đoạn (phase) hợp lý: phân tích, thiết kế, phát triển từng module, tích hợp, kiểm thử, triển khai...
- Mỗi task phải cụ thể, có thể hành động được, bám sát nội dung tài liệu; ước lượng thời lượng thực tế (0.5 - 5 ngày làm việc/task).
- Sắp xếp theo thứ tự phụ thuộc logic; task phụ thuộc phải bắt đầu sau khi task tiền đề kết thúc.
- Chỉ xếp lịch vào ngày làm việc Thứ Hai đến Thứ Sáu, tránh bắt đầu hoặc kết thúc vào Thứ Bảy/Chủ Nhật.
- Ưu tiên (priority): "high" cho việc cốt lõi/chặn đường găng, "medium" bình thường, "low" có thể lùi.
- Không dùng tool, không chạy lệnh terminal. Chỉ phân tích tài liệu được cung cấp.

ĐỊNH DẠNG ĐẦU RA: CHỈ xuất DUY NHẤT một object JSON hợp lệ, không markdown, không giải thích, theo đúng schema:
{
  "project_name": "Tên dự án",
  "summary": "Tóm tắt ngắn kế hoạch (1-3 câu)",
  "tasks": [
    {
      "id": "T1",
      "title": "Tiêu đề task ngắn gọn",
      "description": "Mô tả chi tiết việc cần làm và tiêu chí hoàn thành",
      "start_date": "YYYY-MM-DD",
      "end_date": "YYYY-MM-DD",
      "priority": "high|medium|low",
      "phase": "Tên giai đoạn",
      "source_doc": "Tên file tài liệu liên quan"
    }
  ]
}

TÀI LIỆU DỰ ÁN:
${buf.toString()}
''';

      if (!mounted) return;
      setState(() => _status = 'Agent đang phân tích tài liệu và lập lịch...');

      final completer = Completer<String>();
      final replyBuf = StringBuffer();
      _aiSub = _api.streamChatMessage(
        // Dùng sessionId riêng để không làm bẩn lịch sử chat của phiên chính.
        sessionId: 'schedule_${widget.sessionId}',
        message: prompt,
        model: widget.model,
        workingDir: widget.workingDir,
        onToken: (tok) {
          replyBuf.write(tok);
          if (mounted) {
            setState(() => _status = 'Agent đang lập lịch... (${replyBuf.length} ký tự)');
          }
        },
        onStatus: (s) {
          if (mounted && s.trim().isNotEmpty) setState(() => _status = s);
        },
        onTool: (_) {},
        onDone: (full) {
          if (!completer.isCompleted) completer.complete(full.isNotEmpty ? full : replyBuf.toString());
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      final reply = await completer.future;
      final data = _extractJson(reply);
      if (data == null) {
        throw 'Agent không trả về JSON lịch làm việc hợp lệ. Hãy thử "Tạo lại".';
      }
      if (!mounted) return;
      setState(() {
        _applySchedule(data);
        _generatedAt = DateTime.now();
        if (_tasks.isEmpty) _error = 'Agent không tạo được task nào từ tài liệu.';
      });
      await _saveCache();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _status = '';
        });
      }
    }
  }

  Map<String, dynamic>? _extractJson(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers UI
  // ---------------------------------------------------------------------------
  Color _priorityColor(String pr) {
    switch (pr) {
      case 'high':
        return AppColors.danger;
      case 'low':
        return AppColors.textDim;
      default:
        return AppColors.warning;
    }
  }

  String _priorityLabel(String pr) {
    switch (pr) {
      case 'high':
        return 'Cao';
      case 'low':
        return 'Thấp';
      default:
        return 'Trung bình';
    }
  }

  String _ddmm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<ScheduleTask> _tasksOn(DateTime day) => _tasks.where((t) => t.coversDay(day)).toList();

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: AppColors.bgDark,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      child: SizedBox(
        width: size.width * 0.92,
        height: size.height * 0.9,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppColors.borderDark),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final doneCount = _tasks.where((t) => t.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _projectName.isNotEmpty ? 'Lịch làm việc - $_projectName' : 'Lịch làm việc dự án',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
                const SizedBox(height: 2),
                Text(
                  _tasks.isEmpty
                      ? 'Tạo tự động từ ${widget.docFiles.length} tài liệu bằng Agent (${widget.model})'
                      : '${_tasks.length} công việc • Hoàn thành $doneCount/${_tasks.length}'
                          '${_generatedAt != null ? ' • Tạo lúc ${_ddmm(_generatedAt!)} ${_generatedAt!.hour.toString().padLeft(2, '0')}:${_generatedAt!.minute.toString().padLeft(2, '0')}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (_tasks.isNotEmpty)
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _tasks.isEmpty ? 0 : doneCount / _tasks.length,
                  minHeight: 6,
                  backgroundColor: AppColors.borderDark,
                  color: AppColors.accent,
                ),
              ),
            ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _isGenerating ? null : _generate,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: Text(_tasks.isEmpty ? 'Tạo lịch' : 'Tạo lại'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
          ),
          IconButton(
            tooltip: 'Đóng',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingCache) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_isGenerating && _tasks.isEmpty) {
      return _buildGeneratingView();
    }
    if (_error != null && _tasks.isEmpty) {
      return _buildErrorView();
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: [
              Expanded(flex: 7, child: _buildCalendar()),
              const VerticalDivider(width: 1, color: AppColors.borderDark),
              SizedBox(width: 360, child: _buildDayPanel()),
            ],
          ),
        ),
        if (_isGenerating)
          Positioned.fill(
            child: Container(
              color: AppColors.bgDark.withValues(alpha: 0.75),
              child: _buildGeneratingView(),
            ),
          ),
      ],
    );
  }

  Widget _buildGeneratingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text(
            _status.isNotEmpty ? _status : 'Đang xử lý...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textBody, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Đang dùng ${widget.docFiles.length} tài liệu: ${widget.docFiles.map(p.basename).join(', ')}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 36),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SelectableText(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textBody, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final gridStart = firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Thanh điều hướng tháng
          Row(
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                onPressed: () => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textBody),
              ),
              Text(
                'Tháng ${_focusedMonth.month}/${_focusedMonth.year}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                onPressed: () => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textBody),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _selectedDay = today;
                  _focusedMonth = DateTime(today.year, today.month);
                }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textBody,
                  side: const BorderSide(color: AppColors.borderLight),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Hôm nay', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              _legendDot(AppColors.danger, 'Cao'),
              _legendDot(AppColors.warning, 'Trung bình'),
              _legendDot(AppColors.textDim, 'Thấp'),
              _legendDot(AppColors.accent, 'Đã xong'),
            ],
          ),
          if (_summary.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Text(_summary, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          // Hàng tiêu đề thứ
          Row(
            children: _weekdayLabels
                .map((w) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          w,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: (w == 'T7' || w == 'CN') ? AppColors.textDim : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          // Lưới 6 tuần x 7 ngày
          Expanded(
            child: Column(
              children: List.generate(6, (week) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (dow) {
                      final day = DateTime(gridStart.year, gridStart.month, gridStart.day + week * 7 + dow);
                      return Expanded(child: _buildDayCell(day, today));
                    }),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildDayCell(DateTime day, DateTime today) {
    final inMonth = day.month == _focusedMonth.month;
    final isToday = _sameDay(day, today);
    final isSelected = _sameDay(day, _selectedDay);
    final isWeekend = day.weekday >= 6;
    final tasks = _tasksOn(day);

    return InkWell(
      onTap: () => setState(() {
        _selectedDay = day;
        if (!inMonth) _focusedMonth = DateTime(day.year, day.month);
      }),
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.16)
              : (isWeekend ? AppColors.inputBg : AppColors.cardBg),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : (isToday ? AppColors.accentCyan : AppColors.borderDark),
            width: isSelected || isToday ? 1.2 : 0.8,
          ),
        ),
        child: Opacity(
          opacity: inMonth ? 1 : 0.4,
          child: LayoutBuilder(builder: (context, c) {
            // Số chip hiển thị được tuỳ theo chiều cao ô
            final maxChips = ((c.maxHeight - 20) / 18).floor().clamp(0, 5);
            final shown = tasks.take(maxChips).toList();
            final more = tasks.length - shown.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                        color: isToday ? AppColors.accentCyan : AppColors.textBody,
                      ),
                    ),
                    const Spacer(),
                    if (more > 0)
                      Text('+$more', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 2),
                ...shown.map((t) {
                  final color = t.done ? AppColors.accent : _priorityColor(t.priority);
                  return Container(
                    height: 16,
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                      border: Border(left: BorderSide(color: color, width: 2.5)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textBody,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildDayPanel() {
    const weekdayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    final tasks = _tasksOn(_selectedDay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${weekdayNames[_selectedDay.weekday - 1]}, ${_ddmm(_selectedDay)}/${_selectedDay.year}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
              ),
              const SizedBox(height: 2),
              Text(
                tasks.isEmpty ? 'Không có công việc nào' : '${tasks.length} công việc cần làm',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        if (_error != null && _tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
          ),
        const Divider(height: 1, color: AppColors.borderDark),
        Expanded(
          child: tasks.isEmpty
              ? const Center(
                  child: Text('Ngày rảnh, đi uống cà phê thôi.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildTaskCard(tasks[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(ScheduleTask t) {
    final color = t.done ? AppColors.accent : _priorityColor(t.priority);
    final days = t.end.difference(t.start).inDays + 1;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: const BorderSide(color: AppColors.borderDark),
          right: const BorderSide(color: AppColors.borderDark),
          bottom: const BorderSide(color: AppColors.borderDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: t.done,
                  activeColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.borderLight),
                  onChanged: (v) {
                    setState(() => t.done = v ?? false);
                    _saveCache();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t.id}. ${t.title}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _tag('${_ddmm(t.start)} - ${_ddmm(t.end)} ($days ngày)', AppColors.accentCyan),
              _tag('Ưu tiên: ${_priorityLabel(t.priority)}', _priorityColor(t.priority)),
              if (t.phase.isNotEmpty) _tag(t.phase, AppColors.primaryLight),
            ],
          ),
          if (t.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(t.description, style: const TextStyle(fontSize: 11.5, color: AppColors.textBody, height: 1.35)),
          ],
          if (t.sourceDoc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 12, color: AppColors.textDim),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(t.sourceDoc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
