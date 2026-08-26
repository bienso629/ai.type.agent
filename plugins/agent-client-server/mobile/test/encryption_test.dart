import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/encryption_service.dart';

void main() {
  test('EncryptionService decrypts config.json values correctly', () {
    final encService = EncryptionService();
    final configFile = File('../config.json');
    expect(configFile.existsSync(), isTrue);

    final rawJson = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final encServerIp = rawJson['server_ip'];
    final decServerIp = encService.decryptValue(encServerIp);
    print('Decrypted server_ip: $decServerIp');
    expect(decServerIp, '103.90.232.157');

    final encUser = rawJson['ssh_user'];
    final decUser = encService.decryptValue(encUser);
    print('Decrypted ssh_user: $decUser');
    expect(decUser, 'root');

    final encModel = rawJson['ai_model'];
    final decModel = encService.decryptValue(encModel);
    print('Decrypted ai_model: $decModel');
    expect(decModel, 'glm-5.3');
  });
}
