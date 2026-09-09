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
  String _activeAgent = 'glm-5.3';
  List<LocalCliAgent> _installedCliAgents = [];
  bool _isLoading = false;
  bool _isScanningCliAgents = false;
  String? _error;
  final Map<String, List<String>> _serverIpsMap = {};
  final Set<String> _loadingIpsServerIds = {};

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  String get globalAiModel => _cloudAiModel;
  String get cloudAiModel => _cloudAiModel;
  String get activeAgent => _activeAgent;
  List<LocalCliAgent> get installedCliAgents => _installedCliAgents;
  bool get isScanningCliAgents => _isScanningCliAgents;
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
    if (_activeAgent.isNotEmpty) {
      return _activeAgent;
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
  }

  bool _isCli(String name) {
    final n = name.toLowerCase();
    return n.contains('cli') || n == 'agy' || n == 'claude' || n == 'gemini';
  }

  Future<void> scanCliAgents({bool forceRefresh = false}) async {
    if (_installedCliAgents.isNotEmpty && !forceRefresh) return;
    _isScanningCliAgents = true;
    notifyListeners();

    try {
      _installedCliAgents = await _cliScanner.scanInstalledAgents();
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
        if (_isCli(m)) {
          _cloudAiModel = 'glm-5.3';
          _activeAgent = m;
        } else {
          _cloudAiModel = m;
        }
      }
      if (cfg['active_agent_engine'] != null && cfg['active_agent_engine'].toString().isNotEmpty) {
        _activeAgent = cfg['active_agent_engine'].toString();
      } else {
        _activeAgent = _cloudAiModel;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setActiveAgent(String agent) async {
    if (agent.isNotEmpty) {
      _activeAgent = agent;
      if (!_isCli(agent)) {
        _cloudAiModel = agent;
      }
      notifyListeners();
      try {
        await _storage.setDefaultModel(agent);
        if (_isCli(agent)) {
          await _api.saveConfig({'active_agent_engine': agent});
        } else {
          await _api.saveConfig({'active_agent_engine': agent, 'ai_model': agent});
        }
      } catch (_) {}
    }
  }

  void setGlobalAiModel(String model) {
    setActiveAgent(model);
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
