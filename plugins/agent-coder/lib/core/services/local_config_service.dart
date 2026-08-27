import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/server_model.dart';
import 'encryption_service.dart';
import 'storage_service.dart';

class LocalConfigService {
  static final LocalConfigService _instance = LocalConfigService._internal();
  factory LocalConfigService() => _instance;
  LocalConfigService._internal();

  final EncryptionService _enc = EncryptionService();
  String? _resolvedConfigPath;
  String? _currentUserKey;
  Map<String, dynamic> _cachedConfig = {};

  String? get resolvedConfigPath => _resolvedConfigPath;
  String? get currentUserKey => _currentUserKey;

  static const Map<String, dynamic> defaultRawConfig = {
    'server_ip': '127.0.0.1',
    'ssh_user': 'root',
    'ssh_pass': '',
    'ssh_port': 22,
    'proxy_api_key': '',
    'proxy_base_url': 'https://openrouter.ai/api/v1',
    'ai_model': 'glm-5.3',
    'remote_work_dir': '/root',
    'api_port': 8000,
    'secret_token': 'super_secret_token_123',
    'servers': [],
  };

  Future<void> switchUser(String userKey) async {
    final sanitized = StorageService.sanitizeUserKey(userKey);
    if (_currentUserKey == sanitized && _cachedConfig.isNotEmpty) return;
    _currentUserKey = sanitized;
    _resolvedConfigPath = null;
    _cachedConfig = {};
    await loadConfig(userKey: _currentUserKey);
  }

