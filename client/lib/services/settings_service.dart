import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _keyBaseUrl = 'base_url';
  static const _keyToken = 'bearer_token';
  static const _keyThemeMode = 'theme_mode';

  final SharedPreferences _prefs;
  // On mobile, use encrypted storage for the token.
  // On web, flutter_secure_storage falls back to localStorage anyway,
  // so we just use SharedPreferences there.
  final FlutterSecureStorage? _secure;

  String _cachedToken = '';

  SettingsService._(this._prefs, this._secure, this._cachedToken);

  /// Initialize the service, loading the token from secure storage.
  static Future<SettingsService> create(SharedPreferences prefs) async {
    if (kIsWeb) {
      // On web, store token in SharedPreferences (no better option).
      final token = prefs.getString(_keyToken) ?? '';
      return SettingsService._(prefs, null, token);
    } else {
      const secure = FlutterSecureStorage(aOptions: AndroidOptions.defaultOptions);
      final token = await secure.read(key: _keyToken) ?? '';
      return SettingsService._(prefs, secure, token);
    }
  }

  /// For tests — uses SharedPreferences only, no secure storage.
  factory SettingsService.forTest(SharedPreferences prefs) {
    final token = prefs.getString(_keyToken) ?? '';
    return SettingsService._(prefs, null, token);
  }

  String get baseUrl => _prefs.getString(_keyBaseUrl) ?? '';
  String get token => _cachedToken;

  ThemeMode get themeMode {
    final val = _prefs.getString(_keyThemeMode);
    switch (val) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_keyBaseUrl, url);
    notifyListeners();
  }

  Future<void> setToken(String token) async {
    if (_secure != null) {
      await _secure.write(key: _keyToken, value: token);
    } else {
      await _prefs.setString(_keyToken, token);
    }
    _cachedToken = token;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final val = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
        ? 'dark'
        : 'system';
    await _prefs.setString(_keyThemeMode, val);
    notifyListeners();
  }
}
