import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/server_model.dart';
import 'package:tadu_cloud_ai_agent_mobile/providers/server_provider.dart';
import 'package:tadu_cloud_ai_agent_mobile/screens/terminal/terminal_screen.dart';

class _TestServerProvider extends ServerProvider {
  @override
  Future<void> loadServers({bool silent = false}) async {}

  @override
  Future<void> loadGlobalConfig() async {}

  @override
  Future<void> fetchModels({bool forceRefresh = false, String? customBaseUrl, String? customApiKey}) async {}

  @override
  Future<void> scanCliAgents({bool forceRefresh = false}) async {}
}

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

  group('TerminalScreen Hide/Show & Tab Switching Preservation', () {
    testWidgets(
      'hiding and re-showing Terminal panel preserves exact dimensions, buffer lines, and split tabs without resize/reflow',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final terminalProvider = TerminalProvider();
        final serverProvider = _TestServerProvider();

        final tab1Main = TerminalPaneItem(
          id: 'tab1_main',
          title: 'Local Machine',
          workingDirectory: '/tmp',
        )..isConnected = true;
        final tab1Child = TerminalPaneItem(
          id: 'tab1_child',
          title: 'Local Machine',
          workingDirectory: '/tmp',
        )..isConnected = true;
        tab1Main.splitDirection = TerminalSplitDirection.vertical;
        tab1Main.childPane = tab1Child;

        final tab2Main = TerminalPaneItem(
          id: 'tab2_main',
          title: 'Local Machine',
          workingDirectory: '/tmp',
        )..isConnected = true;

        terminalProvider.seedPanesForTest(
          [tab1Main, tab2Main],
          activeIndex: 0,
        );

        final resizeEvents = <String>[];
        tab1Main.terminal.onResize = (w, h, pw, ph) {
          resizeEvents.add('tab1Main:${w}x$h');
        };
        tab1Child.terminal.onResize = (w, h, pw, ph) {
          resizeEvents.add('tab1Child:${w}x$h');
        };
        tab2Main.terminal.onResize = (w, h, pw, ph) {
          resizeEvents.add('tab2Main:${w}x$h');
        };

        bool showTerminalPanel = true;
        double lastPanelWidth = 700.0;
        double lastPanelHeight = 900.0;
        late StateSetter outerSetState;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TerminalProvider>.value(value: terminalProvider),
              ChangeNotifierProvider<ServerProvider>.value(value: serverProvider),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    outerSetState = setState;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 300) {
                          lastPanelWidth = constraints.maxWidth * 0.5;
                        }
                        if (constraints.maxHeight >= 200) {
                          lastPanelHeight = constraints.maxHeight;
                        }
                        final panelWidth = showTerminalPanel ? (constraints.maxWidth * 0.5) : lastPanelWidth;
                        final panelHeight = constraints.maxHeight >= 200 ? constraints.maxHeight : lastPanelHeight;
                        final occupiedWidth = showTerminalPanel ? panelWidth : 0.0;
                        final occupiedHeight = showTerminalPanel ? constraints.maxHeight : 0.0;

                        return Row(
                          children: [
                            const Expanded(child: SizedBox.expand()),
                            Offstage(
                              offstage: !showTerminalPanel,
                              child: TickerMode(
                                enabled: showTerminalPanel,
                                child: ClipRect(
                                  child: SizedBox(
                                    width: occupiedWidth,
                                    height: occupiedHeight,
                                    child: OverflowBox(
                                      alignment: Alignment.topLeft,
                                      minWidth: panelWidth,
                                      maxWidth: panelWidth,
                                      minHeight: panelHeight,
                                      maxHeight: panelHeight,
                                      child: TerminalScreen(
                                        onHidePanel: () {
                                          setState(() {
                                            showTerminalPanel = false;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialMainCols = tab1Main.terminal.viewWidth;
        final initialMainRows = tab1Main.terminal.viewHeight;
        final initialTab2Cols = tab2Main.terminal.viewWidth;
        expect(initialMainCols, greaterThan(30));
        expect(initialTab2Cols, greaterThan(30));

        // Write long lines into all panes
        const tab1TopLine = 'yenai@ubuntu:~/app_tai_xe\$ npm run build -- --production-check-long-line';
        const tab1BottomLine = 'yenai@ubuntu:~/ai.type\$ git status --short --branch --ahead-behind';
        const tab2Line = 'yenai@ubuntu:~/server\$ docker compose ps --format table-output-check';

        tab1Main.terminal.write('$tab1TopLine\r\nBUILD_OK_TOP\r\n');
        tab1Child.terminal.write('$tab1BottomLine\r\nSTATUS_OK_BOTTOM\r\n');
        tab2Main.terminal.write('$tab2Line\r\nDOCKER_OK_TAB2\r\n');
        await tester.pump();

        resizeEvents.clear();

        // Hide Terminal panel (equivalent to clicking "Ẩn Terminal")
        outerSetState(() {
          showTerminalPanel = false;
        });
        await tester.pump();

        // Dimensions MUST remain completely unchanged (never collapsed to 0 or 1 col!)
        expect(tab1Main.terminal.viewWidth, equals(initialMainCols));
        expect(tab1Main.terminal.viewHeight, equals(initialMainRows));
        expect(tab2Main.terminal.viewWidth, equals(initialTab2Cols));
        expect(resizeEvents, isEmpty);

        // Show Terminal panel again (equivalent to clicking "Mở Terminal")
        outerSetState(() {
          showTerminalPanel = true;
        });
        await tester.pumpAndSettle();

        expect(tab1Main.terminal.viewWidth, equals(initialMainCols));
        expect(tab1Main.terminal.viewHeight, equals(initialMainRows));
        expect(tab2Main.terminal.viewWidth, equals(initialTab2Cols));
        expect(resizeEvents, isEmpty);

        // Switch to Tab 2 and back to Tab 1
        terminalProvider.setActivePaneIndex(1);
        await tester.pumpAndSettle();
        terminalProvider.setActivePaneIndex(0);
        await tester.pumpAndSettle();

        expect(resizeEvents, isEmpty);

        // Verify un-reflowed text in all 3 buffers
        expect(tab1Main.terminal.buffer.getText(), contains(tab1TopLine));
        expect(tab1Main.terminal.buffer.getText(), contains('BUILD_OK_TOP'));
        expect(tab1Child.terminal.buffer.getText(), contains(tab1BottomLine));
        expect(tab1Child.terminal.buffer.getText(), contains('STATUS_OK_BOTTOM'));
        expect(tab2Main.terminal.buffer.getText(), contains(tab2Line));
        expect(tab2Main.terminal.buffer.getText(), contains('DOCKER_OK_TAB2'));
      },
    );
  });
}
