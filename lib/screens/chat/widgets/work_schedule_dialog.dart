import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/api_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat_message.dart';

/// Một đầu việc trong lịch làm việc dự án.
class ScheduleTask {
  String id;
  String title;
  String description;
  DateTime start;
  DateTime end;
  String priority; // high | medium | low
  String phase;
  String sourceDoc;
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
      id: json['id']?.toString() ?? 'T${index + 1}',
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'Công việc ${index + 1}',
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

  static String _ddmmShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String _priorityVi(String pr) {
    switch (pr) {
      case 'high':
        return 'Cao';
      case 'low':
        return 'Thấp';
      default:
        return 'Trung bình';
    }
  }

  /// Tạo nội dung prompt chi tiết, rõ ràng để đưa công việc vào khung chat của Project cho Agent giải quyết.
  static String buildProjectPrompt(
    List<ScheduleTask> tasks, {
    List<String> sessionDocFiles = const [],
  }) {
    if (tasks.isEmpty) return '';

    String? resolveFullDocPath(String src) {
      final clean = src.trim();
      if (clean.isEmpty) return null;
      final lower = clean.toLowerCase();
      for (final doc in sessionDocFiles) {
        if (p.basename(doc).toLowerCase() == lower || doc.toLowerCase().endsWith(lower)) {
          return doc;
        }
      }
      return null;
    }

    final buf = StringBuffer();
    if (tasks.length == 1) {
      final t = tasks.first;
      final matchedPath = resolveFullDocPath(t.sourceDoc);
      buf.writeln('Hãy triển khai giải quyết chi tiết công việc sau trong dự án:');
      buf.writeln('- Mã công việc: ${t.id}');
      buf.writeln('- Tiêu đề: ${t.title}');
      if (t.phase.isNotEmpty) {
        buf.writeln('- Hạng mục / Giai đoạn: ${t.phase}');
      }
      buf.writeln('- Lịch dự kiến: ${_ddmmShort(t.start)} - ${_ddmmShort(t.end)} (Ưu tiên: ${_priorityVi(t.priority)})');
      if (t.sourceDoc.isNotEmpty) {
        buf.writeln(
          matchedPath != null
              ? '- Tài liệu tham chiếu: ${t.sourceDoc} (`$matchedPath`)'
              : '- Tài liệu tham chiếu: ${t.sourceDoc}',
        );
      }
      if (t.description.isNotEmpty) {
        buf.writeln('- Yêu cầu chi tiết:\n${t.description}');
      }
      buf.write(
        '\nYêu cầu thực hiện: Kiểm tra kỹ hiện trạng mã nguồn tại Scope dự án, triển khai đầy đủ các thay đổi cần thiết, kiểm thử lỗi biên dịch và báo cáo kết quả.',
      );
      return buf.toString();
    }

    buf.writeln('Hãy lần lượt triển khai giải quyết chi tiết ${tasks.length} công việc sau trong dự án:\n');
    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final matchedPath = resolveFullDocPath(t.sourceDoc);
      buf.writeln('${i + 1}. [${t.id}] ${t.title}');
      if (t.phase.isNotEmpty) {
        buf.writeln('   - Hạng mục: ${t.phase} (Ưu tiên: ${_priorityVi(t.priority)})');
      }
      if (t.sourceDoc.isNotEmpty) {
        buf.writeln(
          matchedPath != null
              ? '   - Tài liệu tham chiếu: ${t.sourceDoc} (`$matchedPath`)'
              : '   - Tài liệu tham chiếu: ${t.sourceDoc}',
        );
      }
      if (t.description.isNotEmpty) {
        buf.writeln('   - Chi tiết: ${t.description}');
      }
    }
    buf.write(
      '\nYêu cầu thực hiện: Đối chiếu hiện trạng mã nguồn tại Scope dự án, giải quyết trọn vẹn từng đầu việc trên, kiểm tra biên dịch không lỗi và báo cáo kết quả chi tiết.',
    );
    return buf.toString();
  }
}

typedef DispatchScheduleTasksCallback = void Function(
  List<ScheduleTask> tasks, {
  required bool sendImmediately,
});

/// Hộp thoại quản lý và tạo lịch làm việc theo yêu cầu cụ thể của người dùng.
/// Không tự động quét tài liệu hay gọi Agent khi mở hộp thoại; chỉ thực thi khi
/// người dùng nhập prompt và bấm gửi yêu cầu kèm nguồn dữ liệu mong muốn.
class WorkScheduleDialog extends StatefulWidget {
  final String sessionId;
  final String? sessionTitle;
  final String? workingDir;
  final List<String> docFiles;
  final List<ChatMessageModel> recentMessages;
  final String model;
  final ApiService? apiService;
  final DatabaseService? databaseService;
  final DispatchScheduleTasksCallback? onDispatchToPrompt;

  const WorkScheduleDialog({
    super.key,
    required this.sessionId,
    this.sessionTitle,
    required this.workingDir,
    required this.docFiles,
    this.recentMessages = const [],
    required this.model,
    this.apiService,
    this.databaseService,
    this.onDispatchToPrompt,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    String? sessionTitle,
    required String? workingDir,
    required List<String> docFiles,
    List<ChatMessageModel> recentMessages = const [],
    required String model,
    DispatchScheduleTasksCallback? onDispatchToPrompt,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => WorkScheduleDialog(
        sessionId: sessionId,
        sessionTitle: sessionTitle,
        workingDir: workingDir,
        docFiles: docFiles,
        recentMessages: recentMessages,
        model: model,
        onDispatchToPrompt: onDispatchToPrompt,
      ),
    );
  }

  @override
  State<WorkScheduleDialog> createState() => _WorkScheduleDialogState();
}

class _WorkScheduleDialogState extends State<WorkScheduleDialog> {
  late final ApiService _api = widget.apiService ?? ApiService();
  late final DatabaseService _db = widget.databaseService ?? DatabaseService();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _promptScrollController = ScrollController();
  final FocusNode _promptFocusNode = FocusNode();
  double _textareaHeight = 124.0;

  List<ScheduleTask> _tasks = [];
  String _projectName = '';
  String _summary = '';
  DateTime? _generatedAt;

  bool _isLoadingCache = true;
  bool _isGenerating = false;
  String _status = '';
  String? _error;
  StreamSubscription<String>? _aiSub;
  Completer<String>? _activeCompleter;

