import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:tadu_cloud_ai_agent_mobile/core/services/api_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/database_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/theme/app_theme.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/attachment_item.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/chat_message.dart';
import 'package:tadu_cloud_ai_agent_mobile/screens/chat/widgets/work_schedule_dialog.dart';

class _InMemoryDatabaseService implements DatabaseService {
  final Map<String, Map<String, dynamic>> _store = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Map<String, dynamic>?> getWorkSchedule(String sessionId) async {
    final existing = _store[sessionId];
    if (existing == null) return null;
    return jsonDecode(jsonEncode(existing)) as Map<String, dynamic>;
  }

  @override
  Future<bool> saveWorkSchedule({
    required String sessionId,
    required String projectName,
    required String summary,
    required List<String> docFiles,
    DateTime? generatedAt,
    required List<Map<String, dynamic>> tasks,
  }) async {
    _store[sessionId] = {
      'project_name': projectName,
      'summary': summary,
      'doc_files': List<String>.from(docFiles),
      'generated_at': generatedAt?.toIso8601String(),
      'tasks': tasks.map((t) => Map<String, dynamic>.from(t)).toList(),
    };
    return true;
  }

  @override
  Future<bool> deleteWorkSchedule(String sessionId) async {
    _store.remove(sessionId);
    return true;
  }
}

