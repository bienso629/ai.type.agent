import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DatabaseService reads existing sessions and messages from chat_history.db', () async {
    final dbService = DatabaseService();
    await dbService.init();

    print('Resolved DB Path: ${dbService.resolvedPath}');
    expect(dbService.resolvedPath, isNotNull);

    final sessions = await dbService.getSessions();
    print('Total sessions loaded: ${sessions.length}');
    for (final s in sessions) {
      print('- Session [${s.id}]: ${s.title} (${s.messageCount} msgs)');
    }
    expect(sessions.isNotEmpty, isTrue);

    final firstSession = sessions.first;
    final history = await dbService.getMessages(firstSession.id, limit: 10);
    print('Loaded ${history.messages.length} messages for session ${firstSession.id}');
    for (final m in history.messages) {
      print('  [${m.role}] ${m.content.replaceAll("\n", " ").substring(0, m.content.length > 50 ? 50 : m.content.length)}...');
    }
  });

  test('DatabaseService supports user-specific chat_history_{username}.db', () async {
    final dbService = DatabaseService();
    await dbService.switchUser('yenai');

    expect(dbService.currentUserKey, 'yenai');
    expect(dbService.resolvedPath, contains('chat_history_yenai.db'));
    print('User yenai DB Path: ${dbService.resolvedPath}');
    final sessions = await dbService.getSessions();
    expect(sessions.isNotEmpty, isTrue);
    print('Loaded ${sessions.length} sessions for user yenai');
  });
}
