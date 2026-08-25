import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  bool _isLoading = false;
  String? _error;

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ServerProvider() {
    loadServers();
  }

  Future<void> loadServers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _api.getServers();
      _servers = list;

      final savedId = await _storage.getActiveServerId();
      if (list.isNotEmpty) {
        if (savedId != null) {
          _selectedServer = list.firstWhere(
            (s) => s.id == savedId || s.serverIp == savedId,
            orElse: () => list.first,
          );
        } else {
          _selectedServer = list.firstWhere((s) => s.isSelected, orElse: () => list.first);
        }
      } else {
        _selectedServer = null;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
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