  // Nguồn dữ liệu do người dùng chủ động lựa chọn khi gửi prompt
  final Set<String> _selectedDocPaths = <String>{};
  late bool _includeRecentChat;
  bool _replaceAll = false;

  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  static const _weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month);
    _includeRecentChat = widget.recentMessages.isNotEmpty;
    _promptController.addListener(_onPromptChanged);
    _promptFocusNode.addListener(_onPromptChanged);
    _loadCacheOnly();
  }

  void _onPromptChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _aiSub?.cancel();
    _promptController.removeListener(_onPromptChanged);
    _promptFocusNode.removeListener(_onPromptChanged);
    _promptController.dispose();
    _promptScrollController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lưu trữ lịch làm việc trực tiếp trong SQLite của ứng dụng (chat_history.db)
  // ---------------------------------------------------------------------------
  Future<void> _saveCache() async {
    try {
      await _db.saveWorkSchedule(
        sessionId: widget.sessionId,
        projectName: _projectName,
        summary: _summary,
        docFiles: widget.docFiles,
        generatedAt: _generatedAt,
        tasks: _tasks.map((t) => t.toJson()).toList(),
      );
    } catch (_) {}
  }

  Future<void> _loadCacheOnly() async {
    try {
      final data = await _db.getWorkSchedule(widget.sessionId);
      if (data != null) {
        _applyLoadedSchedule(data);
        _generatedAt = DateTime.tryParse(data['generated_at']?.toString() ?? '');
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isLoadingCache = false);
    if (_tasks.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _promptFocusNode.requestFocus();
      });
    }
  }

  void _applyLoadedSchedule(Map<String, dynamic> data) {
    final rawTasks = data['tasks'];
    final tasks = <ScheduleTask>[];
    if (rawTasks is List) {
      for (var i = 0; i < rawTasks.length; i++) {
        final t = rawTasks[i];
        if (t is Map) {
          tasks.add(ScheduleTask.fromJson(Map<String, dynamic>.from(t), i));
        }
      }
    }
    tasks.sort((a, b) => a.start.compareTo(b.start));
    _reindexTasks(tasks);
    _tasks = tasks;
    _projectName = data['project_name']?.toString() ?? '';
    _summary = data['summary']?.toString() ?? '';
    if (tasks.isNotEmpty) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final anyToday = tasks.any((t) => t.coversDay(today));
      final pendingFirst = tasks.where((t) => !t.done).toList();
      _selectedDay = anyToday
          ? today
          : (pendingFirst.isNotEmpty ? pendingFirst.first.start : tasks.first.start);
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    }
  }

  static String _normalizeTitle(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'^t\d+[\.\:\-\s]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static void _reindexTasks(List<ScheduleTask> list) {
    for (var i = 0; i < list.length; i++) {
      list[i].id = 'T${i + 1}';
    }
  }

  List<ScheduleTask> _mergeGeneratedSchedule(
    Map<String, dynamic> data, {
    required bool replaceAll,
  }) {
    final rawTasks = data['tasks'];
    final incoming = <ScheduleTask>[];
    if (rawTasks is List) {
      for (var i = 0; i < rawTasks.length; i++) {
        final t = rawTasks[i];
        if (t is Map) {
          incoming.add(ScheduleTask.fromJson(Map<String, dynamic>.from(t), i));
        }
      }
    }

    final newProjectName = data['project_name']?.toString().trim() ?? '';
    final newSummary = data['summary']?.toString().trim() ?? '';
    if (newProjectName.isNotEmpty) _projectName = newProjectName;
    if (newSummary.isNotEmpty) _summary = newSummary;

    final completedTitles = _tasks
        .where((t) => t.done)
        .map((t) => _normalizeTitle(t.title))
        .where((s) => s.isNotEmpty)
        .toSet();

    if (replaceAll || _tasks.isEmpty) {
      // Ngay cả khi thay thế lịch, loại bỏ các đầu việc trùng hệt đầu việc đã đánh dấu hoàn thành trước đó
      final filtered = <ScheduleTask>[];
      final seen = <String>{};
      for (final item in incoming) {
        final norm = _normalizeTitle(item.title);
        if (norm.isEmpty || seen.contains(norm) || completedTitles.contains(norm)) {
          continue;
        }
        seen.add(norm);
        filtered.add(item);
      }
      filtered.sort((a, b) => a.start.compareTo(b.start));
      _reindexTasks(filtered);
      _tasks = filtered;
      return filtered;
    }

    // Chế độ mặc định: giữ nguyên toàn bộ các việc hiện có (cả đã xong lẫn đang làm), chỉ gộp thêm việc mới
    final existingNorms = _tasks
        .map((t) => _normalizeTitle(t.title))
        .where((s) => s.isNotEmpty)
        .toSet();
    final added = <ScheduleTask>[];
    for (final item in incoming) {
      final norm = _normalizeTitle(item.title);
      if (norm.isEmpty || existingNorms.contains(norm)) continue;
      existingNorms.add(norm);
      added.add(item);
    }

    final merged = <ScheduleTask>[..._tasks, ...added];
    merged.sort((a, b) => a.start.compareTo(b.start));
    _reindexTasks(merged);
    _tasks = merged;
    return added;
  }

  // ---------------------------------------------------------------------------
  // Đọc tài liệu được người dùng chỉ định (không bao giờ tự động đọc toàn bộ)
  // ---------------------------------------------------------------------------
  List<String> _resolveEffectiveDocs(String userPrompt) {
    final validDocs = widget.docFiles.where((d) => d.trim().isNotEmpty).toList();
    if (_selectedDocPaths.isNotEmpty) {
      return validDocs.where(_selectedDocPaths.contains).toList();
    }
    // Nếu người dùng không tick tài liệu nào nhưng gõ đích danh tên file trong prompt thì nạp đúng file đó
    final lowerPrompt = userPrompt.toLowerCase();
    final matched = <String>[];
    for (final doc in validDocs) {
      final base = p.basename(doc).toLowerCase();
      final stem = p.basenameWithoutExtension(doc).toLowerCase();
      if (lowerPrompt.contains(base) || (stem.length >= 5 && lowerPrompt.contains(stem))) {
        matched.add(doc);
      }
    }
    return matched;
  }

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
import sys, zipfile, re, html
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        xml = z.read('word/document.xml').decode('utf-8', 'ignore')
    xml = re.sub(r'</w:p>', '\n', xml)
    xml = re.sub(r'<w:tab/>', '\t', xml)
    text = re.sub(r'<[^>]+>', '', xml)
    print(html.unescape(text))
except Exception:
    print('')
