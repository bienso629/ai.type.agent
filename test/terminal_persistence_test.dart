import 'package:flutter_test/flutter_test.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/server_model.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/terminal_pane_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalPaneItem Serialization & Persistence', () {
    test('toJson and fromJson preserves local terminal attributes', () {
      final pane = TerminalPaneItem(
        id: 'pane_test_1',
        title: 'Local Backend',
        isRemoteSsh: false,
        workingDirectory: '/home/user/project',
      );
      pane.splitDirection = TerminalSplitDirection.horizontal;
      pane.childPane = TerminalPaneItem(
        id: 'subpane_test_1',
        title: 'Child Worker',
        isRemoteSsh: false,
        workingDirectory: '/home/user/project/worker',
      );

      final jsonMap = pane.toJson();
      expect(jsonMap['id'], 'pane_test_1');
      expect(jsonMap['title'], 'Local Backend');
      expect(jsonMap['isRemoteSsh'], false);
      expect(jsonMap['workingDirectory'], '/home/user/project');
      expect(jsonMap['splitDirection'], 'horizontal');
      expect(jsonMap['childPane'], isNotNull);
      expect(jsonMap['childPane']['id'], 'subpane_test_1');

      final restored = TerminalPaneItem.fromJson(jsonMap);
      expect(restored.id, 'pane_test_1');
      expect(restored.title, 'Local Backend');
      expect(restored.isRemoteSsh, false);
      expect(restored.workingDirectory, '/home/user/project');
      expect(restored.splitDirection, TerminalSplitDirection.horizontal);
      expect(restored.childPane, isNotNull);
      expect(restored.childPane!.id, 'subpane_test_1');
      expect(restored.childPane!.title, 'Child Worker');
      expect(restored.childPane!.workingDirectory, '/home/user/project/worker');
    });

    test('toJson and fromJson preserves SSH terminal attributes', () {
      final server = ServerModel(
        id: 'srv_123',
        name: 'Production VPS',
        serverIp: '192.168.1.100',
        sshPort: 2222,
        sshUser: 'deployer',
      );
      final pane = TerminalPaneItem(
        id: 'pane_ssh_1',
        title: 'Production VPS',
        isRemoteSsh: true,
        server: server,
        workingDirectory: '/var/www/app',
      );

      final jsonMap = pane.toJson();
      expect(jsonMap['isRemoteSsh'], true);
      expect(jsonMap['server'], isNotNull);
      expect(jsonMap['server']['id'], 'srv_123');

      final restored = TerminalPaneItem.fromJson(jsonMap);
      expect(restored.isRemoteSsh, true);
      expect(restored.server, isNotNull);
      expect(restored.server!.name, 'Production VPS');
      expect(restored.server!.serverIp, '192.168.1.100');
    });
  });
}
