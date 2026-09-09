import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String _globalAiModel = 'gemini-2.5-flash';
  String? _customLogoPath;
  String _appTitle = 'AI Agent Chatbot';
  String _brandTitle = 'AI Agent';
  String _brandSubtitle = 'AI AGENT CHATBOT';
  bool _isLoading = false;
  String? _error;

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  String get globalAiModel => _globalAiModel;
  String? get customLogoPath => _customLogoPath;
  String get appTitle => _appTitle;
  String get brandTitle => _brandTitle;
  String get brandSubtitle => _brandSubtitle;
  String get currentAiModel {
    if (_selectedServer != null && _selectedServer!.aiModel.isNotEmpty) {
      return _selectedServer!.aiModel;
    }
    if (_globalAiModel.isNotEmpty) {
      return _globalAiModel;
    }
    return 'gemini-2.5-flash';
  }
  bool get isLoading => _isLoading;
  String? get error => _error;

  ServerProvider() {
    loadServers();
    loadGlobalConfig();
  }

  Future<void> loadGlobalConfig() async {
    try {
      final savedLogo = await _storage.getCustomLogoPath();
      if (savedLogo != null && savedLogo.isNotEmpty) {
        _customLogoPath = savedLogo;
      }
      final savedAppTitle = await _storage.getAppTitle();
      if (savedAppTitle != null && savedAppTitle.isNotEmpty) {
        _appTitle = savedAppTitle;
      }
      final savedBrandTitle = await _storage.getBrandTitle();
      if (savedBrandTitle != null && savedBrandTitle.isNotEmpty) {
        _brandTitle = savedBrandTitle;
      }
      final savedBrandSubtitle = await _storage.getBrandSubtitle();
      if (savedBrandSubtitle != null && savedBrandSubtitle.isNotEmpty) {
        _brandSubtitle = savedBrandSubtitle;
      }

      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null && cfg['ai_model'].toString().isNotEmpty) {
        _globalAiModel = cfg['ai_model'].toString();
      }
      if (cfg['custom_logo_path'] != null && cfg['custom_logo_path'].toString().isNotEmpty) {
        _customLogoPath = cfg['custom_logo_path'].toString();
      }
      if (cfg['app_title'] != null && cfg['app_title'].toString().isNotEmpty) {
        _appTitle = cfg['app_title'].toString();
      }
      if (cfg['brand_title'] != null && cfg['brand_title'].toString().isNotEmpty) {
        _brandTitle = cfg['brand_title'].toString();
      }
      if (cfg['brand_subtitle'] != null && cfg['brand_subtitle'].toString().isNotEmpty) {
        _brandSubtitle = cfg['brand_subtitle'].toString();
      }
      notifyListeners();
    } catch (_) {}
  }

  void setGlobalAiModel(String model) {
    if (model.isNotEmpty) {
      _globalAiModel = model;
      notifyListeners();
    }
  }

  Future<void> setCustomLogo(String? path) async {
    _customLogoPath = path;
    await _storage.setCustomLogoPath(path);
    notifyListeners();
  }

  Future<void> setAppTitle(String title) async {
    final clean = title.trim();
    _appTitle = clean.isEmpty ? 'AI Agent Chatbot' : clean;
    await _storage.setAppTitle(clean.isEmpty ? null : clean);
    notifyListeners();
  }

  Future<void> setBrandTitle(String title) async {
    final clean = title.trim();
    _brandTitle = clean.isEmpty ? 'AI Agent' : clean;
    await _storage.setBrandTitle(clean.isEmpty ? null : clean);
    notifyListeners();
  }

  Future<void> setBrandSubtitle(String subtitle) async {
    final clean = subtitle.trim();
    _brandSubtitle = clean.isEmpty ? 'AI AGENT CHATBOT' : clean;
    await _storage.setBrandSubtitle(clean.isEmpty ? null : clean);
    notifyListeners();
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