class _FakeScheduleApiService implements ApiService {
  int streamCalls = 0;
  final List<String> capturedMessages = [];
  String Function(String prompt)? responder;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    List<String>? docFiles,
    String? targetServer,
    List<String>? targetServers,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
    void Function(String reason)? onDisconnected,
    bool stopRemoteOnCancel = false,
  }) {
    streamCalls++;
    capturedMessages.add(message);
    final controller = StreamController<String>();
    Future.microtask(() {
      if (controller.isClosed) return;
      final reply = responder != null
          ? responder!(message)
          : jsonEncode({
              'project_name': 'VinTrans Taxi',
              'summary': 'Lịch triển khai Hạng mục 3 & 4',
              'tasks': [
                {
                  'id': 'T1',
                  'title': 'Xây dựng bảng technical_proposals',
                  'description': 'Tạo migration và API cho 3 nghiệp vụ kỹ thuật',
                  'start_date': '2026-11-16',
                  'end_date': '2026-11-17',
                  'priority': 'high',
                  'phase': 'Hạng mục 3',
                  'source_doc': 'spec_moi.md',
                },
              ],
            });
      onToken(reply);
      onDone(reply);
    });
    return controller.stream.listen((_) {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory tempDir;
  late File docOldCompleted;
  late File docNewSpec;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('work_schedule_test_');
    docOldCompleted = File(p.join(tempDir.path, 'tai_lieu_cu_da_xong.md'));
    docOldCompleted.writeAsStringSync('NOI_DUNG_TAI_LIEU_CU_KHONG_DUOC_DOC_TU_DONG');

    docNewSpec = File(p.join(tempDir.path, 'yeu_cau_moi_saomai.md'));
    docNewSpec.writeAsStringSync('NOI_DUNG_YEU_CAU_MOI_SAOMAI_OCR_ODO');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'DatabaseService stores and restores work schedules & tasks directly in SQLite across DB close/reopen',
    () async {
      final dbPath = p.join(tempDir.path, 'chat_history.db');
      final db1 = DatabaseService.forTest(dbPath);
      final genTime = DateTime(2026, 11, 16, 8, 30);

      final saved = await db1.saveWorkSchedule(
        sessionId: 'sess_sqlite_persist',
        projectName: 'Vận tải VinTrans',
        summary: 'Lộ trình triển khai Hạng mục 3 & 4',
        docFiles: ['/docs/yeu_cau_saomai.md'],
        generatedAt: genTime,
        tasks: [
          {
            'id': 'T1',
            'title': 'Thiết kế bảng technical_proposals',
            'description': 'Hỗ trợ thay nhớt, thay lốp, sửa chữa',
            'start_date': '2026-11-16',
            'end_date': '2026-11-17',
            'priority': 'high',
            'phase': 'Hạng mục 3',
            'source_doc': 'yeu_cau_saomai.md',
            'done': true,
          },
          {
            'id': 'T2',
            'title': 'Tích hợp OCR đồng hồ ODO',
            'description': 'Lưu lịch sử chỉ số Km taplo',
            'start_date': '2026-11-18',
            'end_date': '2026-11-20',
            'priority': 'medium',
            'phase': 'Hạng mục 4',
            'source_doc': 'yeu_cau_saomai.md',
            'done': false,
          },
        ],
      );
      expect(saved, isTrue);
      await db1.close();

      // Mở một kết nối SQLite hoàn toàn mới tới cùng file chat_history.db (mô phỏng cài lại / mở lại app)
      final db2 = DatabaseService.forTest(dbPath);
      final loaded = await db2.getWorkSchedule('sess_sqlite_persist');
      expect(loaded, isNotNull);
      expect(loaded!['project_name'], equals('Vận tải VinTrans'));
      expect(loaded['summary'], equals('Lộ trình triển khai Hạng mục 3 & 4'));
      expect(loaded['doc_files'], equals(['/docs/yeu_cau_saomai.md']));

      final tasks = loaded['tasks'] as List<dynamic>;
      expect(tasks.length, equals(2));
      expect(tasks[0]['title'], equals('Thiết kế bảng technical_proposals'));
      expect(tasks[0]['done'], isTrue);
      expect(tasks[1]['title'], equals('Tích hợp OCR đồng hồ ODO'));
      expect(tasks[1]['done'], isFalse);
      expect(await db2.getPendingWorkScheduleCount('sess_sqlite_persist'), equals(1));

      // Đánh dấu hoàn thành T2 trực tiếp từ khung Chat
      final marked = await db2.markWorkScheduleTasksDone('sess_sqlite_persist', ['T2']);
      expect(marked, isTrue);
      expect(await db2.getPendingWorkScheduleCount('sess_sqlite_persist'), equals(0));

      // Xoá lịch làm việc trong SQLite
      await db2.deleteWorkSchedule('sess_sqlite_persist');
      final afterDelete = await db2.getWorkSchedule('sess_sqlite_persist');
      expect(afterDelete, isNull);
      await db2.close();
    },
  );

  testWidgets(
    'opening WorkScheduleDialog does NOT auto-call Agent or auto-read documents until user prompts and clicks send',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeApi = _FakeScheduleApiService();
      final fakeDb = _InMemoryDatabaseService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkScheduleDialog(
              sessionId: 'sess_vintrans_1',
              sessionTitle: 'Vận tải VinTrans',
              workingDir: tempDir.path,
              docFiles: [docOldCompleted.path, docNewSpec.path],
              recentMessages: [
                ChatMessageModel(
                  sessionId: 'sess_vintrans_1',
                  role: 'assistant',
                  content: 'Hạng mục 1 và 2 đã hoàn thành. Chỉ còn Hạng mục 3 và Hạng mục 4 cần làm.',
                ),
              ],
              model: 'antigravity-cli',
              apiService: fakeApi,
              databaseService: fakeDb,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeApi.streamCalls, equals(0));
      expect(find.textContaining('Chưa có công việc nào được tạo'), findsOneWidget);

      final textareaBoxSize = tester.getSize(
        find.byKey(const ValueKey('schedule_prompt_textarea_box')),
      );
      expect(textareaBoxSize.height, greaterThanOrEqualTo(120.0));
      final promptField = tester.widget<TextField>(find.byType(TextField));
      expect(promptField.expands, isTrue);
      expect(promptField.maxLines, isNull);

      final submitBtn = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('schedule_submit_button')),
      );
      expect(submitBtn.onPressed, isNull);

      await tester.enterText(
        find.byType(TextField),
        'Tạo công việc cho Hạng mục 3 từ tài liệu yeu_cau_moi_saomai.md, bỏ qua phần đã làm',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('schedule_submit_button')));
      await tester.pumpAndSettle();

      expect(fakeApi.streamCalls, equals(1));
      final sentPrompt = fakeApi.capturedMessages.single;
      expect(sentPrompt, contains('NOI_DUNG_YEU_CAU_MOI_SAOMAI_OCR_ODO'));
      expect(sentPrompt, isNot(contains('NOI_DUNG_TAI_LIEU_CU_KHONG_DUOC_DOC_TU_DONG')));
      expect(sentPrompt, contains('Chỉ còn Hạng mục 3 và Hạng mục 4 cần làm'));

      expect(find.textContaining('Xây dựng bảng technical_proposals'), findsWidgets);

      // Xác nhận dữ liệu công việc đã được ghi xuống DatabaseService
      final persisted = await fakeDb.getWorkSchedule('sess_vintrans_1');
      expect(persisted, isNotNull);
      expect((persisted!['tasks'] as List).length, equals(1));
    },
  );

  testWidgets(
    'submitting subsequent prompt preserves completed tasks in DatabaseService and deduplicates repeated titles',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = _InMemoryDatabaseService();
      await fakeDb.saveWorkSchedule(
        sessionId: 'sess_dedup',
        projectName: 'VinTrans Taxi',
        summary: 'Giai đoạn 1',
        docFiles: [docOldCompleted.path],
        generatedAt: DateTime(2026, 11, 15, 10, 0),
        tasks: [
          {
            'id': 'T1',
            'title': 'Luồng đổ dầu QR giai đoạn 1',
            'description': 'Đã triển khai xong',
            'start_date': '2026-11-16',
            'end_date': '2026-11-16',
            'priority': 'high',
            'phase': 'Hạng mục 1',
            'source_doc': 'old.md',
            'done': true,
          },
        ],
      );

      final fakeApi = _FakeScheduleApiService()
        ..responder = (_) => jsonEncode({
              'project_name': 'VinTrans Taxi',
              'summary': 'Bổ sung Hạng mục 4',
              'tasks': [
                {
                  'id': 'T1',
                  'title': 'Luồng đổ dầu QR giai đoạn 1',
                  'description': 'Trùng việc đã xong',
                  'start_date': '2026-11-16',
                  'end_date': '2026-11-16',
                  'priority': 'high',
                  'phase': 'Hạng mục 1',
                  'source_doc': 'old.md',
                },
                {
                  'id': 'T2',
                  'title': 'Đọc OCR chỉ số Km Taplo và lưu ODO',
                  'description': 'Tích hợp đọc ảnh đồng hồ công tơ mét',
                  'start_date': '2026-11-16',
                  'end_date': '2026-11-18',
                  'priority': 'high',
                  'phase': 'Hạng mục 4',
                  'source_doc': 'saomai.md',
                },
              ],
            });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkScheduleDialog(
              sessionId: 'sess_dedup',
              workingDir: tempDir.path,
              docFiles: [docOldCompleted.path],
              model: 'antigravity-cli',
              apiService: fakeApi,
              databaseService: fakeDb,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeApi.streamCalls, equals(0));
      expect(find.textContaining('1 công việc • Hoàn thành 1/1'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Thêm việc OCR ODO cho ngày 16/11');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('schedule_submit_button')));
      await tester.pumpAndSettle();

      expect(fakeApi.capturedMessages.single, contains('[ĐÃ HOÀN THÀNH] Luồng đổ dầu QR giai đoạn 1'));
      expect(find.textContaining('2 công việc • Hoàn thành 1/2'), findsOneWidget);
      expect(find.textContaining('Đọc OCR chỉ số Km Taplo và lưu ODO'), findsWidgets);
    },
  );

  testWidgets(
    'dispatching task from WorkScheduleDialog and ProjectTaskPickerDialog builds rich Project prompt with Scope doc path',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = _InMemoryDatabaseService();
      await fakeDb.saveWorkSchedule(
        sessionId: 'sess_dispatch',
        projectName: 'VinTrans Taxi',
        summary: 'Lộ trình triển khai',
        docFiles: [docNewSpec.path],
        generatedAt: DateTime(2026, 11, 16, 9, 0),
        tasks: [
          {
            'id': 'T1',
            'title': 'Thiết kế bảng technical_proposals',
            'description': 'Hỗ trợ fuel, maintenance, tire, repair',
            'start_date': '2026-11-16',
            'end_date': '2026-11-17',
            'priority': 'high',
            'phase': 'Hạng mục 3',
            'source_doc': 'yeu_cau_moi_saomai.md',
            'done': false,
          },
        ],
      );

      List<ScheduleTask>? dispatchedTasks;
      bool? dispatchedImmediate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (_) => WorkScheduleDialog(
                        sessionId: 'sess_dispatch',
                        workingDir: tempDir.path,
                        docFiles: [docNewSpec.path],
                        model: 'antigravity-cli',
                        databaseService: fakeDb,
                        onDispatchToPrompt: (tasks, {required sendImmediately}) {
                          dispatchedTasks = tasks;
                          dispatchedImmediate = sendImmediately;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Schedule'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Schedule'));
      await tester.pumpAndSettle();

      final promptBtnSize = tester.getSize(find.byKey(const ValueKey('dispatch_prompt_T1')));
      final runBtnSize = tester.getSize(find.byKey(const ValueKey('dispatch_run_T1')));
      final submitBtnSize = tester.getSize(find.byKey(const ValueKey('schedule_submit_button')));
      expect(promptBtnSize.height, equals(32.0));
      expect(runBtnSize.height, equals(32.0));
      expect(submitBtnSize.height, equals(32.0));

      await tester.tap(find.byKey(const ValueKey('dispatch_prompt_T1')));
      await tester.pumpAndSettle();

      expect(dispatchedTasks, isNotNull);
      expect(dispatchedTasks!.length, equals(1));
      expect(dispatchedImmediate, isFalse);

      final prompt = ScheduleTask.buildProjectPrompt(
        dispatchedTasks!,
        sessionDocFiles: [docNewSpec.path],
      );
      expect(prompt, contains('T1'));
      expect(prompt, contains('Thiết kế bảng technical_proposals'));
      expect(prompt, contains('Hạng mục 3'));
      expect(prompt, contains(docNewSpec.path));

      // Kiểm tra luôn ProjectTaskPickerDialog chọn nhanh từ thanh nhập Chat
      List<ScheduleTask>? pickerTasks;
      bool? pickerImmediate;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    ProjectTaskPickerDialog.show(
                      ctx,
                      sessionId: 'sess_dispatch',
                      sessionTitle: 'Vận tải VinTrans',
                      databaseService: fakeDb,
                      onDispatch: (tasks, {required sendImmediately}) {
                        pickerTasks = tasks;
                        pickerImmediate = sendImmediately;
                      },
                    );
                  },
                  child: const Text('Open Picker'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chọn ngay'));
      await tester.pumpAndSettle();

      expect(pickerTasks, isNotNull);
      expect(pickerTasks!.single.id, equals('T1'));
      expect(pickerImmediate, isFalse);
    },
  );

  testWidgets(
    'Linux Desktop (TargetPlatform.linux / VisualDensity.compact) preserves exact 32.0px button height for Gui, Dung, Scope, and WorkScheduleDialog without shrinking global AppTheme buttons to 24px',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      try {
        final fakeDb = _InMemoryDatabaseService();
        await fakeDb.saveWorkSchedule(
          sessionId: 'sess_linux_btns',
          projectName: 'VinTrans Taxi',
          summary: 'Kiểm tra chiều cao nút trên Linux Desktop',
          docFiles: [docNewSpec.path],
          generatedAt: DateTime(2026, 11, 16, 10, 0),
          tasks: [
            {
              'id': 'T1',
              'title': 'Kiểm tra đồng bộ chiều cao nút 32px',
              'description': 'Không được bị VisualDensity.compact trừ xuống 24px',
              'start_date': '2026-11-16',
              'end_date': '2026-11-16',
              'priority': 'high',
              'phase': 'UI',
              'source_doc': 'yeu_cau_moi_saomai.md',
              'done': false,
            },
          ],
        );

        final linuxTheme = AppTheme.darkTheme;
        expect(linuxTheme.visualDensity, equals(VisualDensity.compact));

        await tester.pumpWidget(
          MaterialApp(
            theme: linuxTheme,
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton(
                        key: const ValueKey('global_theme_elevated_btn'),
                        onPressed: () {},
                        child: const Text('Mặc định'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('input_scope_btn'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          fixedSize: const Size.fromHeight(32),
                          side: const BorderSide(color: AppColors.borderDark),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: const Icon(Icons.account_tree_rounded, size: 14),
                        label: const Text('Scope /', style: TextStyle(fontSize: 11)),
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        key: const ValueKey('input_send_btn'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(64, 32),
                          fixedSize: const Size.fromHeight(32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('Gửi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        key: const ValueKey('input_stop_btn'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(64, 32),
                          fixedSize: const Size.fromHeight(32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 14),
                        label: const Text('Dừng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  Expanded(
                    child: WorkScheduleDialog(
                      sessionId: 'sess_linux_btns',
                      workingDir: tempDir.path,
                      docFiles: [docNewSpec.path],
                      model: 'antigravity-cli',
                      databaseService: fakeDb,
                      onDispatchToPrompt: (_, {required sendImmediately}) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byKey(const ValueKey('global_theme_elevated_btn'))).height, greaterThanOrEqualTo(32.0));
        expect(tester.getSize(find.byKey(const ValueKey('input_scope_btn'))).height, equals(32.0));
        expect(tester.getSize(find.byKey(const ValueKey('input_send_btn'))).height, equals(32.0));
        expect(tester.getSize(find.byKey(const ValueKey('input_stop_btn'))).height, equals(32.0));
        expect(tester.getSize(find.byKey(const ValueKey('dispatch_prompt_T1'))).height, equals(32.0));
        expect(tester.getSize(find.byKey(const ValueKey('dispatch_run_T1'))).height, equals(32.0));
        expect(tester.getSize(find.byKey(const ValueKey('schedule_submit_button'))).height, equals(32.0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'editing an existing task and adding a manual task in WorkScheduleDialog updates UI and persists to DatabaseService',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = _InMemoryDatabaseService();
      await fakeDb.saveWorkSchedule(
        sessionId: 'sess_edit_task',
        projectName: 'VinTrans Taxi',
        summary: 'Nghiệp vụ Đổ dầu',
        docFiles: [docNewSpec.path],
        generatedAt: DateTime(2026, 11, 16, 9, 0),
        tasks: [
          {
            'id': 'T1',
            'title': 'Phát triển luồng Đề xuất đổ dầu ban đầu',
            'description': 'Mô tả cũ trước khi chỉnh sửa',
            'start_date': '2026-11-16',
            'end_date': '2026-11-16',
            'priority': 'medium',
            'phase': 'Nghiệp vụ Đổ dầu',
            'source_doc': 'yeu_cau_moi_saomai.md',
            'done': false,
          },
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkScheduleDialog(
              sessionId: 'sess_edit_task',
              workingDir: tempDir.path,
              docFiles: [docNewSpec.path],
              model: 'antigravity-cli',
              databaseService: fakeDb,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Phát triển luồng Đề xuất đổ dầu ban đầu'), findsWidgets);
      expect(find.text('Mô tả cũ trước khi chỉnh sửa'), findsOneWidget);

      // Bấm nút Sửa trên thẻ công việc T1
      await tester.tap(find.byKey(const ValueKey('edit_task_T1')));
      await tester.pumpAndSettle();

      expect(find.text('Chỉnh sửa công việc T1'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('save_edit_task_button'))).height, equals(32.0));
      expect(tester.getSize(find.byKey(const ValueKey('cancel_edit_task_button'))).height, equals(32.0));

      // Sửa tiêu đề, mô tả, hạng mục và đổi mức ưu tiên sang Cao
      await tester.enterText(
        find.byKey(const ValueKey('edit_task_title_input')),
        'Phát triển luồng Đề xuất đổ dầu, Điều phối duyệt mở QR 1 lần',
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit_task_description_input')),
        'Thêm nút Đề xuất đổ dầu trên App Tài xế, tự động ẩn QR sau khi chụp đủ ảnh Taplo + Phiếu nhận dầu.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit_task_phase_input')),
        'Nghiệp vụ Đổ dầu & QR Cây dầu',
      );
      await tester.tap(find.byKey(const ValueKey('edit_task_priority_high')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save_edit_task_button')));
      await tester.pumpAndSettle();

      // Kiểm tra giao diện đã cập nhật ngay lập tức
      expect(find.textContaining('Phát triển luồng Đề xuất đổ dầu, Điều phối duyệt mở QR 1 lần'), findsWidgets);
      expect(
        find.text('Thêm nút Đề xuất đổ dầu trên App Tài xế, tự động ẩn QR sau khi chụp đủ ảnh Taplo + Phiếu nhận dầu.'),
        findsOneWidget,
      );
      expect(find.text('Nghiệp vụ Đổ dầu & QR Cây dầu'), findsOneWidget);
      expect(find.text('Ưu tiên: Cao'), findsOneWidget);

      // Kiểm tra dữ liệu đã được lưu xuống DatabaseService (SQLite)
      final savedAfterEdit = await fakeDb.getWorkSchedule('sess_edit_task');
      expect(savedAfterEdit, isNotNull);
      final savedTasks = (savedAfterEdit!['tasks'] as List).cast<Map<String, dynamic>>();
      expect(savedTasks.length, equals(1));
      expect(savedTasks.single['title'], equals('Phát triển luồng Đề xuất đổ dầu, Điều phối duyệt mở QR 1 lần'));
      expect(
        savedTasks.single['description'],
        equals('Thêm nút Đề xuất đổ dầu trên App Tài xế, tự động ẩn QR sau khi chụp đủ ảnh Taplo + Phiếu nhận dầu.'),
      );
      expect(savedTasks.single['phase'], equals('Nghiệp vụ Đổ dầu & QR Cây dầu'));
      expect(savedTasks.single['priority'], equals('high'));

      // Kiểm tra thêm mới 1 đầu việc thủ công bằng nút Thêm việc
      await tester.tap(find.byKey(const ValueKey('add_manual_task_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('edit_task_title_input')),
        'Kiểm thử nghiệm thu QR Cây dầu trên thiết bị thực tế',
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit_task_description_input')),
        'Test trọn vẹn luồng khoá mã QR sau 1 lần quét.',
      );
      await tester.tap(find.byKey(const ValueKey('save_edit_task_button')));
      await tester.pumpAndSettle();

      final savedAfterAdd = await fakeDb.getWorkSchedule('sess_edit_task');
      final tasksAfterAdd = (savedAfterAdd!['tasks'] as List).cast<Map<String, dynamic>>();
      expect(tasksAfterAdd.length, equals(2));
      expect(tasksAfterAdd[1]['id'], equals('T2'));
      expect(tasksAfterAdd[1]['title'], equals('Kiểm thử nghiệm thu QR Cây dầu trên thiết bị thực tế'));
    },
  );
}
