import 'package:flutter/foundation.dart';
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
  static const String _keyAuthToken = 'auth_token';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserName = 'user_name';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyRememberMe = 'remember_me';
  static const String _keyCustomLogoPath = 'custom_logo_path';
  static const String _keyAppTitle = 'app_title';
  static const String _keyBrandTitle = 'brand_title';
  static const String _keyBrandSubtitle = 'brand_subtitle';
  static const String _keyVoiceEnabled = 'voice_enabled';
  static const String _keyVoiceName = 'voice_name';
  static const String _keyVoiceRate = 'voice_rate';

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  // Gateway URL
  Future<String> getGatewayUrl() async {
    await init();
    final saved = _prefs.getString(_keyGatewayUrl);
    if (kIsWeb) {
      if (saved == null || saved.isEmpty || saved.contains('127.0.0.1') || saved.contains('localhost')) {
        return '';
      }
      return saved;
    }
    return saved ?? 'http://127.0.0.1:8888';
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
    return _prefs.getString(_keyDefaultModel) ?? 'gemini-2.5-flash';
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

  // Custom App Logo Path
  Future<String?> getCustomLogoPath() async {
    await init();
    return _prefs.getString(_keyCustomLogoPath);
  }

  Future<void> setCustomLogoPath(String? path) async {
    await init();
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_keyCustomLogoPath);
    } else {
      await _prefs.setString(_keyCustomLogoPath, path.trim());
    }
  }

  // Custom App & Brand Titles
  Future<String?> getAppTitle() async {
    await init();
    return _prefs.getString(_keyAppTitle);
  }

  Future<void> setAppTitle(String? title) async {
    await init();
    if (title == null || title.trim().isEmpty) {
      await _prefs.remove(_keyAppTitle);
    } else {
      await _prefs.setString(_keyAppTitle, title.trim());
    }
  }

  Future<String?> getBrandTitle() async {
    await init();
    return _prefs.getString(_keyBrandTitle);
  }

  Future<void> setBrandTitle(String? title) async {
    await init();
    if (title == null || title.trim().isEmpty) {
      await _prefs.remove(_keyBrandTitle);
    } else {
      await _prefs.setString(_keyBrandTitle, title.trim());
    }
  }

  Future<String?> getBrandSubtitle() async {
    await init();
    return _prefs.getString(_keyBrandSubtitle);
  }

  Future<void> setBrandSubtitle(String? subtitle) async {
    await init();
    if (subtitle == null || subtitle.trim().isEmpty) {
      await _prefs.remove(_keyBrandSubtitle);
    } else {
      await _prefs.setString(_keyBrandSubtitle, subtitle.trim());
    }
  }

  // Voice TTS (Edge TTS)
  Future<bool> getVoiceEnabled() async {
    await init();
    return _prefs.getBool(_keyVoiceEnabled) ?? false;
  }

  Future<void> setVoiceEnabled(bool enabled) async {
    await init();
    await _prefs.setBool(_keyVoiceEnabled, enabled);
  }

  Future<String> getVoiceName() async {
    await init();
    return _prefs.getString(_keyVoiceName) ?? 'vi-VN-HoaiMyNeural';
  }

  Future<void> setVoiceName(String name) async {
    await init();
    await _prefs.setString(_keyVoiceName, name);
  }

  Future<String> getVoiceRate() async {
    await init();
    return _prefs.getString(_keyVoiceRate) ?? '+0%';
  }

  Future<void> setVoiceRate(String rate) async {
    await init();
    await _prefs.setString(_keyVoiceRate, rate);
  }

  // App Authentication
  Future<String?> getAuthToken() async {
    await init();
    return _prefs.getString(_keyAuthToken);
  }

  Future<void> setAuthToken(String? token) async {
    await init();
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyAuthToken);
    } else {
      await _prefs.setString(_keyAuthToken, token);
    }
  }

  Future<String?> getUserEmail() async {
    await init();
    return _prefs.getString(_keyUserEmail);
  }

  Future<void> setUserEmail(String? email) async {
    await init();
    if (email == null || email.isEmpty) {
      await _prefs.remove(_keyUserEmail);
    } else {
      await _prefs.setString(_keyUserEmail, email);
    }
  }

  Future<String?> getUserName() async {
    await init();
    return _prefs.getString(_keyUserName);
  }

  Future<void> setUserName(String? name) async {
    await init();
    if (name == null || name.isEmpty) {
      await _prefs.remove(_keyUserName);
    } else {
      await _prefs.setString(_keyUserName, name);
    }
  }

  Future<bool> isLoggedIn() async {
    await init();
    return _prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  Future<void> setLoggedIn(bool value) async {
    await init();
    await _prefs.setBool(_keyIsLoggedIn, value);
  }

  Future<bool> getRememberMe() async {
    await init();
    return _prefs.getBool(_keyRememberMe) ?? true;
  }

  Future<void> setRememberMe(bool value) async {
    await init();
    await _prefs.setBool(_keyRememberMe, value);
  }

  Future<void> clearAuth() async {
    await init();
    await _prefs.remove(_keyAuthToken);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserName);
    await _prefs.setBool(_keyIsLoggedIn, false);
  }

  static String sanitizeUserKey(String? user) {
    if (user == null || user.trim().isEmpty) {
      return '';
    }
    var u = user.trim();
    if (u.contains('@')) {
      u = u.split('@')[0];
    }
    final cleaned = u.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').toLowerCase();
    return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<String> getUserKey() async {
    await init();
    final email = await getUserEmail();
    if (email != null && email.isNotEmpty) {
      final key = sanitizeUserKey(email);
      if (key.isNotEmpty) return key;
    }
    final name = await getUserName();
    if (name != null && name.isNotEmpty) {
      final key = sanitizeUserKey(name);
      if (key.isNotEmpty) return key;
    }
    return '';
  }
}
