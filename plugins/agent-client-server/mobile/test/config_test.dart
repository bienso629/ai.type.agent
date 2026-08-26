import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/local_config_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/models/server_model.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });
  test('LocalConfigService loads and decrypts config.json', () async {
    final cfgService = LocalConfigService();
    final config = await cfgService.loadConfig();

    print('Resolved Config Path: ${cfgService.resolvedConfigPath}');
    print('Config keys: ${config.keys.toList()}');
    print('Server IP: ${config['server_ip']}');
    print('SSH User: ${config['ssh_user']}');
    print('SSH Port: ${config['ssh_port']}');
    print('AI Model: ${config['ai_model']}');
    print('Proxy Base URL: ${config['proxy_base_url']}');
    print('Servers raw: ${config['servers']}');
    final servers = await cfgService.getServers();
    print('Loaded servers count: ${servers.length}');
    for (final s in servers) {
      print('  - Server: id=${s.id}, ip=${s.serverIp}, name=${s.name}, selected=${s.isSelected}');
    }

    expect(config['server_ip'], '103.90.232.157');
    expect(config['ssh_user'], 'root');
    expect(config['ssh_port'], 7878);
    expect(config['ai_model'], 'glm-5.3');
  });

  test('LocalConfigService supports adding, updating, and deleting servers', () async {
    final cfgService = LocalConfigService();
    await cfgService.switchUser('testuser');

    final newServer = ServerModel(
      id: 'srv_test_1',
      name: 'Test Server 1',
      serverIp: '192.168.1.100',
      sshPort: 2222,
      sshUser: 'ubuntu',
      sshPass: 'pass123',
    );

    final okAdd = await cfgService.addOrUpdateServer(newServer);
    expect(okAdd, isTrue);

    final listAfterAdd = await cfgService.getServers();
    expect(listAfterAdd.any((s) => s.id == 'srv_test_1' && s.name == 'Test Server 1'), isTrue);

    // Update server
    final updatedServer = newServer.copyWith(name: 'Updated Server 1', sshPort: 2223);
    final okUpdate = await cfgService.addOrUpdateServer(updatedServer);
    expect(okUpdate, isTrue);

    final listAfterUpdate = await cfgService.getServers();
    final found = listAfterUpdate.firstWhere((s) => s.id == 'srv_test_1');
    expect(found.name, 'Updated Server 1');
    expect(found.sshPort, 2223);

    // Delete server
    final okDelete = await cfgService.deleteServer('srv_test_1');
    expect(okDelete, isTrue);

    final listAfterDelete = await cfgService.getServers();
    expect(listAfterDelete.any((s) => s.id == 'srv_test_1'), isFalse);
  });

  test('All config values on disk are 100% encrypted with enc: prefix', () async {
    final cfgService = LocalConfigService();
    await cfgService.switchUser('testuser');

    final testServer = ServerModel(
      id: 'srv_enc_check',
      name: 'Encrypted Check Server',
      serverIp: '10.0.0.1',
      sshPort: 2222,
      sshUser: 'admin',
      sshPass: 'super_secret_password_123',
    );
    await cfgService.addOrUpdateServer(testServer);

    final path = cfgService.resolvedConfigPath;
    expect(path, isNotNull);
    final fileContent = await File(path!).readAsString();
    final rawDiskMap = jsonDecode(fileContent) as Map<String, dynamic>;

    print('Disk config keys: ${rawDiskMap.keys.toList()}');
    for (final entry in rawDiskMap.entries) {
      expect(entry.value, isA<String>(), reason: 'Key ${entry.key} must be an encrypted string');
      expect((entry.value as String).startsWith('enc:'), isTrue, reason: 'Key ${entry.key} must start with enc:');
    }

    // Verify plaintext password or IP does not exist anywhere in the raw file content
    expect(fileContent.contains('super_secret_password_123'), isFalse);
    expect(fileContent.contains('Encrypted Check Server'), isFalse);
  });

  test('Adding multiple servers ensures exactly ONE server is selected/active', () async {
    final cfgService = LocalConfigService();
    await cfgService.switchUser('multi_test_user');

    final server1 = ServerModel(
      id: 'srv_1',
      name: 'Server One',
      serverIp: '10.0.0.1',
      sshPort: 22,
      sshUser: 'root',
      isSelected: true,
    );
    final server2 = ServerModel(
      id: 'srv_2',
      name: 'Server Two',
      serverIp: '10.0.0.2',
      sshPort: 22,
      sshUser: 'root',
      isSelected: false,
    );
    final server3 = ServerModel(
      id: 'srv_3',
      name: 'Server Three',
      serverIp: '10.0.0.3',
      sshPort: 22,
      sshUser: 'root',
      isSelected: false,
    );

    await cfgService.addOrUpdateServer(server1);
    await cfgService.addOrUpdateServer(server2);
    await cfgService.addOrUpdateServer(server3);

    final list = await cfgService.getServers();
    expect(list.length >= 3, isTrue);
    final selectedCount = list.where((s) => s.isSelected).length;
    expect(selectedCount, 1, reason: 'Exactly one server must have isSelected == true');
    expect(list.firstWhere((s) => s.isSelected).id, 'srv_1');

    // Now select server2
    await cfgService.selectServer(server2);
    final listAfterSelect = await cfgService.getServers();
    final selectedCount2 = listAfterSelect.where((s) => s.isSelected).length;
    expect(selectedCount2, 1);
    expect(listAfterSelect.firstWhere((s) => s.isSelected).id, 'srv_2');
  });
}
