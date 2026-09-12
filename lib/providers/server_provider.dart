import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/cli_scanner_service.dart';
import '../core/services/native_ai_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  final CliScannerService _cliScanner = CliScannerService();

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String _cloudAiModel = 'glm-5.3';
  String _activeAgent = 'glm-5.3';
  List<String> _remoteModels = [];
  List<LocalCliAgent> _installedCliAgents = [];
  bool _isLoading = false;
  bool _isLoadingModels = false;
  bool _isScanningCliAgents = false;
  String? _error;
  String? _modelsError;

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  String get globalAiModel => _cloudAiModel;
  String get cloudAiModel => _cloudAiModel;
  String get activeAgent => _activeAgent;
  List<String> get remoteModels => _remoteModels;
  List<LocalCliAgent> get installedCliAgents => _installedCliAgents;
  bool get isLoadingModels => _isLoadingModels;
  bool get isScanningCliAgents => _isScanningCliAgents;
  String? get modelsError => _modelsError;

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
    fetchModels();
    scanCliAgents();
  }

  bool _isCli(String name) {
    final n = name.toLowerCase();
    return n.contains('cli') || n == 'agy' || n == 'claude' || n == 'gemini';
  }

  void _checkPreloadState() {
    if (_selectedServer == null && _isCli(_activeAgent)) {
      if (_activeAgent.contains('antigravity') || _activeAgent == 'agy') {
        NativeAiService.preloadAgyWorker();
      }
    } else {
      NativeAiService.disposeAgyWorkers();
    }
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

  Future<void> fetchModels({bool forceRefresh = false, String? customBaseUrl, String? customApiKey}) async {
    if (_remoteModels.isNotEmpty && !forceRefresh && customBaseUrl == null) return;
    _isLoadingModels = true;
    _modelsError = null;
    notifyListeners();

    try {
      final list = await _api.fetchRemoteModels(
        customBaseUrl: customBaseUrl,
        customApiKey: customApiKey,
      );
      if (list.isNotEmpty) {
        _remoteModels = list;
      }
    } catch (e) {
      _modelsError = e.toString();
    } finally {
      _isLoadingModels = false;
      notifyListeners();
    }
  }

  Future<void> loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null && cfg['ai_model'].toString().isNotEmpty) {
        final m = cfg['ai_model'].toString();
        // If ai_model was mistakenly set to a CLI name, sanitize it back to glm-5.3
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
      _checkPreloadState();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setActiveAgent(String agent) async {
    if (agent.isNotEmpty) {
      _activeAgent = agent;
      if (!_isCli(agent)) {
        _cloudAiModel = agent;
      }
      _checkPreloadState();
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

  Future<void> setGlobalAiModel(String model) async {
    await setActiveAgent(model);
  }

  Future<void> setCloudAiModel(String model) async {
    if (model.isNotEmpty && !_isCli(model)) {
      _cloudAiModel = model;
      if (!_isCli(_activeAgent)) {
        _activeAgent = model;
      }
      notifyListeners();
      try {
        await _storage.setDefaultModel(model);
        await _api.saveConfig({'ai_model': model, 'active_agent_engine': _activeAgent});
      } catch (_) {}
    }
  }

  Future<void> loadServers({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final list = await _api.getServers();
      final savedId = await _storage.getActiveServerId();
      if (list.isNotEmpty) {
        if (savedId != null && savedId.isNotEmpty && savedId != 'local') {
          final matches = list.where((s) => s.id == savedId || s.serverIp == savedId);
          if (matches.isNotEmpty) {
            _selectedServer = matches.first;
          } else {
            _selectedServer = null;
            await _storage.setActiveServerId('local');
          }
        } else {
          _selectedServer = null;
        }
        _servers = list.map((s) => s.copyWith(isSelected: _selectedServer != null && s.id == _selectedServer!.id)).toList();
      } else {
        _servers = [];
        _selectedServer = null;
      }
      await loadGlobalConfig();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> selectServer(ServerModel server) async {
    final isLocal = (server.id == 'local' || server.serverIp == '127.0.0.1' || server.serverIp == 'localhost');
    if (isLocal) {
      _selectedServer = null;
      await _storage.setActiveServerId('local');
      _servers = _servers.map((s) => s.copyWith(isSelected: false)).toList();
      _checkPreloadState();
      notifyListeners();
      try {
        final ok = await _api.selectServer('127.0.0.1', server);
        return ok;
      } catch (_) {
        return false;
      }
    } else {
      _selectedServer = server;
      await _storage.setActiveServerId(server.id);
      _servers = _servers.map((s) => s.copyWith(isSelected: s.id == server.id)).toList();
      _checkPreloadState();
      notifyListeners();

      try {
        final ok = await _api.selectServer(server.serverIp, server);
        return ok;
      } catch (_) {
        return false;
      }
    }
  }

  /// Tự động đồng bộ và chuyển sang server theo targetServer được lưu trong chat session
  Future<bool> selectServerByTarget(String? targetServer) async {
    final t = targetServer?.trim();
    if (t == null || t.isEmpty || t == 'Local Machine' || t == 'Local' || t == 'localhost' || t == '127.0.0.1') {
      if (_selectedServer != null) {
        return await selectServer(ServerModel(id: 'local', name: 'Local Machine', serverIp: '127.0.0.1'));
      }
      return true;
    }

    final matched = ServerModel.findMatchingServer(_servers, t);
    if (matched != null) {
      if (_selectedServer?.id != matched.id) {
        return await selectServer(matched);
      }
      return true;
    }

    return false;
  }

  Future<bool> addOrUpdateServer(ServerModel server) async {
    try {
      final ok = await _api.updateServer(server);
      if (ok) {
        await loadServers(silent: true);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteServer(String serverIdOrIp) async {
    _servers = _servers.where((s) => s.id != serverIdOrIp && s.serverIp != serverIdOrIp).toList();
    if (_selectedServer?.id == serverIdOrIp || _selectedServer?.serverIp == serverIdOrIp) {
      _selectedServer = null;
      await _storage.setActiveServerId('local');
    }
    notifyListeners();

    try {
      final ok = await _api.deleteServer(serverIdOrIp);
      if (ok) {
        await loadServers(silent: true);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<String> exportServers({bool includeFullConfig = false}) async {
    return await _api.exportServers(includeFullConfig: includeFullConfig);
  }

  Future<int> importServers(String jsonStr, {bool overwrite = false}) async {
    final count = await _api.importServers(jsonStr, overwrite: overwrite);
    await loadServers(silent: true);
    return count;
  }
}
