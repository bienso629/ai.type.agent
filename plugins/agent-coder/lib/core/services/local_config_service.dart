import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/server_model.dart';
import 'encryption_service.dart';

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
    // Single config.json mode - no separate user config files
    _cachedConfig = {};
    await loadConfig();
  }

  Future<String> _resolveConfigPath() async {
    if (_resolvedConfigPath != null) return _resolvedConfigPath!;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      final appDir = Directory(p.join(home, '.ai_type_agent'));
      if (!appDir.existsSync()) {
        try {
          appDir.createSync(recursive: true);
        } catch (_) {}
      }
      final masterCfgPath = p.join(appDir.path, 'config.json');
      _resolvedConfigPath = p.normalize(masterCfgPath);
      return _resolvedConfigPath!;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final targetPath = p.join(appDocDir.path, 'config.json');
      _resolvedConfigPath = targetPath;
      return _resolvedConfigPath!;
    } catch (_) {
      _resolvedConfigPath = 'config.json';
      return _resolvedConfigPath!;
    }
  }

  Future<Map<String, dynamic>> loadConfig() async {
    final filePath = await _resolveConfigPath();
    final file = File(filePath);

    if (!file.existsSync()) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      final legacyFile = File(p.join(home, '.tadu_ai_agent', 'config.json'));
      if (legacyFile.existsSync()) {
        try {
          file.parent.createSync(recursive: true);
          legacyFile.copySync(file.path);
        } catch (_) {}
      }
    }

    if (!file.existsSync()) {
      _cachedConfig = Map<String, dynamic>.from(defaultRawConfig);
      await saveConfig(_cachedConfig);
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

      // If servers list is empty, check legacy configs (.tadu_ai_agent) to auto-migrate servers
      if (result['servers'] == null || (result['servers'] is List && (result['servers'] as List).isEmpty)) {
        final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
        for (final legacyName in ['config_lophocvinhxuan.json', 'config.json']) {
          final legacyFile = File(p.join(home, '.tadu_ai_agent', legacyName));
          if (legacyFile.existsSync()) {
            try {
              final legacyContent = legacyFile.readAsStringSync();
              final legacyRaw = jsonDecode(legacyContent) as Map<String, dynamic>;
              final legacyList = _extractServersList(legacyRaw);
              if (legacyList.isNotEmpty) {
                result['servers'] = legacyList;
                needsReSave = true;
                break;
              }
            } catch (_) {}
          }
        }
      }

      // Fill in defaults for missing keys
      for (final entry in defaultRawConfig.entries) {
        if (!result.containsKey(entry.key)) {
          result[entry.key] = entry.value;
        }
      }

      _cachedConfig = result;
      if (needsReSave) {
        await saveConfig(result);
      }
      return result;
    } catch (e) {
      _cachedConfig = Map<String, dynamic>.from(defaultRawConfig);
      return _cachedConfig;
    }
  }

  Future<bool> saveConfig(Map<String, dynamic> newConfig) async {
    try {
      final current = _cachedConfig.isNotEmpty ? Map<String, dynamic>.from(_cachedConfig) : await loadConfig();
      final merged = Map<String, dynamic>.from(current);

      for (final e in newConfig.entries) {
        if (e.key == 'servers' && e.value is List && (e.value as List).isEmpty && current['servers'] is List && (current['servers'] as List).isNotEmpty) {
          // Keep current servers if newConfig mistakenly passed empty servers
          continue;
        }
        merged[e.key] = e.value;
      }

      final filePath = await _resolveConfigPath();
      final file = File(filePath);

      final toSave = <String, dynamic>{};
      for (final entry in merged.entries) {
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
      final rawJson = jsonEncode(merged);
      toSave['_encrypted_vault'] = _enc.encryptValue(rawJson);

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(toSave));
      _cachedConfig = merged;
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Map<String, dynamic>> _extractServersList(Map<String, dynamic> cfg) {
    dynamic raw = cfg['servers'];
    if (raw == null) return [];
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
            var s = item;
            if (s.startsWith('enc:')) s = _enc.decryptValue(s);
            final m = jsonDecode(s);
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
    return await saveConfig(cfg);
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

    return await saveConfig(cfg);
  }

  Future<bool> deleteServer(String serverIdOrIp) async {
    final cleanId = serverIdOrIp.trim();
    if (cleanId.isEmpty || cleanId == 'local' || cleanId == '127.0.0.1' || cleanId == 'localhost') {
      return false;
    }
    final cfg = await loadConfig();
    final servers = _extractServersList(cfg);

    servers.removeWhere((item) {
      final id = item['id']?.toString() ?? '';
      final ip = item['server_ip']?.toString() ?? '';
      return (id.isNotEmpty && id == cleanId) || (ip.isNotEmpty && ip == cleanId);
    });

    cfg['servers'] = servers;
    if (cfg['active_server_id'] == serverIdOrIp || cfg['server_ip'] == serverIdOrIp || servers.isEmpty) {
      cfg['active_server_id'] = 'local';
      cfg['server_ip'] = '127.0.0.1';
    }

    return await saveConfig(cfg);
  }

  Future<String> exportServersJson({bool includeFullConfig = false}) async {
    final cfg = await loadConfig();
    final servers = _extractServersList(cfg);
    final exportData = {
      'version': '1.0.0',
      'app': 'AI Type Agent',
      'exported_at': DateTime.now().toIso8601String(),
      'servers_count': servers.length,
      'servers': servers,
      if (includeFullConfig) ...{
        'proxy_base_url': cfg['proxy_base_url'],
        'ai_model': cfg['ai_model'],
        'remote_work_dir': cfg['remote_work_dir'],
        'api_port': cfg['api_port'],
      }
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<int> importServersJson(String jsonStr, {bool overwrite = false}) async {
    final dynamic parsed = jsonDecode(jsonStr);
    List<dynamic> incomingServers = [];

    if (parsed is List) {
      incomingServers = parsed;
    } else if (parsed is Map) {
      if (parsed['servers'] is List) {
        incomingServers = parsed['servers'] as List;
      } else if (parsed['server_ip'] != null) {
        incomingServers = [parsed];
      }
    }

    if (incomingServers.isEmpty) {
      throw const FormatException('Không tìm thấy danh sách máy chủ hợp lệ trong dữ liệu JSON.');
    }

    final cfg = await loadConfig();
    final currentServers = overwrite ? <Map<String, dynamic>>[] : _extractServersList(cfg);

    int importedCount = 0;
    for (final raw in incomingServers) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);

      final cleaned = <String, dynamic>{};
      for (final e in item.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (v is String && v.startsWith('enc:')) {
          cleaned[k] = _enc.decryptValue(v);
        } else {
          cleaned[k] = v;
        }
      }

      final s = ServerModel.fromJson(cleaned);
      final idx = currentServers.indexWhere((existing) =>
          (s.id.isNotEmpty && existing['id'] == s.id) ||
          (s.serverIp.isNotEmpty &&
              existing['server_ip'] == s.serverIp &&
              existing['ssh_port']?.toString() == s.sshPort.toString()));

      if (idx >= 0) {
        currentServers[idx] = s.toJson();
      } else {
        currentServers.add(s.toJson());
      }
      importedCount++;
    }

    cfg['servers'] = currentServers;
    await saveConfig(cfg);
    return importedCount;
  }
}