  Future<String> _resolveConfigPath({String? userKey}) async {
    final key = userKey ?? _currentUserKey ?? await StorageService().getUserKey();
    final configFileName = key.isNotEmpty ? 'config_$key.json' : 'config.json';

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      final appDir = Directory(p.join(home, '.ai_type_agent'));
      if (!appDir.existsSync()) {
        try {
          appDir.createSync(recursive: true);
        } catch (_) {}
      }

      final userCfgPath = p.join(appDir.path, configFileName);
      final masterCfgPath = p.join(appDir.path, 'config.json');

      if (File(userCfgPath).existsSync()) {
        _resolvedConfigPath = p.normalize(userCfgPath);
        return _resolvedConfigPath!;
      }

      if (key.isNotEmpty && File(masterCfgPath).existsSync()) {
        try {
          File(masterCfgPath).copySync(userCfgPath);
          _resolvedConfigPath = p.normalize(userCfgPath);
          return _resolvedConfigPath!;
        } catch (_) {}
      }

      _resolvedConfigPath = p.normalize(userCfgPath);
      return _resolvedConfigPath!;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final targetPath = p.join(appDocDir.path, configFileName);
      if (key.isNotEmpty && !File(targetPath).existsSync()) {
        final defaultCfg = p.join(appDocDir.path, 'config.json');
        if (File(defaultCfg).existsSync()) {
          try {
            File(defaultCfg).copySync(targetPath);
          } catch (_) {}
        }
      }
      _resolvedConfigPath = targetPath;
      return _resolvedConfigPath!;
    } catch (_) {
      _resolvedConfigPath = configFileName;
      return configFileName;
    }
  }

  Future<Map<String, dynamic>> loadConfig({String? userKey}) async {
    final filePath = await _resolveConfigPath(userKey: userKey);
    final file = File(filePath);

    if (!file.existsSync()) {
      _cachedConfig = Map<String, dynamic>.from(defaultRawConfig);
      await saveConfig(_cachedConfig, userKey: userKey);
      return _cachedConfig;
    }

    try {
      final content = await file.readAsString();
      final raw = jsonDecode(content) as Map<String, dynamic>;
      bool needsReSave = false;

      // Decrypt overall vault if present
      if (raw['_encrypted_vault'] != null) {
        try {
          final decryptedVault = _enc.decryptValue(raw['_encrypted_vault']);
          final vaultJson = jsonDecode(decryptedVault) as Map<String, dynamic>;
          raw.addAll(vaultJson);
        } catch (_) {}
      }

      final result = <String, dynamic>{};
      for (final entry in raw.entries) {
        if (entry.key == '_encrypted_vault') continue;
        final k = entry.key;
        final v = entry.value;

        if (v is String && v.startsWith('enc:')) {
          final dec = _enc.decryptValue(v);
          if (k == 'ssh_port' || k == 'api_port') {
            result[k] = int.tryParse(dec) ?? dec;
          } else if (k == 'servers') {
            try {
              final parsed = jsonDecode(dec);
              if (parsed is List) {
                result[k] = parsed;
              } else {
                result[k] = [];
              }
            } catch (_) {
              result[k] = [];
            }
          } else if (dec == 'true') {
            result[k] = true;
          } else if (dec == 'false') {
            result[k] = false;
          } else {
            result[k] = dec;
          }
        } else {
          // If any field on disk was stored as plaintext, flag for immediate re-encryption
          if (v != null && (v is! String || !v.startsWith('enc:'))) {
            needsReSave = true;
          }
          if (k == 'ssh_port' || k == 'api_port') {
            result[k] = int.tryParse(v.toString()) ?? v;
          } else {
            result[k] = v;
          }
        }
      }

      // Ensure each server in servers list is clean and decrypted
      if (result['servers'] is List) {
        final rawServers = result['servers'] as List;
        final cleanServers = <Map<String, dynamic>>[];
        for (final item in rawServers) {
          if (item is Map) {
            final m = <String, dynamic>{};
            for (final se in item.entries) {
              final sk = se.key.toString();
              final sv = se.value;
              if (sv is String && sv.startsWith('enc:')) {
                final decSv = _enc.decryptValue(sv);
                if (sk == 'ssh_port' || sk == 'api_port') {
                  m[sk] = int.tryParse(decSv) ?? decSv;
                } else if (decSv == 'true') {
                  m[sk] = true;
                } else if (decSv == 'false') {
                  m[sk] = false;
                } else {
                  m[sk] = decSv;
                }
              } else {
                m[sk] = sv;
              }
            }
            cleanServers.add(m);
          }
        }
        result['servers'] = cleanServers;
      }

      // Fill in defaults for missing keys
      for (final entry in defaultRawConfig.entries) {
        if (!result.containsKey(entry.key)) {
          result[entry.key] = entry.value;
        }
      }

      _cachedConfig = result;
      if (needsReSave) {
        await saveConfig(result, userKey: userKey);
      }
      return result;
    } catch (e) {
      _cachedConfig = Map<String, dynamic>.from(defaultRawConfig);
      return _cachedConfig;
    }
  }

  Future<bool> saveConfig(Map<String, dynamic> newConfig, {String? userKey}) async {
    try {
      final filePath = await _resolveConfigPath(userKey: userKey);
      final file = File(filePath);

      final toSave = <String, dynamic>{};
      for (final entry in newConfig.entries) {
        final k = entry.key;
        final v = entry.value;

        if (k == '_encrypted_vault') continue;

        if (v != null) {
          if (v is List || v is Map) {
            toSave[k] = _enc.encryptValue(jsonEncode(v));
          } else {
            toSave[k] = _enc.encryptValue(v.toString());
          }
        }
      }

      // Also persist encrypted vault for backward compatibility
      final rawJson = jsonEncode(newConfig);
      toSave['_encrypted_vault'] = _enc.encryptValue(rawJson);

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(toSave));
      _cachedConfig = Map<String, dynamic>.from(newConfig);
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Map<String, dynamic>> _extractServersList(Map<String, dynamic> cfg) {
    dynamic raw = cfg['servers'];
    if (raw is String) {
      if (raw.startsWith('enc:')) {
        raw = _enc.decryptValue(raw);
      }
      try {
        raw = jsonDecode(raw);
      } catch (_) {}
    }

    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        } else if (item is String) {
          try {
            final m = jsonDecode(item);
            if (m is Map) list.add(Map<String, dynamic>.from(m));
          } catch (_) {}
        }
      }
    }
    return list;
  }

  Future<List<ServerModel>> getServers() async {
    final cfg = await loadConfig();
    final serversList = <ServerModel>[];
    final activeId = cfg['active_server_id']?.toString() ?? '';

    final rawList = _extractServersList(cfg);
    for (final item in rawList) {
      final id = item['id']?.toString() ?? '';
      final ip = item['server_ip']?.toString() ?? '';
      final isCurr = activeId.isNotEmpty && activeId != 'local' && (id == activeId || ip == activeId);
      final s = ServerModel.fromJson(item, isCurrent: isCurr);
      serversList.add(s);
    }

    // Recovery check: If serversList is empty, but cfg has a remote server_ip, restore it!
    if (serversList.isEmpty) {
      final ip = cfg['server_ip']?.toString() ?? '';
      if (ip.isNotEmpty && ip != '127.0.0.1' && ip != 'localhost') {
        final restored = ServerModel.fromJson(cfg, isCurrent: activeId != 'local');
        serversList.add(restored);
        cfg['servers'] = [restored.toJson()];
        await saveConfig(cfg, userKey: _currentUserKey);
      }
    }

    return serversList;
  }

  Future<bool> addOrUpdateServer(ServerModel server) async {
    final cfg = await loadConfig();
    final servers = _extractServersList(cfg);

    int existingIdx = servers.indexWhere((item) =>
        item['id'] == server.id || (item['server_ip'] == server.serverIp && item['ssh_port']?.toString() == server.sshPort.toString()));

    if (existingIdx >= 0) {
      servers[existingIdx] = server.toJson();
    } else {
      servers.add(server.toJson());
    }

    final activeId = cfg['active_server_id']?.toString() ?? '';
    final isActive = server.isSelected ||
        (activeId.isNotEmpty && activeId != 'local' && (activeId == server.id || activeId == server.serverIp));

    if (isActive) {
      cfg['active_server_id'] = server.id;
      cfg['server_ip'] = server.serverIp;
      cfg['ssh_user'] = server.sshUser;
      cfg['ssh_pass'] = server.sshPass;
      cfg['ssh_port'] = server.sshPort;
      cfg['ai_model'] = server.aiModel;
      cfg['remote_work_dir'] = server.remoteWorkDir;
      cfg['api_port'] = server.apiPort;
      cfg['secret_token'] = server.secretToken;
    }

    final currentActiveId = cfg['active_server_id']?.toString() ?? '';
    for (int i = 0; i < servers.length; i++) {
      final sId = servers[i]['id']?.toString();
      final sIp = servers[i]['server_ip']?.toString();
      final isAct = (currentActiveId.isNotEmpty && currentActiveId != 'local') && (sId == currentActiveId || sIp == currentActiveId);
      servers[i]['is_selected'] = isAct;
      servers[i]['set_active'] = isAct;
    }

    cfg['servers'] = servers;
    return await saveConfig(cfg, userKey: _currentUserKey);
  }

  Future<bool> selectServer(ServerModel server) async {
    final cfg = await loadConfig();
    final rawServers = _extractServersList(cfg);
    final isLocal = (server.id == 'local' || server.serverIp == '127.0.0.1' || server.serverIp == 'localhost');

    final updatedServers = <Map<String, dynamic>>[];
    for (final item in rawServers) {
      final m = Map<String, dynamic>.from(item);
      final isSel = !isLocal && (m['id'] == server.id || m['server_ip'] == server.serverIp);
      m['is_selected'] = isSel;
      m['set_active'] = isSel;
      updatedServers.add(m);
    }

    cfg['servers'] = updatedServers;
    if (isLocal) {
      cfg['active_server_id'] = 'local';
      cfg['server_ip'] = '127.0.0.1';
    } else {
      cfg['active_server_id'] = server.id;
      cfg['server_ip'] = server.serverIp;
      cfg['ssh_user'] = server.sshUser;
      cfg['ssh_pass'] = server.sshPass;
      cfg['ssh_port'] = server.sshPort;
      cfg['ai_model'] = server.aiModel;
      cfg['remote_work_dir'] = server.remoteWorkDir;
      cfg['api_port'] = server.apiPort;
      cfg['secret_token'] = server.secretToken;
    }

    return await saveConfig(cfg, userKey: _currentUserKey);
  }

  Future<bool> deleteServer(String serverIdOrIp) async {
    if (serverIdOrIp.trim().isEmpty) return false;
    final cfg = await loadConfig();
    final servers = _extractServersList(cfg);

    servers.removeWhere((item) {
      final id = item['id']?.toString() ?? '';
      final ip = item['server_ip']?.toString() ?? '';
      return (id.isNotEmpty && id == serverIdOrIp) || (ip.isNotEmpty && ip == serverIdOrIp);
    });

    cfg['servers'] = servers;
    if (cfg['active_server_id'] == serverIdOrIp || cfg['server_ip'] == serverIdOrIp || servers.isEmpty) {
      cfg['active_server_id'] = 'local';
      cfg['server_ip'] = '127.0.0.1';
    }

    return await saveConfig(cfg, userKey: _currentUserKey);
  }
}
