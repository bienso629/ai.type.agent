import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/cli_scanner_service.dart';
import '../core/services/native_ssh_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  final NativeSshService _ssh = NativeSshService();
  final CliScannerService _cliScanner = CliScannerService();

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String _cloudAiModel = 'glm-5.3';
  String _activeCliAgent = 'antigravity-cli';
  String _engineMode = 'cloud'; // 'cloud' hoặc 'cli'
  List<LocalCliAgent> _installedCliAgents = [];
  List<String> _mitomModels = [];
  bool _isLoading = false;
  bool _isScanningCliAgents = false;
  bool _isLoadingMitomModels = false;
  String? _error;
  final Map<String, List<String>> _serverIpsMap = {};
  final Set<String> _loadingIpsServerIds = {};

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  String get globalAiModel => _cloudAiModel;
  String get cloudAiModel => _cloudAiModel;
  String get activeCliAgent => _activeCliAgent;
  String get engineMode => _engineMode;
  bool get isCliMode => _engineMode == 'cli';
  String get activeAgent => isCliMode ? _activeCliAgent : _cloudAiModel;
  List<LocalCliAgent> get installedCliAgents => _installedCliAgents;
  List<String> get mitomModels => _mitomModels;
  bool get isScanningCliAgents => _isScanningCliAgents;
  bool get isLoadingMitomModels => _isLoadingMitomModels;
  Map<String, List<String>> get serverIpsMap => _serverIpsMap;

  List<String> getIpsForServer(ServerModel server) {
    if (_serverIpsMap.containsKey(server.id)) {
      return _serverIpsMap[server.id]!;
    }
    if (server.serverIp.isNotEmpty) {
      return [server.serverIp];
    }
    return [];
  }

  bool isLoadingIps(String serverId) => _loadingIpsServerIds.contains(serverId);

  String get currentAiModel {
    if (isCliMode) {
      return _activeCliAgent.isNotEmpty ? _activeCliAgent : 'antigravity-cli';
    }
    if (_cloudAiModel.isNotEmpty) {
      return _cloudAiModel;
    }
    if (_selectedServer != null && _selectedServer!.aiModel.isNotEmpty) {
      return _selectedServer!.aiModel;
    }
    return 'glm-5.3';
  }

  bool get isLoading => _isLoading;
  String? get error => _error;

  ServerProvider() {
    loadServers();
    loadGlobalConfig();
    scanCliAgents();
    fetchMitomModels();
  }

  bool _isCli(String name) {
    final n = name.toLowerCase();
    return n.contains('cli') || n == 'agy' || n == 'claude' || n == 'gemini';
  }

  Future<void> fetchMitomModels({bool forceRefresh = false}) async {
    if (_mitomModels.isNotEmpty && !forceRefresh) return;
    _isLoadingMitomModels = true;
    notifyListeners();

    try {
      final list = await _api.fetchMitomModels();
      if (list.isNotEmpty) {
        _mitomModels = list;
      }
    } catch (_) {} finally {
      _isLoadingMitomModels = false;
      notifyListeners();
    }
  }

  Future<void> scanCliAgents({bool forceRefresh = false}) async {
    if (_installedCliAgents.isNotEmpty && !forceRefresh) return;
    _isScanningCliAgents = true;
    notifyListeners();

    try {
      _installedCliAgents = await _cliScanner.scanInstalledAgents();
      // Nếu _activeCliAgent chưa nằm trong danh sách hoặc rỗng, ưu tiên antigravity-cli rồi tới claude-cli
      if (_installedCliAgents.isNotEmpty) {
        final hasActive = _installedCliAgents.any((a) => a.id == _activeCliAgent);
        if (!hasActive) {
          final agy = _installedCliAgents.firstWhere(
            (a) => a.id.contains('antigravity') || a.binary.contains('agy'),
            orElse: () => _installedCliAgents.first,
          );
          _activeCliAgent = agy.id;
        }
      }
    } catch (_) {} finally {
      _isScanningCliAgents = false;
      notifyListeners();
    }
  }

  Future<void> loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null && cfg['ai_model'].toString().isNotEmpty) {
        final m = cfg['ai_model'].toString();
        if (!_isCli(m)) {
          _cloudAiModel = m;
        } else {
          _activeCliAgent = m;
        }
      }
      if (cfg['active_cli_agent'] != null && cfg['active_cli_agent'].toString().isNotEmpty) {
        _activeCliAgent = cfg['active_cli_agent'].toString();
      }
      if (cfg['engine_mode'] != null && cfg['engine_mode'].toString().isNotEmpty) {
        _engineMode = cfg['engine_mode'].toString() == 'cli' ? 'cli' : 'cloud';
      } else if (cfg['active_agent_engine'] != null) {
        final eng = cfg['active_agent_engine'].toString();
        if (_isCli(eng)) {
          _engineMode = 'cli';
          _activeCliAgent = eng;
        } else {
          _engineMode = 'cloud';
          _cloudAiModel = eng;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setActiveAgent(String agent) async {
    if (agent.isEmpty) return;
    if (_isCli(agent)) {
      await setActiveCliAgent(agent);
    } else {
      await setCloudAiModel(agent);
    }
  }

  Future<void> setActiveCliAgent(String cliAgentId) async {
    if (cliAgentId.isNotEmpty) {
      _activeCliAgent = cliAgentId;
      _engineMode = 'cli';
      notifyListeners();
      try {
        await _storage.setDefaultModel(cliAgentId);
        await _api.saveConfig({
          'active_cli_agent': cliAgentId,
          'engine_mode': 'cli',
          'active_agent_engine': cliAgentId,
        });
      } catch (_) {}
    }
  }

  Future<void> setCloudAiModel(String model) async {
    if (model.isNotEmpty) {
      _cloudAiModel = model;
      _engineMode = 'cloud';
      notifyListeners();
      try {
        await _storage.setDefaultModel(model);
        await _api.saveConfig({
          'ai_model': model,
          'engine_mode': 'cloud',
          'active_agent_engine': model,
        });
      } catch (_) {}
    }
  }

  void setGlobalAiModel(String model) {
    if (_isCli(model)) {
      setActiveCliAgent(model);
    } else {
      setCloudAiModel(model);
    }
  }

  Future<void> loadServers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _api.getServers();
      final savedId = await _storage.getActiveServerId();
      if (list.isNotEmpty) {
        if (savedId != null && savedId.isNotEmpty) {
          _selectedServer = list.firstWhere(
            (s) => s.id == savedId || s.serverIp == savedId,
            orElse: () => list.firstWhere((s) => s.isSelected, orElse: () => list.first),
          );
        } else {
          _selectedServer = list.firstWhere((s) => s.isSelected, orElse: () => list.first);
        }
        _servers = list.map((s) => s.copyWith(isSelected: s.id == _selectedServer!.id)).toList();
      } else {
        _servers = [];
        _selectedServer = null;
      }
      await loadGlobalConfig();
      // Asynchronously fetch pointing IPs for all servers
      _fetchServerIpsForAll();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _fetchServerIpsForAll() {
    for (final server in _servers) {
      fetchIpsForServer(server);
    }
  }

  Future<void> fetchIpsForServer(ServerModel server, {bool force = false}) async {
    if (!force && _serverIpsMap.containsKey(server.id) && _serverIpsMap[server.id]!.isNotEmpty) {
      return;
    }
    if (_loadingIpsServerIds.contains(server.id)) return;

    _loadingIpsServerIds.add(server.id);
    notifyListeners();

    try {
      final ips = await _ssh.getServerIps(
        host: server.serverIp,
        port: server.sshPort,
        user: server.sshUser,
        pass: server.sshPass,
        key: server.sshKey,
      );
      if (ips.isNotEmpty) {
        _serverIpsMap[server.id] = ips;
      } else if (server.serverIp.isNotEmpty) {
        _serverIpsMap[server.id] = [server.serverIp];
      }
    } catch (_) {
      if (server.serverIp.isNotEmpty) {
        _serverIpsMap[server.id] = [server.serverIp];
      }
    } finally {
      _loadingIpsServerIds.remove(server.id);
      notifyListeners();
    }
  }

  Future<bool> selectServer(ServerModel server) async {
    _selectedServer = server;
    await _storage.setActiveServerId(server.id);
    notifyListeners();

    try {
      final ok = await _api.selectServer(server.serverIp);
      if (ok) {
        await loadServers();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addOrUpdateServer(ServerModel server) async {
    try {
      final ok = await _api.updateServer(server);
      if (ok) {
        await loadServers();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteServer(String serverIp) async {
    try {
      final ok = await _api.deleteServer(serverIp);
      if (ok) {
        await loadServers();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}