''';
        final res = await Process.run('python3', ['-c', script, path]);
        return res.exitCode == 0 ? res.stdout.toString() : '';
      }
      return file.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  String _buildRecentChatContext() {
    if (!_includeRecentChat || widget.recentMessages.isEmpty) return '';
    const maxTotalChars = 14000;
    const maxPerMsgChars = 4500;
    final recent = widget.recentMessages.length > 6
        ? widget.recentMessages.sublist(widget.recentMessages.length - 6)
        : widget.recentMessages;

    final buf = StringBuffer();
    for (final msg in recent) {
      var text = msg.cleanContent.trim();
      if (text.isEmpty) continue;
      if (text.length > maxPerMsgChars) {
        text = '${text.substring(0, maxPerMsgChars)}\n...[đã rút gọn]';
      }
      final speaker = msg.role == 'user' ? 'NGƯỜI DÙNG' : 'AGENT PHÂN TÍCH';
      final block = '[$speaker]:\n$text\n\n';
      if (buf.length + block.length > maxTotalChars) break;
      buf.write(block);
    }
    return buf.toString().trim();
  }

  String _buildExistingTasksContext() {
    if (_tasks.isEmpty) return '';
    final buf = StringBuffer();
    for (final t in _tasks) {
      final stateLabel = t.done ? 'ĐÃ HOÀN THÀNH' : 'ĐANG CHỜ / ĐÃ LÊN LỊCH';
      buf.writeln('- [${t.id}] [$stateLabel] ${t.title} (${ScheduleTask._fmt(t.start)} -> ${ScheduleTask._fmt(t.end)})');
    }
    return buf.toString().trim();
  }

  void _cancelGeneration() {
    _aiSub?.cancel();
    _aiSub = null;
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.completeError('Đã dừng tạo công việc theo yêu cầu.');
    }
    if (mounted) {
      setState(() {
        _isGenerating = false;
        _status = '';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Chỉ chạy khi người dùng chủ động nhập prompt và bấm Gửi yêu cầu
  // ---------------------------------------------------------------------------
  Future<void> _submitPrompt() async {
    if (_isGenerating) return;
    final userPrompt = _promptController.text.trim();
    if (userPrompt.isEmpty) {
      setState(() {
        _error = 'Vui lòng nhập yêu cầu cụ thể vào ô bên dưới rồi bấm "Gửi yêu cầu" để tạo công việc.';
      });
      _promptFocusNode.requestFocus();
      return;
    }

    final docsToRead = _resolveEffectiveDocs(userPrompt);
    setState(() {
      _isGenerating = true;
      _error = null;
      _status = docsToRead.isNotEmpty
          ? 'Đang đọc ${docsToRead.length} tài liệu đã chọn...'
          : 'Đang chuẩn bị dữ liệu theo yêu cầu...';
    });

    try {
      const perDocLimit = 15000;
      const totalDocLimit = 45000;
      final docsBuf = StringBuffer();
      for (final doc in docsToRead) {
        if (docsBuf.length >= totalDocLimit) break;
        var text = (await _readDocText(doc)).trim();
        if (text.isEmpty) continue;
        if (text.length > perDocLimit) {
          text = '${text.substring(0, perDocLimit)}\n...[đã cắt bớt]';
        }
        docsBuf.writeln('=== TÀI LIỆU THAM CHIẾU: ${p.basename(doc)} ===');
        docsBuf.writeln(text);
        docsBuf.writeln('=== HẾT TÀI LIỆU: ${p.basename(doc)} ===\n');
      }

      final recentChatText = _buildRecentChatContext();
      final existingTasksText = _buildExistingTasksContext();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr = ScheduleTask._fmt(today);
      const weekdayNames = [
        'Thứ Hai',
        'Thứ Ba',
        'Thứ Tư',
        'Thứ Năm',
        'Thứ Sáu',
        'Thứ Bảy',
        'Chủ Nhật',
      ];

      final promptBuf = StringBuffer();
      promptBuf.writeln(
        'Bạn là Project Manager / Tech Lead. Nhiệm vụ: tạo danh sách công việc (Lịch làm việc) CHÍNH XÁC theo đúng yêu cầu của người dùng dưới đây.',
      );
      promptBuf.writeln('\nNGÀY HIỆN TẠI: $todayStr (${weekdayNames[today.weekday - 1]}).');
      if (widget.sessionTitle != null && widget.sessionTitle!.trim().isNotEmpty) {
        promptBuf.writeln('DỰ ÁN / HỘI THOẠI: ${widget.sessionTitle!.trim()}');
      }

      promptBuf.writeln('\n=== YÊU CẦU TRỰC TIẾP TỪ NGƯỜI DÙNG (ƯU TIÊN TUYỆT ĐỐI) ===');
      promptBuf.writeln(userPrompt);
      promptBuf.writeln('=== HẾT YÊU CẦU NGƯỜI DÙNG ===');

      promptBuf.writeln('\nQUY TẮC BẮT BUỘC:');
      promptBuf.writeln(
        '1. CHỈ tạo đúng phạm vi công việc mà người dùng yêu cầu ở trên. Tuyệt đối KHÔNG tự ý quét lan man hay tạo lại toàn bộ dự án ngoài yêu cầu.',
      );
      promptBuf.writeln(
        '2. TUYỆT ĐỐI KHÔNG tạo lại các công việc/hạng mục đã làm xong, đã hoàn thành trong mã nguồn/hội thoại, hoặc đã có sẵn trong danh sách công việc hiện tại dưới đây.',
      );
      promptBuf.writeln(
        '3. Sắp xếp ngày bắt đầu / kết thúc hợp lý theo ngày làm việc (Thứ Hai - Thứ Sáu, trừ khi người dùng chỉ định ngày cụ thể khác). Mỗi task cụ thể, súc tích, thực tế.',
      );
      promptBuf.writeln(
        '4. KHÔNG gọi bất kỳ công cụ (tool) hay lệnh terminal nào. Chỉ dựa trên yêu cầu và dữ liệu đính kèm ngay trong tin nhắn này.',
      );
      promptBuf.writeln(
        '5. CHỈ xuất DUY NHẤT một object JSON hợp lệ (không bọc giải thích ngoài JSON) theo đúng cấu trúc:',
      );
      promptBuf.writeln('''{
  "project_name": "Tên dự án ngắn gọn",
  "summary": "Tóm tắt ngắn gọn các công việc vừa lập (1-2 câu)",
  "tasks": [
    {
      "id": "T1",
      "title": "Tiêu đề công việc ngắn gọn",
      "description": "Mô tả cụ thể việc cần làm và kết quả đầu ra",
      "start_date": "YYYY-MM-DD",
      "end_date": "YYYY-MM-DD",
      "priority": "high|medium|low",
      "phase": "Tên giai đoạn / hạng mục",
      "source_doc": "Tên tài liệu hoặc nguồn yêu cầu"
    }
  ]
}''');

      if (existingTasksText.isNotEmpty) {
        promptBuf.writeln(
          '\n=== CÁC CÔNG VIỆC ĐÃ CÓ SẴN / ĐÃ LÀM (TUYỆT ĐỐI KHÔNG TẠO TRÙNG LẶP) ===',
        );
        promptBuf.writeln(existingTasksText);
        promptBuf.writeln('=== HẾT DANH SÁCH CÔNG VIỆC ĐÃ CÓ ===');
      }

      if (recentChatText.isNotEmpty) {
        promptBuf.writeln(
          '\n=== NGỮ CẢNH TRAO ĐỔI GẦN ĐÂY TRONG HỘI THOẠI (BỎ QUA CÁC PHẦN ĐÃ HOÀN THÀNH) ===',
        );
        promptBuf.writeln(recentChatText);
        promptBuf.writeln('=== HẾT NGỮ CẢNH HỘI THOẠI ===');
      }

      if (docsBuf.isNotEmpty) {
        promptBuf.writeln('\n=== DỮ LIỆU TÀI LIỆU NGƯỜI DÙNG ĐÍNH KÈM ===');
        promptBuf.write(docsBuf.toString());
        promptBuf.writeln('=== HẾT DỮ LIỆU TÀI LIỆU ===');
      }

      if (!mounted) return;
      setState(() => _status = 'Agent đang phân tích yêu cầu và tạo công việc...');

      final completer = Completer<String>();
      _activeCompleter = completer;
      final replyBuf = StringBuffer();
      _aiSub = _api.streamChatMessage(
        sessionId: 'schedule_${widget.sessionId}_${DateTime.now().millisecondsSinceEpoch}',
        message: promptBuf.toString(),
        model: widget.model,
        workingDir: null,
        onToken: (tok) {
          replyBuf.write(tok);
          if (mounted) {
            setState(() => _status = 'Agent đang lập công việc... (${replyBuf.length} ký tự)');
          }
        },
        onStatus: (s) {
          if (mounted && s.trim().isNotEmpty) setState(() => _status = s);
        },
        onTool: (_) {},
        onDone: (full) {
          if (!completer.isCompleted) {
            completer.complete(full.isNotEmpty ? full : replyBuf.toString());
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      final reply = await completer.future;
      final data = _extractJson(reply);
      if (data == null) {
        throw 'Agent không trả về đúng định dạng JSON công việc. Hãy mô tả cụ thể hơn và bấm Gửi lại.';
      }
      if (!mounted) return;

      final shouldReplace = _replaceAll || _tasks.isEmpty;
      final newlyAdded = _mergeGeneratedSchedule(data, replaceAll: shouldReplace);
      setState(() {
        _generatedAt = DateTime.now();
        if (newlyAdded.isNotEmpty) {
          _selectedDay = newlyAdded.first.start;
          _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
          _promptController.clear();
          _replaceAll = false;
        } else if (_tasks.isEmpty) {
          _error = 'Không có công việc mới nào được tạo từ yêu cầu trên.';
        } else {
          _promptController.clear();
        }
      });
      await _saveCache();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _activeCompleter = null;
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

  Future<void> _openDocPickerDialog() async {
    final tempSelected = Set<String>.from(_selectedDocPaths);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.borderDark),
              ),
              title: Row(
                children: [
                  const Icon(Icons.description_rounded, size: 18, color: AppColors.accentCyan),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Chọn tài liệu gửi kèm cho Agent',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        if (tempSelected.length == widget.docFiles.length) {
                          tempSelected.clear();
                        } else {
                          tempSelected.addAll(widget.docFiles);
                        }
                      });
                    },
                    child: Text(
                      tempSelected.length == widget.docFiles.length ? 'Bỏ chọn hết' : 'Chọn tất cả',
                      style: const TextStyle(fontSize: 12, color: AppColors.primaryLight),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.docFiles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderDark),
                    itemBuilder: (_, i) {
                      final docPath = widget.docFiles[i];
                      final checked = tempSelected.contains(docPath);
                      return CheckboxListTile(
                        value: checked,
                        dense: true,
                        activeColor: AppColors.accentCyan,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          p.basename(docPath),
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                        ),
                        subtitle: Text(
                          docPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            if (val == true) {
                              tempSelected.add(docPath);
                            } else {
                              tempSelected.remove(docPath);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    fixedSize: const Size.fromHeight(32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    side: const BorderSide(color: AppColors.borderDark),
                    shape: AppRadius.shape,
                  ),
                  child: const Text('Huỷ', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(tempSelected),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    fixedSize: const Size.fromHeight(32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    shape: AppRadius.shape,
                  ),
                  child: Text('Xác nhận (${tempSelected.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedDocPaths
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _confirmClearAllTasks() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderDark),
        ),
        title: const Text(
          'Xoá toàn bộ lịch làm việc?',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
        ),
        content: const Text(
          'Toàn bộ các đầu việc hiện có trong lịch của phiên này sẽ bị xoá. Bạn có chắc chắn muốn tiếp tục?',
          style: TextStyle(fontSize: 12.5, color: AppColors.textBody),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              fixedSize: const Size.fromHeight(32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              side: const BorderSide(color: AppColors.borderDark),
              shape: AppRadius.shape,
            ),
            child: const Text('Huỷ', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 32),
              fixedSize: const Size.fromHeight(32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              shape: AppRadius.shape,
            ),
            child: const Text('Xoá tất cả', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _tasks.clear();
        _summary = '';
        _generatedAt = null;
      });
      await _db.deleteWorkSchedule(widget.sessionId);
    }
  }

  void _deleteSingleTask(ScheduleTask task) {
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id && t.title == task.title);
      _reindexTasks(_tasks);
    });
    _saveCache();
  }

  Future<void> _editSingleTask(ScheduleTask task) async {
    final updated = await ScheduleTaskEditDialog.show(
      context,
      initialTask: task,
      docFiles: widget.docFiles,
    );
    if (updated == null || !mounted) return;
    setState(() {
      task.title = updated.title;
      task.description = updated.description;
      task.start = updated.start;
      task.end = updated.end;
      task.priority = updated.priority;
      task.phase = updated.phase;
      task.sourceDoc = updated.sourceDoc;
      task.done = updated.done;
      _tasks.sort((a, b) => a.start.compareTo(b.start));
      _reindexTasks(_tasks);
      if (!task.coversDay(_selectedDay)) {
        _selectedDay = task.start;
        _focusedMonth = DateTime(task.start.year, task.start.month);
      }
    });
    await _saveCache();
  }

  Future<void> _addNewManualTask() async {
    final created = await ScheduleTaskEditDialog.show(
      context,
      initialDate: _selectedDay,
      nextTaskId: 'T${_tasks.length + 1}',
      docFiles: widget.docFiles,
    );
    if (created == null || !mounted) return;
    setState(() {
      _tasks.add(created);
      _tasks.sort((a, b) => a.start.compareTo(b.start));
      _reindexTasks(_tasks);
      _generatedAt ??= DateTime.now();
      if (!created.coversDay(_selectedDay)) {
        _selectedDay = created.start;
        _focusedMonth = DateTime(created.start.year, created.start.month);
      }
    });
    await _saveCache();
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
            const Divider(height: 1, color: AppColors.borderDark),
            _buildPromptComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final doneCount = _tasks.where((t) => t.done).length;
    final headerTitle = _projectName.isNotEmpty
        ? 'Lịch làm việc - $_projectName'
        : (widget.sessionTitle != null && widget.sessionTitle!.trim().isNotEmpty
            ? 'Lịch làm việc - ${widget.sessionTitle!.trim()}'
            : 'Lịch làm việc dự án');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
                  headerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
                const SizedBox(height: 2),
                Text(
                  _tasks.isEmpty
                      ? 'Chưa có công việc • Nhập yêu cầu ở khung dưới và bấm "Gửi yêu cầu" để tạo việc chính xác (${widget.model})'
                      : '${_tasks.length} công việc • Hoàn thành $doneCount/${_tasks.length}'
                          '${_generatedAt != null ? ' • Cập nhật ${_ddmm(_generatedAt!)} ${_generatedAt!.hour.toString().padLeft(2, '0')}:${_generatedAt!.minute.toString().padLeft(2, '0')}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (_tasks.isNotEmpty) ...[
            SizedBox(
              width: 130,
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
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _isGenerating ? null : _confirmClearAllTasks,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Xoá hết', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
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
              color: AppColors.bgDark.withValues(alpha: 0.78),
              child: _buildGeneratingView(),
            ),
          ),
      ],
    );
  }

  Widget _buildPromptComposer() {
    final canSubmit = !_isGenerating && _promptController.text.trim().isNotEmpty;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxAllowedHeight = (screenHeight * 0.38).clamp(110.0, 320.0);
    final effectiveHeight = _textareaHeight.clamp(96.0, maxAllowedHeight);
    final isFocused = _promptFocusNode.hasFocus;

    return Container(
      color: AppColors.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thanh kéo thay đổi chiều cao vùng nhập Textarea
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _textareaHeight = (_textareaHeight - details.delta.dy).clamp(96.0, maxAllowedHeight);
                });
              },
              child: Container(
                width: double.infinity,
                height: 10,
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null && _error!.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _error = null),
                          child: const Icon(Icons.close_rounded, size: 15, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),

                // Hàng chọn nguồn dữ liệu đi kèm lệnh tạo việc
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Dữ liệu gửi kèm:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                    if (widget.docFiles.isNotEmpty)
                      InkWell(
                        onTap: _isGenerating ? null : _openDocPickerDialog,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedDocPaths.isNotEmpty
                                ? AppColors.accentCyan.withValues(alpha: 0.16)
                                : AppColors.cardBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _selectedDocPaths.isNotEmpty ? AppColors.accentCyan : AppColors.borderDark,
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 13,
                                color: _selectedDocPaths.isNotEmpty ? AppColors.accentCyan : AppColors.textMuted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _selectedDocPaths.isEmpty
                                    ? 'Chọn tài liệu (0/${widget.docFiles.length})'
                                    : 'Tài liệu đã chọn (${_selectedDocPaths.length}/${widget.docFiles.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedDocPaths.isNotEmpty ? AppColors.accentCyan : AppColors.textBody,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.recentMessages.isNotEmpty)
                      InkWell(
                        onTap: _isGenerating
                            ? null
                            : () => setState(() => _includeRecentChat = !_includeRecentChat),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _includeRecentChat
                                ? AppColors.primaryLight.withValues(alpha: 0.16)
                                : AppColors.cardBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _includeRecentChat ? AppColors.primaryLight : AppColors.borderDark,
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _includeRecentChat ? Icons.check_circle_rounded : Icons.chat_bubble_outline_rounded,
                                size: 13,
                                color: _includeRecentChat ? AppColors.primaryLight : AppColors.textMuted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Kèm ngữ cảnh hội thoại gần đây',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _includeRecentChat ? AppColors.primaryLight : AppColors.textBody,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_tasks.isNotEmpty)
                      InkWell(
                        onTap: _isGenerating
                            ? null
                            : () => setState(() => _replaceAll = !_replaceAll),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _replaceAll
                                ? AppColors.warning.withValues(alpha: 0.16)
                                : AppColors.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _replaceAll ? AppColors.warning : AppColors.accent,
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _replaceAll ? Icons.autorenew_rounded : Icons.playlist_add_check_rounded,
                                size: 14,
                                color: _replaceAll ? AppColors.warning : AppColors.accent,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _replaceAll
                                    ? 'Chế độ: Thay thế lịch hiện tại'
                                    : 'Chế độ: Bổ sung (giữ việc cũ & việc đã xong)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _replaceAll ? AppColors.warning : AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final docPath in _selectedDocPaths.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                p.basename(docPath),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, color: AppColors.textBody),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: _isGenerating ? null : () => setState(() => _selectedDocPaths.remove(docPath)),
                              child: const Icon(Icons.close_rounded, size: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedDocPaths.length > 3)
                      Text(
                        '+${_selectedDocPaths.length - 3} tệp khác',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Khung Textarea rộng rãi nhiều dòng + thanh tác vụ gửi bên dưới
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isFocused ? AppColors.primaryLight : AppColors.borderDark,
                      width: isFocused ? 1.2 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        key: const ValueKey('schedule_prompt_textarea_box'),
                        height: effectiveHeight,
                        child: Focus(
                          onKeyEvent: (_, event) {
                            final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed;
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                isCtrlOrCmd) {
                              if (canSubmit) {
                                _submitPrompt();
                              }
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Scrollbar(
                            controller: _promptScrollController,
                            thumbVisibility: true,
                            child: TextField(
                              controller: _promptController,
                              scrollController: _promptScrollController,
                              focusNode: _promptFocusNode,
                              enabled: !_isGenerating,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(fontSize: 13.5, color: AppColors.textWhite, height: 1.45),
                              decoration: const InputDecoration(
                                hintText:
                                    'Nhập chi tiết yêu cầu hoặc dán danh sách đầu việc cần lập lịch tại đây...\n'
                                    'Ví dụ:\n'
                                    '- Lên lịch triển khai Hạng mục 3 (Đề xuất kỹ thuật) và Hạng mục 4 (OCR ODO) từ thứ Hai tuần tới\n'
                                    '- Bỏ qua toàn bộ các phần đã hoàn thành trước đó',
                                hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textDim, height: 1.4),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(5)),
                          border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.8)),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Enter để xuống dòng • Ctrl + Enter để gửi nhanh • Kéo thanh trên để mở rộng khung nhập',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: AppColors.textDim),
                              ),
                            ),
                            const SizedBox(width: 12),
            if (_isGenerating)
                              ElevatedButton.icon(
                                onPressed: _cancelGeneration,
                                icon: const Icon(Icons.stop_circle_outlined, size: 14),
                                label: const Text('Dừng', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 32),
                                  fixedSize: const Size.fromHeight(32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                  shape: AppRadius.shape,
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                key: const ValueKey('schedule_submit_button'),
                                onPressed: canSubmit ? _submitPrompt : null,
                                icon: const Icon(Icons.send_rounded, size: 14),
                                label: const Text('Gửi yêu cầu', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 32),
                                  fixedSize: const Size.fromHeight(32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: AppColors.primary,
                                  disabledBackgroundColor: AppColors.sidebarBg,
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: AppColors.textDim,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                  shape: AppRadius.shape,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 14),
          Text(
            _status.isNotEmpty ? _status : 'Đang xử lý yêu cầu tạo việc...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textBody, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancelGeneration,
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Huỷ yêu cầu', style: TextStyle(fontSize: 11.5)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              fixedSize: const Size.fromHeight(32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.textBody,
              side: const BorderSide(color: AppColors.borderLight),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              shape: AppRadius.shape,
            ),
          ),
        ],
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
                  minimumSize: const Size(0, 32),
                  fixedSize: const Size.fromHeight(32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.textBody,
                  side: const BorderSide(color: AppColors.borderLight),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: AppRadius.shape,
                ),
                child: const Text('Hôm nay', style: TextStyle(fontSize: 11.5)),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
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
    final pendingOnDay = tasks.where((t) => !t.done).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${weekdayNames[_selectedDay.weekday - 1]}, ${_ddmm(_selectedDay)}/${_selectedDay.year}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('add_manual_task_button'),
                    onTap: _addNewManualTask,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderLight, width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 13, color: AppColors.accentCyan),
                          SizedBox(width: 3),
                          Text(
                            'Thêm việc',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.accentCyan),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onDispatchToPrompt != null && pendingOnDay.length > 1) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        final cb = widget.onDispatchToPrompt!;
                        Navigator.of(context).pop();
                        cb(pendingOnDay, sendImmediately: false);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.6), width: 0.8),
                        ),
                        child: Text(
                          'Đưa ${pendingOnDay.length} việc vào Prompt',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                tasks.isEmpty ? 'Không có công việc nào trong ngày này' : '${tasks.length} công việc cần làm',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.borderDark),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _tasks.isEmpty
                          ? 'Chưa có công việc nào được tạo.\nHãy nhập yêu cầu vào ô bên dưới (kèm tài liệu hoặc ngữ cảnh hội thoại cần thiết) rồi bấm "Gửi yêu cầu".'
                          : 'Không có công việc nào được xếp vào ngày này.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.45),
                    ),
                  ),
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
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 3)),
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
              const SizedBox(width: 6),
              InkWell(
                key: ValueKey('edit_task_${t.id}'),
                onTap: () => _editSingleTask(t),
                borderRadius: BorderRadius.circular(4),
                child: Tooltip(
                  message: 'Chỉnh sửa công việc',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.45), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 12, color: AppColors.primaryLight),
                        SizedBox(width: 3),
                        Text(
                          'Sửa',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: ValueKey('delete_task_${t.id}'),
                onTap: () => _deleteSingleTask(t),
                borderRadius: BorderRadius.circular(4),
                child: const Tooltip(
                  message: 'Xoá công việc',
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.textDim),
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
                  child: Text(
                    t.sourceDoc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
                  ),
                ),
              ],
            ),
          ],
          if (widget.onDispatchToPrompt != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.borderDark),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      key: ValueKey('dispatch_prompt_${t.id}'),
                      onPressed: () {
                        final cb = widget.onDispatchToPrompt!;
                        Navigator.of(context).pop();
                        cb([t], sendImmediately: false);
                      },
                      icon: const Icon(Icons.edit_note_rounded, size: 14, color: AppColors.primaryLight),
                      label: const Text(
                        'Đưa vào Prompt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.55), width: 0.8),
                        shape: AppRadius.shape,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      key: ValueKey('dispatch_run_${t.id}'),
                      onPressed: () {
                        final cb = widget.onDispatchToPrompt!;
                        Navigator.of(context).pop();
                        cb([t], sendImmediately: true);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 14),
                      label: const Text(
                        'Giải quyết ngay',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        shape: AppRadius.shape,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
          ),
        ),
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

/// Hộp thoại chọn nhanh 1 hoặc nhiều công việc từ SQLite của Project ngay trên thanh nhập Chat.
class ProjectTaskPickerDialog extends StatefulWidget {
  final String sessionId;
  final String? sessionTitle;
  final DatabaseService? databaseService;
  final VoidCallback? onOpenFullSchedule;
  final DispatchScheduleTasksCallback onDispatch;

  const ProjectTaskPickerDialog({
    super.key,
    required this.sessionId,
    this.sessionTitle,
    this.databaseService,
    this.onOpenFullSchedule,
    required this.onDispatch,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    String? sessionTitle,
    DatabaseService? databaseService,
    VoidCallback? onOpenFullSchedule,
    required DispatchScheduleTasksCallback onDispatch,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ProjectTaskPickerDialog(
        sessionId: sessionId,
        sessionTitle: sessionTitle,
        databaseService: databaseService,
        onOpenFullSchedule: onOpenFullSchedule,
        onDispatch: onDispatch,
      ),
    );
  }

  @override
  State<ProjectTaskPickerDialog> createState() => _ProjectTaskPickerDialogState();
}

class _ProjectTaskPickerDialogState extends State<ProjectTaskPickerDialog> {
  late final DatabaseService _db = widget.databaseService ?? DatabaseService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _showOnlyPending = true;
  List<ScheduleTask> _allTasks = [];
  String _projectName = '';
  String _summary = '';
  List<String> _docFiles = [];
  DateTime? _generatedAt;
  final Set<String> _selectedTaskIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    try {
      final data = await _db.getWorkSchedule(widget.sessionId);
      final loaded = <ScheduleTask>[];
      if (data != null) {
        _projectName = data['project_name']?.toString() ?? '';
        _summary = data['summary']?.toString() ?? '';
        _generatedAt = DateTime.tryParse(data['generated_at']?.toString() ?? '');
        if (data['doc_files'] is List) {
          _docFiles = (data['doc_files'] as List).map((e) => e.toString()).toList();
        }
      }
      if (data != null && data['tasks'] is List) {
        final raw = data['tasks'] as List;
        for (var i = 0; i < raw.length; i++) {
          final item = raw[i];
          if (item is Map) {
            loaded.add(ScheduleTask.fromJson(Map<String, dynamic>.from(item), i));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _allTasks = loaded;
        if (loaded.isNotEmpty && loaded.every((t) => t.done)) {
          _showOnlyPending = false;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ScheduleTask> get _filteredTasks {
    final q = _searchController.text.trim().toLowerCase();
    return _allTasks.where((t) {
      if (_showOnlyPending && t.done) return false;
      if (q.isEmpty) return true;
      return t.id.toLowerCase().contains(q) ||
          t.title.toLowerCase().contains(q) ||
          t.phase.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
    }).toList();
  }

  List<ScheduleTask> get _selectedTasks =>
      _allTasks.where((t) => _selectedTaskIds.contains(t.id)).toList();

  Future<void> _editTaskInPicker(ScheduleTask task) async {
    final updated = await ScheduleTaskEditDialog.show(
      context,
      initialTask: task,
      docFiles: _docFiles,
    );
    if (updated == null || !mounted) return;
    setState(() {
      task.title = updated.title;
      task.description = updated.description;
      task.start = updated.start;
      task.end = updated.end;
      task.priority = updated.priority;
      task.phase = updated.phase;
      task.sourceDoc = updated.sourceDoc;
      task.done = updated.done;
      _allTasks.sort((a, b) => a.start.compareTo(b.start));
      for (var i = 0; i < _allTasks.length; i++) {
        _allTasks[i].id = 'T${i + 1}';
      }
    });
    await _db.saveWorkSchedule(
      sessionId: widget.sessionId,
      projectName: _projectName,
      summary: _summary,
      docFiles: _docFiles,
      generatedAt: _generatedAt ?? DateTime.now(),
      tasks: _allTasks.map((e) => e.toJson()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _allTasks.where((t) => !t.done).length;
    final visible = _filteredTasks;
    final selected = _selectedTasks;

    return Dialog(
      backgroundColor: AppColors.bgDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      child: SizedBox(
        width: 680,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.checklist_rtl_rounded, size: 17, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sessionTitle != null && widget.sessionTitle!.trim().isNotEmpty
                              ? 'Chọn công việc đưa vào Prompt - ${widget.sessionTitle!.trim()}'
                              : 'Chọn công việc đưa vào Prompt',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Chưa hoàn thành: $pendingCount/${_allTasks.length} công việc • Chọn 1 hoặc nhiều việc để giải quyết chi tiết',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onOpenFullSchedule != null)
                    TextButton.icon(
                      onPressed: () {
                        final openSchedule = widget.onOpenFullSchedule!;
                        Navigator.of(context).pop();
                        openSchedule();
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 15),
                      label: const Text('Mở Lịch làm việc', style: TextStyle(fontSize: 11.5)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.accentCyan),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderDark),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                        decoration: InputDecoration(
                          hintText: 'Tìm theo mã (T1), tiêu đề hoặc hạng mục...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textDim),
                          prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.inputBg,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(color: AppColors.borderDark),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(color: AppColors.borderDark),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(color: AppColors.primaryLight),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _showOnlyPending = !_showOnlyPending),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _showOnlyPending ? AppColors.primary.withValues(alpha: 0.16) : AppColors.cardBg,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: _showOnlyPending ? AppColors.primaryLight : AppColors.borderDark,
                        ),
                      ),
                      child: Text(
                        _showOnlyPending ? 'Chỉ việc chưa xong ($pendingCount)' : 'Tất cả (${_allTasks.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _showOnlyPending ? AppColors.primaryLight : AppColors.textBody,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _allTasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Dự án này chưa có đầu việc nào trong Lịch làm việc.',
                                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                              ),
                              if (widget.onOpenFullSchedule != null) ...[
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final openSchedule = widget.onOpenFullSchedule!;
                                    Navigator.of(context).pop();
                                    openSchedule();
                                  },
                                  icon: const Icon(Icons.calendar_month_rounded, size: 14),
                                  label: const Text(
                                    'Mở Lịch làm việc để tạo công việc',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 32),
                                    fixedSize: const Size.fromHeight(32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    shape: AppRadius.shape,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : visible.isEmpty
                          ? const Center(
                              child: Text(
                                'Không tìm thấy công việc phù hợp.',
                                style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final t = visible[i];
                                final isChecked = _selectedTaskIds.contains(t.id);
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isChecked) {
                                        _selectedTaskIds.remove(t.id);
                                      } else {
                                        _selectedTaskIds.add(t.id);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isChecked
                                          ? AppColors.primary.withValues(alpha: 0.14)
                                          : AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isChecked ? AppColors.primaryLight : AppColors.borderDark,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: Checkbox(
                                            value: isChecked,
                                            activeColor: AppColors.primary,
                                            side: const BorderSide(color: AppColors.borderLight),
                                            onChanged: (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selectedTaskIds.add(t.id);
                                                } else {
                                                  _selectedTaskIds.remove(t.id);
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
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
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${ScheduleTask._ddmmShort(t.start)} - ${ScheduleTask._ddmmShort(t.end)}',
                                                    style: const TextStyle(fontSize: 10.5, color: AppColors.accentCyan),
                                                  ),
                                                ],
                                              ),
                                              if (t.phase.isNotEmpty || t.sourceDoc.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  [
                                                    if (t.phase.isNotEmpty) t.phase,
                                                    if (t.sourceDoc.isNotEmpty) 'Tài liệu: ${t.sourceDoc}',
                                                    if (t.done) 'Đã hoàn thành',
                                                  ].join(' • '),
                                                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                                ),
                                              ],
                                              if (t.description.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  t.description,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textBody),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          height: 32,
                                          child: OutlinedButton(
                                            key: ValueKey('picker_edit_task_${t.id}'),
                                            onPressed: () => _editTaskInPicker(t),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 32),
                                              fixedSize: const Size.fromHeight(32),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                              side: const BorderSide(color: AppColors.borderDark),
                                              shape: AppRadius.shape,
                                            ),
                                            child: const Text(
                                              'Sửa',
                                              style: TextStyle(fontSize: 11, color: AppColors.primaryLight),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          height: 32,
                                          child: OutlinedButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              widget.onDispatch([t], sendImmediately: false);
                                            },
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 32),
                                              fixedSize: const Size.fromHeight(32),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                              side: const BorderSide(color: AppColors.borderLight),
                                              shape: AppRadius.shape,
                                            ),
                                            child: const Text(
                                              'Chọn ngay',
                                              style: TextStyle(fontSize: 11, color: AppColors.textWhite),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            const Divider(height: 1, color: AppColors.borderDark),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: AppColors.sidebarBg,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.isEmpty
                          ? 'Chưa chọn công việc nào'
                          : 'Đã chọn ${selected.length} công việc (${selected.map((e) => e.id).join(', ')})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onDispatch(selected, sendImmediately: false);
                            },
                      icon: const Icon(Icons.edit_note_rounded, size: 14),
                      label: Text(
                        selected.isEmpty ? 'Đưa vào Prompt' : 'Đưa vào Prompt (${selected.length})',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.primaryLight,
                        side: BorderSide(
                          color: selected.isEmpty ? AppColors.borderDark : AppColors.primaryLight,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        shape: AppRadius.shape,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onDispatch(selected, sendImmediately: true);
                            },
                      icon: const Icon(Icons.play_arrow_rounded, size: 14),
                      label: Text(
                        selected.isEmpty ? 'Giải quyết ngay' : 'Giải quyết ngay (${selected.length})',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.cardBg,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: AppColors.textDim,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        shape: AppRadius.shape,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hộp thoại chỉnh sửa chi tiết hoặc thêm mới 1 đầu việc trong Lịch làm việc dự án.
class ScheduleTaskEditDialog extends StatefulWidget {
  final ScheduleTask? initialTask;
  final DateTime? initialDate;
  final String? nextTaskId;
  final List<String> docFiles;

  const ScheduleTaskEditDialog({
    super.key,
    this.initialTask,
    this.initialDate,
    this.nextTaskId,
    this.docFiles = const [],
  });

  static Future<ScheduleTask?> show(
    BuildContext context, {
    ScheduleTask? initialTask,
    DateTime? initialDate,
    String? nextTaskId,
    List<String> docFiles = const [],
  }) {
    return showDialog<ScheduleTask>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ScheduleTaskEditDialog(
        initialTask: initialTask,
        initialDate: initialDate,
        nextTaskId: nextTaskId,
        docFiles: docFiles,
      ),
    );
  }

  @override
  State<ScheduleTaskEditDialog> createState() => _ScheduleTaskEditDialogState();
}

class _ScheduleTaskEditDialogState extends State<ScheduleTaskEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _phaseController;
  late final TextEditingController _sourceDocController;
  late DateTime _startDate;
  late DateTime _endDate;
  late String _priority;
  late bool _done;

  bool get _isEditing => widget.initialTask != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTask;
    final now = DateTime.now();
    final defaultDay = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _titleController = TextEditingController(text: t?.title ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _phaseController = TextEditingController(text: t?.phase ?? '');
    _sourceDocController = TextEditingController(text: t?.sourceDoc ?? '');
    _startDate = t?.start ?? defaultDay;
    _endDate = t?.end ?? defaultDay;
    _priority = t?.priority ?? 'high';
    _done = t?.done ?? false;
    _titleController.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFormChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _phaseController.dispose();
    _sourceDocController.dispose();
    super.dispose();
  }

  String _fmtDdMmYyyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null || !mounted) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isStart) {
        _startDate = normalized;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = normalized;
        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  void _handleSave() {
    final cleanTitle = _titleController.text.trim();
    if (cleanTitle.isEmpty) return;
    final result = ScheduleTask(
      id: widget.initialTask?.id ?? widget.nextTaskId ?? 'T1',
      title: cleanTitle,
      description: _descriptionController.text.trim(),
      start: _startDate,
      end: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      priority: _priority,
      phase: _phaseController.text.trim(),
      sourceDoc: _sourceDocController.text.trim(),
      done: _done,
    );
    Navigator.of(context).pop(result);
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textDim),
      filled: true,
      fillColor: AppColors.inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.2),
      ),
    );
  }

  Widget _buildPriorityOption(String value, String label, Color color) {
    final selected = _priority == value;
    return Expanded(
      child: SizedBox(
        height: 32,
        child: OutlinedButton(
          key: ValueKey('edit_task_priority_$value'),
          onPressed: () => setState(() => _priority = value),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            fixedSize: const Size.fromHeight(32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: selected ? color.withValues(alpha: 0.16) : AppColors.inputBg,
            side: BorderSide(
              color: selected ? color : AppColors.borderDark,
              width: selected ? 1.2 : 0.8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            shape: AppRadius.shape,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? color : AppColors.textBody,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _titleController.text.trim().isNotEmpty;
    final days = _endDate.difference(_startDate).inDays + 1;
    final docBasenames = widget.docFiles
        .map((f) => p.basename(f))
        .where((b) => b.trim().isNotEmpty)
        .toSet()
        .toList();

    return Dialog(
      backgroundColor: AppColors.bgDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _isEditing ? Icons.edit_note_rounded : Icons.add_task_rounded,
                      size: 18,
                      color: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isEditing
                          ? 'Chỉnh sửa công việc ${widget.initialTask!.id}'
                          : 'Thêm công việc mới (${widget.nextTaskId ?? 'T1'})',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderDark),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tiêu đề công việc *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('edit_task_title_input'),
                      controller: _titleController,
                      minLines: 1,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite, fontWeight: FontWeight.w600),
                      decoration: _inputDeco('Nhập tiêu đề công việc...'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Mô tả chi tiết công việc',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('edit_task_description_input'),
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 7,
                      style: const TextStyle(fontSize: 12, color: AppColors.textBody, height: 1.4),
                      decoration: _inputDeco('Mô tả các yêu cầu kỹ thuật, luồng xử lý, nghiệm thu...'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hạng mục / Giai đoạn',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 34,
                                child: TextField(
                                  key: const ValueKey('edit_task_phase_input'),
                                  controller: _phaseController,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                  decoration: _inputDeco('VD: Hạng mục 1, Backend, UI...'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mức độ ưu tiên',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _buildPriorityOption('high', 'Cao', AppColors.danger),
                                  const SizedBox(width: 6),
                                  _buildPriorityOption('medium', 'Trung bình', AppColors.warning),
                                  const SizedBox(width: 6),
                                  _buildPriorityOption('low', 'Thấp', AppColors.textMuted),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ngày bắt đầu',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 32,
                                child: OutlinedButton.icon(
                                  key: const ValueKey('edit_task_start_date_btn'),
                                  onPressed: () => _pickDate(isStart: true),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 32),
                                    fixedSize: const Size.fromHeight(32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: AppColors.inputBg,
                                    side: const BorderSide(color: AppColors.borderDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    shape: AppRadius.shape,
                                  ),
                                  icon: const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.accentCyan),
                                  label: Text(
                                    _fmtDdMmYyyy(_startDate),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ngày kết thúc ($days ngày)',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 32,
                                child: OutlinedButton.icon(
                                  key: const ValueKey('edit_task_end_date_btn'),
                                  onPressed: () => _pickDate(isStart: false),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 32),
                                    fixedSize: const Size.fromHeight(32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: AppColors.inputBg,
                                    side: const BorderSide(color: AppColors.borderDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    shape: AppRadius.shape,
                                  ),
                                  icon: const Icon(Icons.event_available_rounded, size: 13, color: AppColors.accentCyan),
                                  label: Text(
                                    _fmtDdMmYyyy(_endDate),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tài liệu tham chiếu',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        key: const ValueKey('edit_task_source_doc_input'),
                        controller: _sourceDocController,
                        style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                        decoration: _inputDeco('Tên file tài liệu liên quan (nếu có)...'),
                      ),
                    ),
                    if (docBasenames.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: docBasenames.map((docName) {
                          final isCurrent = _sourceDocController.text.trim() == docName;
                          return InkWell(
                            onTap: () => setState(() => _sourceDocController.text = docName),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCurrent ? AppColors.primary.withValues(alpha: 0.16) : AppColors.cardBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isCurrent ? AppColors.primaryLight : AppColors.borderDark,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                docName,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isCurrent ? AppColors.primaryLight : AppColors.textMuted,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    InkWell(
                      key: const ValueKey('edit_task_done_checkbox'),
                      onTap: () => setState(() => _done = !_done),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _done,
                                activeColor: AppColors.accent,
                                side: const BorderSide(color: AppColors.borderLight),
                                onChanged: (v) => setState(() => _done = v ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Đánh dấu đã hoàn thành công việc này',
                              style: TextStyle(fontSize: 12, color: AppColors.textBody),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderDark),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.sidebarBg,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      key: const ValueKey('cancel_edit_task_button'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        side: const BorderSide(color: AppColors.borderDark),
                        shape: AppRadius.shape,
                      ),
                      child: const Text('Huỷ', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      key: const ValueKey('save_edit_task_button'),
                      onPressed: canSave ? _handleSave : null,
                      icon: const Icon(Icons.save_outlined, size: 14),
                      label: const Text(
                        'Lưu công việc',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.cardBg,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: AppColors.textDim,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        shape: AppRadius.shape,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
