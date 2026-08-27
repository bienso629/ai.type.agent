import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String _globalAiModel = 'glm-5.3';
  bool _isLoading = false;
  String? _error;

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  String get globalAiModel => _globalAiModel;
  String get currentAiModel {
    if (_globalAiModel.isNotEmpty) {
      return _globalAiModel;
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
  }

  Future<void> loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null && cfg['ai_model'].toString().isNotEmpty) {
        _globalAiModel = cfg['ai_model'].toString();
        notifyListeners();
      }
    } catch (_) {}
  }

  void setGlobalAiModel(String model) {
    if (model.isNotEmpty) {
      _globalAiModel = model;
      notifyListeners();
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
      notifyListeners();

      try {
        final ok = await _api.selectServer(server.serverIp, server);
        return ok;
      } catch (_) {
        return false;
      }
    }
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
}
