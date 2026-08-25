import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  static const String _keyGatewayUrl = 'gateway_url';
  static const String _keySecretToken = 'secret_token';
  static const String _keyActiveServerId = 'active_server_id';
  static const String _keyDefaultModel = 'default_ai_model';
  static const String _keyBiometricEnabled = 'biometric_enabled';

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  // Gateway URL
  Future<String> getGatewayUrl() async {
    await init();
    return _prefs.getString(_keyGatewayUrl) ?? 'http://127.0.0.1:8888';
  }

  Future<void> setGatewayUrl(String url) async {
    await init();
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    await _prefs.setString(_keyGatewayUrl, cleanUrl);
  }

  // Secret Token
  Future<String> getSecretToken() async {
    await init();
    return _prefs.getString(_keySecretToken) ?? '';
  }

  Future<void> setSecretToken(String token) async {
    await init();
    await _prefs.setString(_keySecretToken, token.trim());
  }

  // Active Server ID
  Future<String?> getActiveServerId() async {
    await init();
    return _prefs.getString(_keyActiveServerId);
  }

  Future<void> setActiveServerId(String id) async {
    await init();
    await _prefs.setString(_keyActiveServerId, id);
  }

  // Default AI Model
  Future<String> getDefaultModel() async {
    await init();
    return _prefs.getString(_keyDefaultModel) ?? 'glm-5.3';
  }

  Future<void> setDefaultModel(String model) async {
    await init();
    await _prefs.setString(_keyDefaultModel, model);
  }

  // Biometric Auth
  Future<bool> getBiometricEnabled() async {
    await init();
    return _prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await init();
    await _prefs.setBool(_keyBiometricEnabled, enabled);
  }
}
